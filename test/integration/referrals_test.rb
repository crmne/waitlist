require "test_helper"

class ReferralsTest < ActionDispatch::IntegrationTest
  def join(email, ref: nil, confirm: true)
    perform_enqueued_jobs { post "/p/acme/signups", params: { email:, ref:, elapsed_ms: 5000 }.compact, as: :json }
    signup = acme.signups.find_by!(email:)
    perform_enqueued_jobs { post "/confirm/#{signup.generate_token_for(:confirmation)}" } if confirm
    signup.reload
  end

  test "a referral counts once, when the referred person confirms" do
    ana = join("ana@example.com")
    bea = join("bea@example.com", ref: ana.referral_code, confirm: false)
    assert_equal ana, bea.referred_by
    assert_equal 0, ana.reload.referrals_count

    perform_enqueued_jobs { post "/confirm/#{bea.generate_token_for(:confirmation)}" }
    assert_equal 1, ana.reload.referrals_count
    perform_enqueued_jobs { bea.reload.confirm! }
    # Signing up again with the same address changes nothing.
    join("bea@example.com", ref: ana.referral_code, confirm: false)
    assert_equal 1, ana.reload.referrals_count
  end

  test "old GetWaitlist links use ref_id" do
    ana = join("ana@example.com")
    perform_enqueued_jobs { post "/p/acme/signups", params: { email: "cai@example.com", ref_id: ana.referral_code, elapsed_ms: 5000 }, as: :json }
    assert_equal ana, acme.signups.find_by!(email: "cai@example.com").referred_by
  end

  test "no self-referral, no credit from an unconfirmed or deleted referrer, and leaving and rejoining counts nothing" do
    ana = join("ana@example.com")
    assert_nil join("ANA+again@example.com", ref: ana.referral_code).referred_by

    pending = join("pen@example.com", confirm: false)
    assert_nil join("dan@example.com", ref: pending.referral_code).referred_by

    eve = join("eve@example.com", ref: ana.referral_code)
    assert_equal 1, ana.reload.referrals_count
    eve.forget!
    assert_nil join("eve@example.com", ref: ana.referral_code).referred_by
    assert_equal 1, ana.reload.referrals_count

    gus = join("gus@example.com", ref: ana.referral_code, confirm: false)
    ana.forget!
    assert_nil gus.reload.referred_by_id
    perform_enqueued_jobs { post "/confirm/#{gus.generate_token_for(:confirmation)}" }
    assert gus.reload.confirmed?
  end

  test "each confirmed referral moves someone up five places" do
    people = (1..8).map { |i| confirmed_signup("p#{i}@example.com", at: (10 - i).days.ago) }
    last = people.last
    assert_equal 8, last.place_in_line
    last.update!(referrals_count: 1)
    assert_equal 3, last.place_in_line
    last.update!(referrals_count: 2)
    assert_equal 1, last.place_in_line
    assert_equal people.first, acme.line.second
    last.product.update!(places_per_referral: 3)
    last.update!(referrals_count: 1)
    assert_equal 5, last.place_in_line
  end

  test "the confirmed page and email show the person's link, and the referrer learns nothing about who joined" do
    ana = join("ana@example.com", confirm: false)
    mail = ActionMailer::Base.deliveries.last
    assert_includes mail.text_part.body.to_s, "/p/acme?ref=#{ana.referral_code}"
    assert_includes mail.text_part.body.to_s, "move up 5 places"

    post "/confirm/#{ana.generate_token_for(:confirmation)}"
    assert_select "input#referral-link[value$=?]", "/p/acme?ref=#{ana.referral_code}"
    assert_select "button[data-copy]", "Copy"
    assert_match "We never tell you who they are", response.body

    get "/p/acme?ref=#{ana.referral_code}"
    assert_select "input[name=ref][value=?]", ana.referral_code
  end

  test "the admin and the notification show referral counts" do
    ana = join("ana@example.com")
    ActionMailer::Base.deliveries.clear
    join("bea@example.com", ref: ana.referral_code)
    note = ActionMailer::Base.deliveries.find { |m| m.subject.include?("bea@example.com joined") }
    assert_includes note.text_part.body.to_s, "Joined through someone's link: yes"

    get "/admin/products/acme", headers: admin_headers
    assert_select "tr#signup-#{ana.id} td.n", text: "1"
  end
end
