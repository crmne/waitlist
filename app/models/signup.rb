class Signup < ApplicationRecord
  # The line shown under the form and stored with each signup, so we can
  # show what someone agreed to.
  CONSENT_TEXT = "I agree to receive one email to confirm my address, and later an email when there is a place for me. " \
    "I can leave the list at any time."

  FOLLOW_UP_COLUMNS = [
    { checked: :approval_follow_up_checked_at, sent: :approval_follow_up_sent_at, failed: :approval_follow_up_failed_at },
    { checked: :approval_follow_up_second_checked_at, sent: :approval_follow_up_second_sent_at, failed: :approval_follow_up_second_failed_at }
  ].freeze

  CONFIRMATION_REMINDER_DELAYS = [1.day, 7.days].freeze
  CONFIRMATION_REMINDER_COLUMNS = [
    { checked: :confirmation_reminder_checked_at, sent: :confirmation_reminder_sent_at, failed: :confirmation_reminder_failed_at },
    { checked: :confirmation_reminder_second_checked_at, sent: :confirmation_reminder_second_sent_at, failed: :confirmation_reminder_second_failed_at }
  ].freeze

  def self.confirmation_reminder_columns(step)
    raise ArgumentError, "reminder step must be 1 or 2" unless [1, 2].include?(step)
    CONFIRMATION_REMINDER_COLUMNS.fetch(step - 1)
  end

  def self.follow_up_columns(step)
    raise ArgumentError, "follow-up step must be 1 or 2" unless [1, 2].include?(step)
    FOLLOW_UP_COLUMNS.fetch(step - 1)
  end

  belongs_to :product
  belongs_to :referred_by, class_name: "Signup", optional: true
  has_many :referrals, class_name: "Signup", foreign_key: :referred_by_id, dependent: :nullify, inverse_of: :referred_by

  before_create :assign_referral_code
  before_create :set_confirmation_deadline

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  validates :email, presence: true, length: { maximum: 254 },
    format: { with: /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/ }, uniqueness: { scope: :product_id }
  validates :source, :consent_text, presence: true
  validates :experiment, :variant, length: { maximum: 64 }, allow_nil: true

  def experiment_properties
    experiment.present? && variant.present? ? { experiment:, variant: } : {}
  end

  scope :unconfirmed, -> { where(confirmed_at: nil) }
  scope :confirmed, -> { where.not(confirmed_at: nil) }
  scope :waiting, -> { confirmed.where(approved_at: nil) }
  scope :approved, -> { where.not(approved_at: nil) }
  scope :in_line, -> { order(:created_at, :id) }

  # Neither token is stored. A confirmation link stops working once the
  # address is confirmed or the unconfirmed record is deleted (RetentionJob,
  # well before config.x.confirmation_validity); the leave
  # link works until the person is deleted.
  generates_token_for :confirmation, expires_in: Rails.configuration.x.confirmation_validity do
    confirmed_at
  end
  generates_token_for :leave do
    email
  end

  def status
    if approved_at then "approved"
    elsif confirmed_at then "waiting"
    else "unconfirmed"
    end
  end

  def confirmed? = confirmed_at.present?

  def confirmation_deadline = confirm_by || (created_at || Time.current) + product.unconfirmed_retention

  def confirmation_reminders_enabled?
    product.confirmation_reminders? && %w[site form].include?(source) && reminder_sent_at.nil?
  end

  # 1 for the first person waiting (Product#line).
  def place_in_line
    return unless confirmed? && approved_at.nil?
    product.line.index { |signup| signup.id == id }&.+(1)
  end

  # Only someone confirming through the link gets here; imports set
  # confirmed_at directly, so they never notify.
  def confirm!
    return if confirmed?
    transaction do
      update!(confirmed_at: Time.current, confirm_by: nil)
      Suppression.lift(product, email)
    end
    credit_referrer
    NotifyJoinedJob.perform_later(self) if product.notify_address
  end

  # Confirmed referrals made here, plus credit carried over from GetWaitlist.
  def effective_referrals = referrals_count + imported_referrals

  # The address minus any +tag, for spotting self-referrals.
  def self.base_address(email)
    local, domain = email.to_s.downcase.split("@", 2)
    "#{local.to_s.split("+", 2).first}@#{domain}"
  end

  # The person whose link brought a new signup here, or nil: someone
  # confirmed on this product, not the same address (ignoring +tags), and
  # never for an address that left before (so leaving and rejoining can't
  # be used to count twice).
  def self.referrer_for(product, code, email)
    return if code.blank? || Suppression.suppressed?(product, email)
    referrer = product.signups.confirmed.find_by(referral_code: code.to_s.strip)
    referrer unless referrer.nil? || base_address(referrer.email) == base_address(email)
  end

  def can_send_confirmation?
    !confirmed? && (confirmation_sent_at.nil? || confirmation_sent_at < Rails.configuration.x.confirmation_resend_after.ago)
  end

  # Approval is the owner's decision, from the admin. A product with an
  # approval step (`approval` in config/products.yml) gets it run as a job.
  def approve!
    raise ArgumentError, "only someone who confirmed can be approved" unless confirmed?
    return if approved_at
    update!(approved_at: Time.current)
    ApprovalJob.perform_later(self) if product.on_approve
  end

  # Where the product's approval step stands, for the admin: nil (not
  # approved), "approved" (no approval step), "pending" (not registered
  # yet), "registered" (registered, no email from here), "failed" (the
  # approval email failed) or "sent".
  def approval_state
    return unless approved_at
    return "approved" unless product.on_approve
    return "sent" if approval_emailed_at
    return "failed" if approval_failed_at
    approval_registered_at ? "registered" : "pending"
  end

  # Approved, but the approval step didn't finish: the admin can try again.
  def approval_retryable? = %w[pending failed].include?(approval_state)

  # Deletes the person and remembers only a digest of the address, so an
  # import can't add them back.
  def forget!
    transaction do
      Suppression.add(product, email)
      destroy!
    end
  end

  private

  def set_confirmation_deadline
    self.confirm_by ||= confirmation_deadline if !confirmed? && confirmation_reminders_enabled?
  end

  def assign_referral_code
    self.referral_code ||= loop do
      code = SecureRandom.alphanumeric(10)
      break code unless Signup.exists?(product_id:, referral_code: code)
    end
  end

  # A referral counts once, when the referred person confirms, and only if
  # the referrer is still here and confirmed.
  def credit_referrer
    return unless referred_by_id
    Signup.confirmed.where(id: referred_by_id).update_all("referrals_count = referrals_count + 1")
  end
end
