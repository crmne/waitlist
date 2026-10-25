require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  FakeIssuer = Struct.new(:result) do
    def issue(_signup) = result.is_a?(Exception) ? raise(result) : result
  end

  def with_issuer(issuer)
    original = LicenceIssuers.method(:for)
    LicenceIssuers.define_singleton_method(:for) { |_name| issuer }
    yield
  ensure
    LicenceIssuers.define_singleton_method(:for, original)
  end

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
    with_issuer(FakeIssuer.new("0b7e4f7a-8f6c-4c1e-9a43-2f1d8f0b5c11")) { perform_enqueued_jobs }
    assert_equal "0b7e4f7a-8f6c-4c1e-9a43-2f1d8f0b5c11", first.reload.licence_reference
    assert first.licence_issued_at
    get "/admin/products/acme?status=approved", headers: admin_headers
    assert_match "Key registered, waiting to be sent", response.body

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

  test "an approval whose key wasn't registered can be tried again" do
    signup = confirmed_signup("dj@example.com")
    post "/admin/signups/#{signup.id}/approve", headers: admin_headers
    clear_enqueued_jobs
    with_issuer(FakeIssuer.new(LicenceIssuers::AcmeLicence::Error.new("down"))) do
      ApprovalJob.perform_now(signup)
    end
    assert_nil signup.reload.licence_issued_at

    get "/admin/products/acme?status=approved", headers: admin_headers
    assert_match "Key not registered yet", response.body
    assert_enqueued_with(job: ApprovalJob, args: [signup]) do
      post "/admin/signups/#{signup.id}/register_licence", headers: admin_headers
    end
    with_issuer(FakeIssuer.new("0b7e4f7a-8f6c-4c1e-9a43-2f1d8f0b5c11")) { perform_enqueued_jobs }
    assert signup.reload.licence_issued_at
  end
end
