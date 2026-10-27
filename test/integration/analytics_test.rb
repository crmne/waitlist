require "test_helper"

class AnalyticsTest < ActionDispatch::IntegrationTest
  def analytics
    meta = css_select('meta[name="analytics"]').first or return
    JSON.parse(meta["content"])
  end

  def signup(email, **attrs) = acme.signups.create!(email:, consent_text: Signup::CONSENT_TEXT, source: "form", **attrs)

  test "the confirmation counts under the product's page, never the page's token address" do
    referrer = signup("ana@example.com", confirmed_at: 1.day.ago)
    bea = signup("bea@example.com", referred_by: referrer)
    token = bea.generate_token_for(:confirmation)
    perform_enqueued_jobs { post "/confirm/#{token}" }

    assert_response :success
    assert_equal({ "url" => "https://acme.example/waitlist/confirmed", "events" => [["Waitlist: Confirmed", { "referral" => "yes" }]] }, analytics)
    assert_select 'script[src="https://stats.acme.example/js/script.js"]'
    assert_not_includes css_select('meta[name="analytics"]').first["content"], token
  end

  test "a referral link's form counts the visit without its code, and the hosted form's thanks a signup" do
    get "/p/acme?ref=SECRETCODE"
    assert_equal [["Referral: Visit", { "landing" => "waitlist form" }]], analytics["events"]
    assert_equal "https://acme.example/waitlist/form", analytics["url"]
    assert_not_includes response.body[/<meta name="analytics"[^>]*>/], "SECRETCODE"
    csp = response.headers["Content-Security-Policy"]
    assert_includes csp, "script-src 'self' https://stats.acme.example"
    assert_includes csp, "connect-src 'self' https://stats.acme.example"

    get "/p/acme/thanks"
    assert_equal [["Waitlist: Submitted", { "form" => "hosted" }]], analytics["events"]
  end

  test "nothing is counted in a frame, or for a product without analytics" do
    get "/p/acme?embed=1"
    assert_nil analytics
    assert_select "script[src^='https://stats']", 0

    get "/p/plain"
    assert_nil analytics
    assert_not_includes response.headers["Content-Security-Policy"], "script-src"
  end
end
