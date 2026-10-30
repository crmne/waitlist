require "test_helper"

class ConfirmationRemindersTest < ActionDispatch::IntegrationTest
  test "new signups record the disclosed reminders and a fourteen day deadline" do
    product = acme
    product.update!(settings: product.settings.merge("confirmation_reminders" => true))
    get "/p/acme"
    assert_includes response.body, "two confirmation reminders after one day and one week"
    perform_enqueued_jobs do
      post "/p/acme/signups", params: { elapsed_ms: 5000, email: "dj@example.com" }, as: :json
    end
    assert_response :accepted
    signup = product.signups.sole
    assert_equal product.consent_text, signup.consent_text
    assert_in_delta signup.created_at + 14.days, signup.confirm_by, 1.second
    assert_includes ActionMailer::Base.deliveries.last.text_part.decoded, signup.confirm_by.strftime("%-d %B %Y")
    token = SignupMailer.confirmation_reminder(signup).message.text_part.decoded[%r{/confirm/(\S+)}, 1]
    get "/confirm/#{token}"
    assert_response :success
    assert_not signup.reload.confirmed?
    post "/confirm/#{token}"
    assert_response :success
    assert signup.reload.confirmed?
    travel 8.days do
      assert_no_enqueued_jobs(only: ConfirmationReminderJob) { ConfirmationRemindersJob.perform_now }
    end
  end
end
