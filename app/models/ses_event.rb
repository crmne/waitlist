# What SES tells us about mail we sent (event publishing through SNS, or
# identity notifications): a complaint or a permanent bounce suppresses the
# address for the product and forgets its signup, sending nothing to them.
# Transient and undetermined bounces, deliveries and anything else are only
# logged (production keeps no logs, so in practice they are dropped).
#
# The product comes from the `product` message tag the mailer sets
# (ApplicationMailer, with SES_CONFIGURATION_SET); without a known tag,
# every product holding the address is affected.
#
# Repeating an event changes nothing: the suppression already exists, the
# signup is already gone, and a signup made after the message was sent is
# a fresh consent that an old complaint or bounce never removes.
class SesEvent
  def self.handle(event) = new(event).handle

  def initialize(event)
    @event = event.is_a?(Hash) ? event : {}
  end

  # Returns the number of signups forgotten.
  def handle
    case kind
    when "Complaint"
      # "not-spam" is a provider taking a complaint back: nothing to do.
      return 0 if @event.dig("complaint", "complaintFeedbackType") == "not-spam"
      act(recipients("complaint", "complainedRecipients"))
    when "Bounce"
      return act(recipients("bounce", "bouncedRecipients")) if @event.dig("bounce", "bounceType") == "Permanent"
      log "#{@event.dig("bounce", "bounceType") || "unknown"} bounce, kept"
      0
    else
      0
    end
  end

  private

  def kind = @event["eventType"] || @event["notificationType"]

  def recipients(section, list)
    Array(@event.dig(section, list)).filter_map do |recipient|
      address(recipient["emailAddress"]) if recipient.is_a?(Hash)
    end.uniq
  end

  def address(value)
    Mail::Address.new(value.to_s).address.to_s.strip.downcase.presence
  rescue Mail::Field::ParseError
    nil
  end

  def act(emails)
    sent_at = Time.iso8601(@event.dig("mail", "timestamp").to_s) rescue Time.current
    forgotten = emails.sum do |email|
      products_for(email).count do |product|
        signup = product.signups.find_by(email:)
        next false if signup && signup.created_at > sent_at
        signup ? signup.forget! : Suppression.add(product, email)
        signup.present?
      end
    end
    log "#{kind.downcase}, #{forgotten} signup(s) forgotten"
    forgotten
  end

  def products_for(email)
    tagged = Product.find_by(slug: Array(@event.dig("mail", "tags", "product")).first.to_s)
    tagged ? [tagged] : Product.where(id: Signup.where(email:).select(:product_id)).to_a
  end

  # Never the address: only the kind of event and a count.
  def log(text) = Rails.logger.info("SES event: #{text}")
end
