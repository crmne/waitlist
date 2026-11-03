# Where Amazon SNS posts SES's bounce and complaint events (SesEvent),
# and the one subscription confirmation for that topic. Answers 404 until
# SES_EVENTS_TOPIC_ARN names the topic, 403 to anything SnsMessage can't
# verify, and 200 once a message is handled or repeated, so SNS retries
# only failures. Named as Chat with Work's hook is.
class Hooks::SesEventsController < ApplicationController
  MAX_BODY = 256.kilobytes

  skip_forgery_protection
  before_action { request.session_options[:skip] = true }

  def create
    topic_arn = Rails.configuration.x.ses_events_topic_arn.presence or return head(:not_found)
    return head(:content_too_large) if request.content_length.to_i > MAX_BODY

    message = SnsMessage.verify!(request.body.read(MAX_BODY + 1), topic_arn:)
    return head(:ok) unless message.first_delivery?
    case message.type
    when "SubscriptionConfirmation" then confirm(message)
    when "Notification" then SesEvent.handle(event(message.message))
    end
    head :ok unless performed?
  rescue SnsMessage::Invalid
    head :forbidden
  end

  private

  def confirm(message)
    message.confirm_subscription!
  rescue SnsMessage::Invalid
    head :bad_gateway
  end

  # SES also posts a plain-text test message when the destination is set up.
  def event(text)
    JSON.parse(text.to_s)
  rescue JSON::ParserError
    nil
  end
end
