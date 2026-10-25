require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  test "the admin needs the password, and is closed without one" do
    get "/admin"
    assert_response :unauthorized
    get "/admin", headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "wrong") }
    assert_response :unauthorized

    Rails.configuration.x.admin_password = nil
    get "/admin", headers: admin_headers
    assert_response :not_found
  end

  test "counts, approval, export and delete" do
    first = confirmed_signup("first@example.com", at: 2.days.ago)
    first.update!(answers: { "How many tracks do you have?" => "Over 20000" })
    confirmed_signup("=cmd@example.com", at: 1.day.ago)
    acme.signups.create!(email: "pending@example.com", consent_text: "test")

    get "/admin", headers: admin_headers
    assert_response :success
    assert_select "td.n", text: "2" # waiting
    assert_select "td.n", text: "1" # unconfirmed

    get "/admin/products/acme", headers: admin_headers
    assert_match "first@example.com", response.body
    assert_no_match "pending@example.com", response.body
    assert_select "button", text: "Approve"

    assert_enqueued_with(job: ApprovalJob) do
      post "/admin/signups/#{first.id}/approve", headers: admin_headers
    end
    assert first.reload.approved_at
    requests = fake_webhook
    perform_enqueued_jobs
    assert_equal "0b7e4f7a-8f6c-4c1e-9a43-2f1d8f0b5c11", first.reload.approval_reference
    assert first.approval_emailed_at && first.approval_acknowledged_at
    assert_equal ["http://hooks.internal/approved", "http://hooks.internal/sent"], requests.map(&:first)
    assert_equal "Bearer test-token", requests.first.last
    assert_equal({ "email" => "first@example.com", "reference" => "waitlist-#{first.referral_code}", "product" => "acme" }, requests.first[1])
    assert_equal({ "licence_id" => first.approval_reference, "reference" => "waitlist-#{first.referral_code}" }, requests.last[1])

    # The key goes out in the approval email and is stored nowhere.
    mail = ActionMailer::Base.deliveries.find { |m| m.subject == "Your Acme key" }
    assert_includes mail.text_part.body.to_s, "Paste this key: `KEY-123`"
    assert_includes mail.html_part.body.to_s, "KEY-123</code>"
    assert_includes mail.text_part.body.to_s, "valid until 23 April 2027"
    assert_not Signup.where("CAST(answers AS TEXT) LIKE '%KEY-123%' OR approval_reference LIKE '%KEY-123%'").exists?
    assert_not SolidQueue::Job.table_exists? && SolidQueue::Job.where("arguments LIKE '%KEY-123%'").exists?

    get "/admin/products/acme?status=approved", headers: admin_headers
    assert_match "Key sent", response.body

    get "/admin/products/acme/export", headers: admin_headers
    assert_equal "text/csv", response.media_type
    rows = CSV.parse(response.body)
    assert_equal "email", rows.first.first
    assert_includes rows.map(&:first), "'=cmd@example.com"
    assert_includes rows.find { _1.first == "first@example.com" }, "Over 20000"

    get "/admin/signups/#{first.id}/delete", headers: admin_headers
    assert_match "Delete first@example.com?", response.body
    delete "/admin/signups/#{first.id}", headers: admin_headers
    assert_not Signup.exists?(first.id)
    assert Suppression.suppressed?(acme, "first@example.com")
  end

  test "an unconfirmed person can't be approved" do
    pending = acme.signups.create!(email: "pending@example.com", consent_text: "test")
    post "/admin/signups/#{pending.id}/approve", headers: admin_headers
    assert_nil pending.reload.approved_at
  end

  test "an approval whose webhook was down, or whose email failed, can be tried again" do
    signup = confirmed_signup("dj@example.com")
    post "/admin/signups/#{signup.id}/approve", headers: admin_headers
    clear_enqueued_jobs
    fake_webhook(fail_with: 503)
    ApprovalJob.perform_now(signup)
    assert_nil signup.reload.approval_registered_at
    get "/admin/products/acme?status=approved", headers: admin_headers
    assert_match "Key not registered yet", response.body

    # The webhook works, but the email fails.
    requests = fake_webhook
    failing = Class.new(StandardError)
    original = SignupMailer.method(:approved)
    SignupMailer.define_singleton_method(:approved) { |*| raise failing, "SMTP down" }
    begin
      assert_raises(failing) { ApprovalJob.perform_now(signup) }
    ensure
      SignupMailer.define_singleton_method(:approved, original)
    end
    assert signup.reload.approval_registered_at
    assert signup.approval_failed_at
    assert_nil signup.approval_emailed_at
    get "/admin/products/acme?status=approved", headers: admin_headers
    assert_match "Key registered, email failed", response.body
    assert_select "button", text: "Try again"

    assert_enqueued_with(job: ApprovalJob, args: [signup]) do
      post "/admin/signups/#{signup.id}/retry_approval", headers: admin_headers
    end
    perform_enqueued_jobs
    assert signup.reload.approval_emailed_at
    assert_equal 1, ActionMailer::Base.deliveries.count { |m| m.subject == "Your Acme key" }
    assert_equal 3, requests.size # registered twice (idempotent), told once
  end

  test "a product with no approval step just records the approval" do
    plain = Product.find_by!(slug: "plain")
    signup = plain.signups.create!(email: "dj@example.com", consent_text: "t", confirmed_at: Time.current)
    assert_no_enqueued_jobs(only: ApprovalJob) { signup.approve! }
    assert_equal "approved", signup.approval_state
  end
end
