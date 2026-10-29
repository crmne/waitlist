require "test_helper"

class SignupExperimentTest < ActionDispatch::IntegrationTest
  def join(email = "dj@example.com", **labels)
    post "/p/acme/signups", params: { email:, elapsed_ms: 5000, **labels }, as: :json
    assert_response :accepted
  end

  test "the accepted signup saves its configured labels without a browser analytics event" do
    join(experiment: "headline-v1", variant: "discover")
    signup = acme.signups.sole
    assert_equal({ experiment: "headline-v1", variant: "discover" }, signup.experiment_properties)
    assert_nil response.headers["Set-Cookie"]

    # Another page load must not change the original signup's treatment.
    join(experiment: "headline-v1", variant: "prep")
    assert_equal "discover", signup.reload.variant
    assert_equal 1, acme.signups.count
  end

  test "a later visit cannot backfill an unknown original treatment" do
    join
    join(experiment: "headline-v1", variant: "prep")
    assert_empty acme.signups.sole.experiment_properties
  end

  test "unknown incomplete and malformed labels are dropped without refusing a signup" do
    [
      { experiment: "headline-v1", variant: "email@example.com" },
      { experiment: "unknown", variant: "prep" },
      { experiment: "headline-v1" },
      { variant: "prep" },
      { experiment: ["headline-v1"], variant: "prep" },
      { experiment: "headline-v1", variant: { value: "prep" } }
    ].each_with_index do |labels, index|
      join("dj#{index}@example.com", **labels)
      assert_nil acme.signups.order(:id).last.experiment
      assert_nil acme.signups.order(:id).last.variant
    end
    post "/p/plain/signups", params: { email: "dj@example.com", elapsed_ms: 5000, experiment: "headline-v1", variant: "prep" }, as: :json
    assert_response :accepted
    assert_empty Product.find_by!(slug: "plain").signups.sole.experiment_properties
  end

  test "quietly refused spam cannot become an attributed signup" do
    assert_no_difference "Signup.count" do
      join(experiment: "headline-v1", variant: "prep", website: "spam")
    end
  end

  test "confirmation in a new request carries only the saved labels and never identifiers" do
    join(experiment: "headline-v1", variant: "discover")
    token = acme.signups.sole.generate_token_for(:confirmation)
    post "/confirm/#{token}"
    assert_response :success
    meta = css_select('meta[name="analytics"]').sole["content"]
    analytics = JSON.parse(meta)
    assert_equal "https://acme.example/waitlist/confirmed", analytics.fetch("url")
    assert_equal [["Waitlist: Confirmed", { "referral" => "no", "experiment" => "headline-v1", "variant" => "discover" }]], analytics.fetch("events")
    assert_not_includes meta, token
    assert_not_includes meta, "dj@example.com"
    assert acme.signups.sole.confirmed?
    post "/confirm/#{token}"
    assert_response :not_found
  end

  test "admin totals count retained records from the experiment start independently of list filters" do
    start = Time.iso8601("2026-10-29T00:00:00Z")
    create = ->(email, **attributes) { acme.signups.create!(email:, consent_text: "test", created_at: start, **attributes) }
    create.call("a@example.com", experiment: "headline-v1", variant: "prep")
    create.call("b@example.com", experiment: "headline-v1", variant: "prep", confirmed_at: start, approved_at: start)
    create.call("c@example.com", experiment: "headline-v1", variant: "discover", confirmed_at: start)
    create.call("unknown@example.com")
    create.call("old@example.com", created_at: start - 1.second, confirmed_at: start + 1.hour)
    create.call("other@example.com", experiment: "other-v1", variant: "prep")
    confirmed_signup("another-product@example.com", product: Product.find_by!(slug: "plain"), at: start)

    get "/admin/products/acme?status=approved&q=nobody", headers: admin_headers
    assert_response :success
    rows = css_select(".experiment-report tbody tr").map { |row| row.css("td").map(&:text) }
    assert_equal [["prep", "2", "1", "1"], ["discover", "1", "1", "0"], ["Unattributed", "1", "0", "1"]], rows

    get "/admin/products/acme/export", headers: admin_headers
    rows = CSV.parse(response.body, headers: true)
    assert_equal "headline-v1", rows.find { |row| row["email"] == "a@example.com" }["experiment"]
    assert_equal "prep", rows.find { |row| row["email"] == "a@example.com" }["variant"]
    assert_nil rows.find { |row| row["email"] == "unknown@example.com" }["variant"]
  end

  test "closing an experiment excludes later signups but keeps later confirmations in its cohort" do
    boundary = Time.iso8601("2026-10-29T12:00:00Z")
    product = acme
    settings = product.settings.deep_dup
    settings["signup_experiments"]["headline-v1"]["ended_at"] = boundary.iso8601
    settings["signup_experiments"]["headline-v2"] = { "started_at" => boundary.iso8601, "variants" => ["original", "prep", "discover"] }
    product.update!(settings:)
    product.signups.create!(email: "old@example.com", consent_text: "test", created_at: boundary - 1.second,
      confirmed_at: boundary + 1.hour, experiment: "headline-v1", variant: "prep")
    product.signups.create!(email: "unknown-before@example.com", consent_text: "test", created_at: boundary - 1.second)
    product.signups.create!(email: "unknown-after@example.com", consent_text: "test", created_at: boundary)
    product.signups.create!(email: "new@example.com", consent_text: "test", created_at: boundary,
      experiment: "headline-v2", variant: "original")
    old, current = product.signup_experiment_reports
    assert_equal boundary, old[:ended_at]
    assert_equal 1, old[:rows].find { _1[:variant] == "prep" }[:confirmed]
    assert_equal 1, old[:rows].find { _1[:variant] == "Unattributed" }[:total]
    assert_nil current[:ended_at]
    assert_equal 1, current[:rows].find { _1[:variant] == "original" }[:total]
    assert_equal 1, current[:rows].find { _1[:variant] == "Unattributed" }[:total]
  end
end
