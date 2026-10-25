require "test_helper"

class JoinedNotificationTest < ActionDispatch::IntegrationTest
  def sign_up_and_confirm(email = "dj@example.com")
    perform_enqueued_jobs do
      post "/p/acme/signups", params: { elapsed_ms: 5000, email:, answers: { "What do you play on most?" => "Traktor" } }, as: :json
    end
    signup = acme.signups.find_by!(email:)
    ActionMailer::Base.deliveries.clear
    [signup, signup.generate_token_for(:confirmation)]
  end

  test "confirming emails the product's notify address once, with answers, place, count and an admin link" do
    confirmed_signup("first@example.com", at: 1.day.ago)
    signup, token = sign_up_and_confirm

    perform_enqueued_jobs { post "/confirm/#{token}" }
    assert_response :success
    mail = ActionMailer::Base.deliveries.sole
    assert_equal ["carmine@paolino.me"], mail.to
    assert_equal ["hello@example.com"], mail.from
    assert_equal "Acme waitlist: dj@example.com joined (#2)", mail.subject
    body = mail.text_part.body.to_s
    assert_includes body, "What do you play on most? Traktor"
    assert_includes body, "How many tracks do you have? (no answer)"
    assert_includes body, "Place in line: 2"
    assert_includes body, "Waiting now: 2"
    assert_includes body, "/admin/products/acme#signup-#{signup.id}"

    # The same link again, or confirm! again, sends nothing more.
    perform_enqueued_jobs { post "/confirm/#{token}" }
    perform_enqueued_jobs { signup.reload.confirm! }
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  test "signing up without confirming notifies nobody" do
    sign_up_and_confirm
    assert_empty ActionMailer::Base.deliveries
    assert_no_enqueued_jobs only: NotifyJoinedJob
  end

  test "a product with no notify address sends nothing, and someone who left before the job ran is skipped" do
    signup, token = sign_up_and_confirm
    acme.update!(notify_address: nil)
    perform_enqueued_jobs { post "/confirm/#{token}" }
    assert_empty ActionMailer::Base.deliveries

    acme.update!(notify_address: "carmine@paolino.me")
    other, other_token = sign_up_and_confirm("other@example.com")
    post "/confirm/#{other_token}"
    other.destroy!
    perform_enqueued_jobs
    assert_empty ActionMailer::Base.deliveries
  end

  test "products default to notifying carmine@paolino.me" do
    assert_equal "carmine@paolino.me", acme.notify_address
  end
end
