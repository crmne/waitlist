# Imports signups pulled from GetWaitlist (bin/getwaitlist-pull) into one
# product, without emailing anyone (docs/migration.md).
#
# Only signups GetWaitlist reports as verified are imported, as confirmed:
# they confirmed their address with GetWaitlist, so asking again would be
# spam. Unverified, removed and spam signups are skipped, as are addresses
# already here and anyone who left or was deleted here (Suppression).
# Original signup times are kept, so places in line are kept. Referral data,
# names, phone numbers and metadata are never read.
class GetwaitlistImport
  SOURCE = "getwaitlist"
  CONSENT_TEXT = "Signed up through the GetWaitlist form and confirmed the address there; imported without a new email."

  Plan = Struct.new(:import, :unverified, :removed, :spam, :existing, :suppressed, :invalid, keyword_init: true) do
    def counts = to_h.transform_values(&:size)
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
      plan.import.each do |row|
        signed_up = parse_time(row["created_at"]) || now
        @product.signups.create!(
          email: row["email"], answers: @product.clean_answers(answers_of(row)),
          source: SOURCE, consent_text: CONSENT_TEXT,
          created_at: signed_up, confirmed_at: now
        )
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
