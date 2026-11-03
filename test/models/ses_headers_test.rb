require "test_helper"

class SesHeadersTest < ActiveSupport::TestCase
  teardown { Rails.configuration.x.ses_configuration_set = nil }

  test "with a configuration set, every email names it and tags its product" do
    Rails.configuration.x.ses_configuration_set = "waitlist"
    signup = acme.signups.create!(email: "dj@example.com", consent_text: "test")
    mail = SignupMailer.confirmation(signup).message
    assert_equal "waitlist", mail["X-SES-CONFIGURATION-SET"].to_s
    assert_equal "product=acme", mail["X-SES-MESSAGE-TAGS"].to_s

    left = SignupMailer.left(acme, "dj@example.com").message
    assert_equal "product=acme", left["X-SES-MESSAGE-TAGS"].to_s
  end

  test "without one, no SES headers are added" do
    signup = acme.signups.create!(email: "dj@example.com", consent_text: "test")
    mail = SignupMailer.confirmation(signup).message
    assert_nil mail["X-SES-CONFIGURATION-SET"]
    assert_nil mail["X-SES-MESSAGE-TAGS"]
  end
end
