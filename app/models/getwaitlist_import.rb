# Imports signups pulled from GetWaitlist (bin/getwaitlist-pull) into one
# product, without emailing anyone (docs/migration.md).
#
# Only signups GetWaitlist reports as verified are imported, as confirmed:
# they confirmed their address with GetWaitlist, so asking again would be
# spam. Unverified, removed and spam signups are skipped, as are addresses
# already here and anyone who left or was deleted here (Suppression).
# Original signup times are kept. Each person keeps their GetWaitlist
# referral token as their referral code, so old ?ref_id= links keep
# counting; who referred whom is rebuilt between imported people; and any
# GetWaitlist referral credit not covered by an imported person (someone who
# never confirmed there) is kept as imported_referrals, so nobody loses
# places. Names, phone numbers and metadata are never read.
class GetwaitlistImport
  SOURCE = "getwaitlist"
  CONSENT_TEXT = "Signed up through the GetWaitlist form and confirmed the address there; imported without a new email."

  CODE = /\A[A-Za-z0-9_-]{4,64}\z/

  Plan = Struct.new(:import, :unverified, :removed, :spam, :existing, :suppressed, :invalid, keyword_init: true) do
    def counts
      to_h.transform_values(&:size).merge(
        imported_with_referral_credit: import.count { |row| row["amount_referred"].to_i.positive? },
        referral_credit: import.sum { |row| row["amount_referred"].to_i }
      )
    end
  end

  def initialize(product:, rows:)
    @product = product
    @rows = rows
  end

  def plan
    plan = Plan.new(import: [], unverified: [], removed: [], spam: [], existing: [], suppressed: [], invalid: [])
    seen = Set.new
    existing = @product.signups.pluck(:email).to_set
    @rows.each do |row|
      email = Signup.normalize_value_for(:email, row["email"])
      bucket =
        if email.blank? || !email.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/) || seen.include?(email) then :invalid
        elsif row["removed_date"].present? then :removed
        elsif row["is_spam"] then :spam
        elsif !row["verified"] then :unverified
        elsif existing.include?(email) then :existing
        elsif Suppression.suppressed?(@product, email) then :suppressed
        else :import
        end
      seen << email if email.present?
      plan[bucket] << row.merge("email" => email)
    end
    plan
  end

  def apply!
    plan = self.plan
    now = Time.current
    Signup.transaction do
      by_token = {}
      plan.import.each do |row|
        signed_up = parse_time(row["created_at"]) || now
        token = row["referral_token"].to_s
        code = token if token.match?(CODE) && !@product.signups.exists?(referral_code: token)
        signup = @product.signups.create!(
          email: row["email"], answers: @product.clean_answers(answers_of(row)),
          source: SOURCE, consent_text: CONSENT_TEXT,
          created_at: signed_up, confirmed_at: now, referral_code: code
        )
        by_token[token] = [signup, row] if code
      end
      by_token.each_value do |signup, row|
        referrer = by_token[row["referred_by_signup_token"].to_s]&.first
        signup.update!(referred_by: referrer) if referrer && referrer != signup
      end
      by_token.each_value do |signup, row|
        rebuilt = signup.referrals.count
        signup.update!(referrals_count: rebuilt, imported_referrals: [row["amount_referred"].to_i - rebuilt, 0].max)
      end
    end
    plan
  end

  private

  # GetWaitlist sends answers as [{question_value:, answer_value:}].
  def answers_of(row)
    Array(row["answers"]).each_with_object({}) do |answer, answers|
      next unless answer.is_a?(Hash)
      answers[answer["question_value"].to_s.strip] = answer["answer_value"].to_s.strip
    end
  end

  # GetWaitlist's times look like "2026-09-27_12-30-51", in UTC.
  def parse_time(value)
    text = value.to_s
    if (m = text.match(/\A(\d{4})-(\d\d)-(\d\d)[_ T](\d\d)[-:](\d\d)[-:](\d\d)/))
      Time.utc(*m.captures.map(&:to_i))
    else
      Time.zone.parse(text)
    end
  rescue ArgumentError
    nil
  end
end
