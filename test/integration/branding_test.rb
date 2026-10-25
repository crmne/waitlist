require "test_helper"

class BrandingTest < ActionDispatch::IntegrationTest
  test "every email is branded: sender name, logo, colours, footer with Impressum and leave link, and a text part" do
    signup = acme.signups.create!(email: "dj@example.com", consent_text: "t")
    mail = SignupMailer.confirmation(signup).message
    assert_equal "Acme <hello@acme.example>", mail[:from].value
    html = mail.html_part.body.to_s
    assert_includes html, "/brands/acme/logo.png"
    assert_includes html, "#6a4fd8"
    assert_includes html, "Acme GmbH · Example Street 1, 10115 Berlin"
    assert_includes html, "Leave the waitlist and delete my details"
    text = mail.text_part.body.to_s
    assert_includes text, "Leave the waitlist and delete my details: http"
    assert_includes text, "Acme GmbH"
    assert_includes mail["List-Unsubscribe"].to_s, "/leave/"

    plain = Product.find_by!(slug: "plain").signups.create!(email: "dj@example.com", consent_text: "t")
    plain_html = SignupMailer.confirmation(plain).message.html_part.body.to_s
    assert_no_match(/<img/, plain_html)
    assert_includes plain_html, ">Plain</a>"
  end

  test "leaving sends one branded confirmation that the details are gone" do
    signup = acme.signups.create!(email: "dj@example.com", consent_text: "t", confirmed_at: Time.current)
    perform_enqueued_jobs { post "/leave/#{signup.generate_token_for(:leave)}" }
    mail = ActionMailer::Base.deliveries.sole
    assert_equal "You've left the Acme waitlist", mail.subject
    assert_equal ["dj@example.com"], mail.to
    assert_includes mail.text_part.body.to_s, "have been deleted"
    assert_not Signup.exists?(signup.id)
  end

  test "brand files are served from the brand folder only" do
    get "/brands/acme/logo.png"
    assert_response :success
    assert_equal "image/png", response.media_type
    get "/brands/acme/token"
    assert_response :not_found
    get "/brands/acme/approval.md"
    assert_response :not_found
    get "/brands/acme/..%2Fproducts.yml"
    assert_response :not_found
  end
end
