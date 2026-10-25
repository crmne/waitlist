require "test_helper"

class GetwaitlistImportTest < ActiveSupport::TestCase
  def rows
    [
      { "email" => "A@example.com", "created_at" => "2026-09-27_12-30-51", "verified" => true,
        "answers" => [{ "question_value" => "What do you play on most?", "answer_value" => " Traktor" }], "amount_referred" => 3, "phone" => "123" },
      { "email" => "b@example.com", "created_at" => "2026-09-28_10-00-00", "verified" => false },
      { "email" => "c@example.com", "created_at" => "2026-09-28_11-00-00", "verified" => true, "removed_date" => "2026-10-01" },
      { "email" => "d@example.com", "created_at" => "2026-09-28_12-00-00", "verified" => true, "is_spam" => true },
      { "email" => "here@example.com", "created_at" => "2026-09-29_12-00-00", "verified" => true },
      { "email" => "left@example.com", "created_at" => "2026-09-29_13-00-00", "verified" => true },
      { "email" => "a@example.com", "created_at" => "2026-09-30_12-00-00", "verified" => true },
      { "email" => "nope", "verified" => true }
    ]
  end

  setup do
    confirmed_signup("here@example.com")
    Suppression.add(acme, "left@example.com")
  end

  test "a dry run writes nothing and counts every reason" do
    counts = GetwaitlistImport.new(product: acme, rows:).plan.counts
    assert_equal({ import: 1, unverified: 1, removed: 1, spam: 1, existing: 1, suppressed: 1, invalid: 2,
      imported_with_referral_credit: 1, referral_credit: 3 }, counts)
    assert_equal 1, Signup.count
  end

  test "applying imports only verified people, as confirmed, with their signup time and answers, and emails nobody" do
    assert_no_enqueued_jobs do
      GetwaitlistImport.new(product: acme, rows:).apply!
    end
    imported = acme.signups.find_by!(email: "a@example.com")
    assert imported.confirmed?
    assert_equal Time.utc(2026, 9, 27, 12, 30, 51), imported.created_at
    assert_equal({ "What do you play on most?" => "Traktor" }, imported.answers)
    assert_equal "getwaitlist", imported.source
    assert_equal 1, imported.place_in_line
    assert_equal 2, Signup.count

    # Running it again adds nobody.
    assert_equal 0, GetwaitlistImport.new(product: acme, rows:).apply!.import.size
  end

  test "referral codes, who referred whom and leftover credit come across, so old links keep counting" do
    rows = [
      { "email" => "ref@example.com", "created_at" => "2026-09-27_10-00-00", "verified" => true, "referral_token" => "AAAAAAAAA", "amount_referred" => 3 },
      { "email" => "kid@example.com", "created_at" => "2026-09-28_10-00-00", "verified" => true, "referral_token" => "BBBBBBBBB", "referred_by_signup_token" => "AAAAAAAAA" },
      { "email" => "never@example.com", "created_at" => "2026-09-28_11-00-00", "verified" => false, "referral_token" => "CCCCCCCCC", "referred_by_signup_token" => "AAAAAAAAA" }
    ]
    GetwaitlistImport.new(product: acme, rows:).apply!
    referrer = acme.signups.find_by!(email: "ref@example.com")
    kid = acme.signups.find_by!(email: "kid@example.com")
    assert_equal "AAAAAAAAA", referrer.referral_code
    assert_equal referrer, kid.referred_by
    assert_equal [1, 2, 3], [referrer.referrals_count, referrer.imported_referrals, referrer.effective_referrals]
    # An old GetWaitlist link (ref_id=AAAAAAAAA) now credits the same person.
    assert_equal referrer, Signup.referrer_for(acme, "AAAAAAAAA", "new@example.com")
  end
end
