# Signs SNS messages the way Amazon does, with a throwaway key and a
# certificate served from a stubbed sns.eu-central-1.amazonaws.com.
module SnsTestHelper
  TOPIC_ARN = "arn:aws:sns:eu-central-1:123456789012:waitlist-ses-events"
  CERT_URL = "https://sns.eu-central-1.amazonaws.com/SimpleNotificationService-0123456789abcdef.pem"
  SNS_KEY = OpenSSL::PKey::RSA.new(2048)
  SNS_CERT = OpenSSL::X509::Certificate.new.tap do |cert|
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=sns.amazonaws.com")
    cert.public_key = SNS_KEY.public_key
    cert.not_before = 1.day.ago
    cert.not_after = 1.year.from_now
    cert.sign(SNS_KEY, OpenSSL::Digest.new("SHA256"))
  end

  def stub_sns(requests = [], subscribe_code: "200")
    SnsMessage::CERTIFICATES.clear
    SnsMessage.transport = lambda do |uri|
      requests << uri.to_s
      uri.path.end_with?(".pem") ? ["200", SNS_CERT.to_pem] : [subscribe_code, "<ConfirmSubscriptionResponse/>"]
    end
    requests
  end

  def sns_message(type: "Notification", message: "{}", key: SNS_KEY, version: "2", **overrides)
    fields = { "Type" => type, "MessageId" => SecureRandom.uuid, "TopicArn" => TOPIC_ARN,
      "Message" => message, "Timestamp" => Time.current.utc.iso8601(3),
      "SignatureVersion" => version, "SigningCertURL" => CERT_URL }
    if type == "Notification"
      fields["Subject"] = "Amazon SES Email Event Notification"
    else
      fields["Token"] = "token-#{SecureRandom.hex(8)}"
      fields["SubscribeURL"] = "https://sns.eu-central-1.amazonaws.com/?Action=ConfirmSubscription&TopicArn=#{TOPIC_ARN}&Token=#{fields["Token"]}"
    end
    fields.merge!(overrides.transform_keys(&:to_s))
    signed = SnsMessage::SIGNED_FIELDS.fetch(type).filter_map { |name| "#{name}\n#{fields[name]}\n" unless fields[name].nil? }.join
    fields["Signature"] ||= Base64.strict_encode64(key.sign("SHA256", signed))
    fields
  end

  # An SES event-publishing record, as SNS carries it in Message.
  # Sent a second from now by default, so after any signup the test made.
  def ses_event(type, emails, product: "acme", sent_at: 1.second.from_now, bounce_type: "Permanent")
    event = { "eventType" => type,
      "mail" => { "timestamp" => sent_at.utc.iso8601(3), "messageId" => SecureRandom.hex(8),
        "destination" => Array(emails), "tags" => product ? { "product" => [product] } : {} } }
    recipients = Array(emails).map { |email| { "emailAddress" => email } }
    case type
    when "Complaint" then event["complaint"] = { "complainedRecipients" => recipients, "complaintFeedbackType" => "abuse" }
    when "Bounce" then event["bounce"] = { "bounceType" => bounce_type, "bouncedRecipients" => recipients }
    end
    JSON.generate(event)
  end
end
