class Signup < ApplicationRecord
  # The line shown under the form and stored with each signup, so we can
  # show what someone agreed to.
  CONSENT_TEXT = "I agree to receive one email to confirm my address, and later an email when there is a place for me. " \
    "I can leave the list at any time."

  belongs_to :product

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  validates :email, presence: true, length: { maximum: 254 },
    format: { with: /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/ }, uniqueness: { scope: :product_id }
  validates :source, :consent_text, presence: true

  scope :unconfirmed, -> { where(confirmed_at: nil) }
  scope :confirmed, -> { where.not(confirmed_at: nil) }
  scope :waiting, -> { confirmed.where(approved_at: nil) }
  scope :approved, -> { where.not(approved_at: nil) }
  scope :in_line, -> { order(:created_at, :id) }

  # Neither token is stored. A confirmation link stops working once the
  # address is confirmed or after config.x.confirmation_validity; the leave
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

  # 1 for the first person waiting, by signup time.
  def place_in_line
    return unless confirmed? && approved_at.nil?
    product.signups.waiting.where("created_at < ? OR (created_at = ? AND id < ?)", created_at, created_at, id).count + 1
  end

  # Only someone confirming through the link gets here; imports set
  # confirmed_at directly, so they never notify.
  def confirm!
    return if confirmed?
    transaction do
      update!(confirmed_at: Time.current)
      Suppression.lift(product, email)
    end
    NotifyJoinedJob.perform_later(self) if product.notify_address
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
    ApprovalJob.perform_later(self) if product.licence_issuer
  end

  # Deletes the person and remembers only a digest of the address, so an
  # import can't add them back.
  def forget!
    transaction do
      Suppression.add(product, email)
      destroy!
    end
  end
end
