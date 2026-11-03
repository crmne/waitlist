require "test_helper"

class OneClickUnsubscribeTest < ActionDispatch::IntegrationTest
  setup do
    @forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown { ActionController::Base.allow_forgery_protection = @forgery }

  test "emails with a leave link offer RFC 8058 one-click unsubscribe at that link" do
    signup = acme.signups.create!(email: "dj@example.com", consent_text: "test")
    mail = SignupMailer.confirmation(signup).message
    assert_equal "List-Unsubscribe=One-Click", mail["List-Unsubscribe-Post"].to_s
    assert_match %r{\A<https?://[^>]+/leave/[^>]+>\z}, mail["List-Unsubscribe"].to_s
  end

  test "a provider's one-click POST leaves without a session, a CSRF token or a goodbye email" do
    signup = confirmed_signup
    token = signup.generate_token_for(:leave)

    assert_no_enqueued_emails do
      post "/leave/#{token}", params: "List-Unsubscribe=One-Click",
        headers: { "Content-Type" => "application/x-www-form-urlencoded" }
    end
    assert_response :success
    assert_nil response.headers["Set-Cookie"]
    assert_not Signup.exists?(signup.id)
    assert Suppression.suppressed?(acme, "dj@example.com")
  end

  test "one-click as multipart form data also sends nothing" do
    signup = confirmed_signup
    assert_no_enqueued_emails do
      post "/leave/#{signup.generate_token_for(:leave)}", params: { "List-Unsubscribe" => "One-Click" },
        headers: { "Content-Type" => "multipart/form-data" }
    end
    assert_not Signup.exists?(signup.id)
  end

  test "leaving by hand on the page still sends the one goodbye email" do
    signup = confirmed_signup
    assert_enqueued_emails(1) { post "/leave/#{signup.generate_token_for(:leave)}" }
    assert_not Signup.exists?(signup.id)
  end

  test "a one-click POST with a bad token changes nothing" do
    signup = confirmed_signup
    assert_no_enqueued_emails { post "/leave/nonsense", params: { "List-Unsubscribe" => "One-Click" } }
    assert_response :success
    assert Signup.exists?(signup.id)
  end
end
