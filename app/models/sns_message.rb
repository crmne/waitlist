require "net/http"

# A message Amazon SNS posted to us, verified before anything reads it
# (https://docs.aws.amazon.com/sns/latest/dg/sns-verify-signature-of-message.html):
#
# - it names the one topic this deployment subscribed (SES_EVENTS_TOPIC_ARN).
#   Any AWS account can sign messages from its own topics, so a valid
#   signature alone proves nothing about who sent it;
# - its signing certificate is fetched over HTTPS from
#   sns.<that topic's region>.amazonaws.com, and nowhere else;
# - its signature (SignatureVersion 2, SHA256 with RSA, only) checks against
#   that certificate over the fields SNS signs;
# - its Timestamp is within the last hour.
#
# Anything else raises Invalid. Chat with Work checks its SNS hooks the same
# way (crmne/chatwithwork app/models/sns_message.rb).
class SnsMessage
  class Invalid < StandardError; end

  TYPES = %w[Notification SubscriptionConfirmation UnsubscribeConfirmation].freeze
  SIGNED_FIELDS = {
    "Notification" => %w[Message MessageId Subject Timestamp TopicArn Type],
    "SubscriptionConfirmation" => %w[Message MessageId SubscribeURL Timestamp Token TopicArn Type],
    "UnsubscribeConfirmation" => %w[Message MessageId SubscribeURL Timestamp Token TopicArn Type]
  }.freeze
  MAX_AGE = 1.hour
  TOPIC_ARN = /\Aarn:aws:sns:([a-z0-9-]+):\d{12}:[A-Za-z0-9_-]{1,256}\z/

  # Tests set this to a lambda (uri) answering code and body.
  class_attribute :transport
  CERTIFICATES = {}
  CERTIFICATES_LOCK = Mutex.new

  attr_reader :fields

  def self.verify!(body, topic_arn:)
    new(body, topic_arn:).tap(&:verify!)
  end

  def initialize(body, topic_arn:)
    @fields = JSON.parse(body.to_s)
    raise Invalid, "not a JSON object" unless @fields.is_a?(Hash)
    @topic_arn = topic_arn.to_s
    @region = @topic_arn[TOPIC_ARN, 1] or raise Invalid, "no topic configured"
  rescue JSON::ParserError
    raise Invalid, "not JSON"
  end

  def type = fields["Type"]
  def message = fields["Message"]

  def verify!
    raise Invalid, "unknown type" unless TYPES.include?(type)
    raise Invalid, "another topic" unless ActiveSupport::SecurityUtils.secure_compare(fields["TopicArn"].to_s, @topic_arn)
    raise Invalid, "not SignatureVersion 2" unless fields["SignatureVersion"] == "2"
    raise Invalid, "too old" unless recent?
    signature = Base64.strict_decode64(fields["Signature"].to_s)
    key = certificate(aws_url(fields["SigningCertURL"], pem: true)).public_key
    raise Invalid, "bad signature" unless key.verify("SHA256", signature, string_to_sign)
    aws_url(fields["SubscribeURL"]) if type == "SubscriptionConfirmation"
    self
  rescue ArgumentError, OpenSSL::PKey::PKeyError
    raise Invalid, "bad signature"
  end

  # SNS delivers at least once; a repeat within two days is dropped. Handling
  # a repeat would change nothing anyway (SesEvent), this only saves work.
  def first_delivery?
    Rails.cache.write(["sns/message", fields["MessageId"].to_s], true, unless_exist: true, expires_in: 2.days)
  end

  # Confirms the subscription by visiting the SubscribeURL of a verified
  # SubscriptionConfirmation, which must be on the same SNS host.
  def confirm_subscription!
    raise Invalid, "not a subscription confirmation" unless type == "SubscriptionConfirmation"
    code, _body = get(aws_url(fields["SubscribeURL"]))
    raise Invalid, "SNS refused the confirmation (HTTP #{code})" unless (200..299).cover?(code.to_i)
  end

  private

  def recent?
    timestamp = Time.iso8601(fields["Timestamp"].to_s)
    timestamp > MAX_AGE.ago && timestamp < 5.minutes.from_now
  rescue ArgumentError
    false
  end

  def string_to_sign
    SIGNED_FIELDS.fetch(type).filter_map { |name| "#{name}\n#{fields[name]}\n" unless fields[name].nil? }.join
  end

  def aws_url(value, pem: false)
    uri = URI.parse(value.to_s)
    valid = uri.is_a?(URI::HTTPS) && uri.host == "sns.#{@region}.amazonaws.com" && uri.port == 443 && uri.userinfo.nil?
    valid &&= uri.path.end_with?(".pem") if pem
    raise Invalid, "not an SNS address in #{@region}" unless valid
    uri
  rescue URI::InvalidURIError
    raise Invalid, "not an SNS address"
  end

  def certificate(uri)
    CERTIFICATES_LOCK.synchronize { CERTIFICATES[uri.to_s] } || begin
      code, body = get(uri)
      raise Invalid, "no certificate (HTTP #{code})" unless code.to_i == 200
      cert = OpenSSL::X509::Certificate.new(body)
      raise Invalid, "certificate expired" unless (cert.not_before..cert.not_after).cover?(Time.now)
      CERTIFICATES_LOCK.synchronize do
        CERTIFICATES.shift while CERTIFICATES.size >= 8
        CERTIFICATES[uri.to_s] = cert
      end
    end
  rescue OpenSSL::X509::CertificateError
    raise Invalid, "unreadable certificate"
  end

  def get(uri)
    (self.class.transport || method(:net_http)).call(uri)
  rescue SocketError, SystemCallError, Timeout::Error, IOError, OpenSSL::SSL::SSLError => error
    raise Invalid, "could not reach SNS: #{error.class}"
  end

  # TLS with the system's roots, no redirects.
  def net_http(uri)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.get(uri.request_uri) }
    [response.code, response.body]
  end
end
