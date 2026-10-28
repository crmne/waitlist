require "test_helper"

class SignupFlowTest < ActionDispatch::IntegrationTest
  test "the hosted form signs someone up, emails a confirmation link and sets no cookie" do
    get "/p/acme"
    assert_response :success
    assert_nil response.headers["Set-Cookie"]
    assert_match "Join the Acme waitlist", response.body

    perform_enqueued_jobs do
      post "/p/acme/signups", params: { elapsed_ms: 5000, email: " DJ@Example.com ", answers: { "Where do you play most?" => "At home", "Made up?" => "x" } }
    end
    assert_redirected_to "/p/acme/thanks"
    assert_nil response.headers["Set-Cookie"]

    signup = acme.signups.sole
    assert_equal "dj@example.com", signup.email
    assert_equal({ "Where do you play most?" => "At home" }, signup.answers)
    assert_not signup.confirmed?
    assert_equal Signup::CONSENT_TEXT, signup.consent_text
    assert_equal "form", signup.source

    mail = ActionMailer::Base.deliveries.sole
    assert_equal ["dj@example.com"], mail.to
    assert_equal ["hello@acme.example"], mail.from
    assert_equal "Confirm your place on the Acme waitlist", mail.subject
    confirm = mail.text_part.body.to_s[%r{https?://\S+/confirm/\S+}]
    leave = mail.text_part.body.to_s[%r{https?://\S+/leave/\S+}]
    assert confirm && leave
    assert_includes mail["List-Unsubscribe"].to_s, "/leave/"

    # Following the link only shows a button; a mail scanner can't confirm.
    get URI(confirm).path
    assert_response :success
    assert_not signup.reload.confirmed?

    post URI(confirm).path
    assert_response :success
    assert_match "You're number 1", response.body
    assert signup.reload.confirmed?

    # The confirmation link stops working once used.
    get URI(confirm).path
    assert_response :not_found
  end

  test "a signup from the product site's own form is counted as the site's" do
    post "/p/acme/signups", params: { elapsed_ms: 5000, email: "site@example.com" }, as: :json, headers: { "Origin" => "https://acme.example" }
    assert_response :accepted
    assert_equal "site", acme.signups.sole.source
  end

  test "signing up again sends no second email inside the resend window and says the same thing" do
    perform_enqueued_jobs do
      2.times { post "/p/acme/signups", params: { elapsed_ms: 5000, email: "dj@example.com" }, as: :json }
    end
    assert_response :accepted
    assert_equal({ "status" => "check_email" }, response.parsed_body)
    assert_equal 1, ActionMailer::Base.deliveries.size

    travel 20.minutes do
      perform_enqueued_jobs { post "/p/acme/signups", params: { elapsed_ms: 5000, email: "dj@example.com" }, as: :json }
    end
    assert_equal 2, ActionMailer::Base.deliveries.size

    confirmed_signup("old@example.com")
    perform_enqueued_jobs { post "/p/acme/signups", params: { elapsed_ms: 5000, email: "old@example.com" }, as: :json }
    assert_response :accepted
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  test "the JSON endpoint answers CORS only for the product's own sites" do
    process :options, "/p/acme/signups", headers: { "Origin" => "https://acme.example" }
    assert_response :no_content
    assert_equal "https://acme.example", response.headers["Access-Control-Allow-Origin"]

    post "/p/acme/signups", params: { elapsed_ms: 5000, email: "dj@example.com" }, as: :json, headers: { "Origin" => "https://evil.example" }
    assert_nil response.headers["Access-Control-Allow-Origin"]
  end

  test "a bad address is refused, and the honeypot pretends to work" do
    post "/p/acme/signups", params: { elapsed_ms: 5000, email: "not an email" }, as: :json
    assert_response :unprocessable_content
    assert_equal "error", response.parsed_body["status"]

    post "/p/acme/signups", params: { elapsed_ms: 5000, email: "bot@example.com", website: "spam" }
    assert_redirected_to "/p/acme/thanks"
    assert_equal 0, Signup.count
    assert_no_enqueued_emails
  end

  test "the hosted form may be framed only by the product's sites" do
    get "/p/acme?embed=1"
    assert_nil response.headers["X-Frame-Options"]
    assert_includes response.headers["Content-Security-Policy"], "form-action 'self'; frame-ancestors 'self' https://acme.example"
    acme.update!(thanks_url: "https://acme.example/thanks")
    get "/p/acme"
    assert_includes response.headers["Content-Security-Policy"], "form-action 'self' https://acme.example;"
  end

  test "an unknown product is a 404" do
    get "/p/nothing"
    assert_response :not_found
  end

  test "leaving deletes the person and keeps only a digest that blocks imports" do
    signup = confirmed_signup
    token = signup.generate_token_for(:leave)
    get "/leave/#{token}"
    assert_response :success
    assert Signup.exists?(signup.id)

    post "/leave/#{token}"
    assert_response :success
    assert_nil response.headers["Set-Cookie"]
    assert_not Signup.exists?(signup.id)
    assert Suppression.suppressed?(acme, "dj@example.com")
    assert_not Suppression.where("email_digest LIKE ?", "%example%").exists?

    # Signing up and confirming again lifts it.
    perform_enqueued_jobs { post "/p/acme/signups", params: { elapsed_ms: 5000, email: "dj@example.com" } }
    acme.signups.sole.confirm!
    assert_not Suppression.suppressed?(acme, "dj@example.com")
  end

  test "signup rows hold no address, user agent or referrer" do
    columns = Signup.column_names.join(" ")
    %w[ip remote user_agent referer landing].each { |word| assert_no_match(/#{word}/, columns) }
  end
end
