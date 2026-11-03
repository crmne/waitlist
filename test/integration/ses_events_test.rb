require "test_helper"
require_relative "../sns_test_helper"

class SesEventsTest < ActionDispatch::IntegrationTest
  include SnsTestHelper

  setup do
    @requests = stub_sns
    Rails.configuration.x.ses_events_topic_arn = TOPIC_ARN
    @forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    Rails.configuration.x.ses_events_topic_arn = nil
    ActionController::Base.allow_forgery_protection = @forgery
    SnsMessage.transport = nil
  end

  def plain = Product.find_by!(slug: "plain")

  def deliver(fields)
    post "/hooks/ses_events", params: JSON.generate(fields),
      headers: { "Content-Type" => "text/plain; charset=UTF-8", "x-amz-sns-message-type" => fields["Type"] }
  end

  def notify(*args, **options) = deliver(sns_message(message: ses_event(*args, **options)))

  # Verification

  test "answers 404 until a topic is configured" do
    Rails.configuration.x.ses_events_topic_arn = nil
    signup = confirmed_signup
    notify("Complaint", signup.email)
    assert_response :not_found
    assert Signup.exists?(signup.id)
  end

  test "a signed subscription confirmation for our topic is confirmed at its SNS address" do
    deliver(sns_message(type: "SubscriptionConfirmation", message: "You have chosen to subscribe"))
    assert_response :success
    assert_equal 2, @requests.size
    assert_match %r{\Ahttps://sns\.eu-central-1\.amazonaws\.com/\?Action=ConfirmSubscription}, @requests.last
    assert_nil response.headers["Set-Cookie"]
  end

  test "a confirmation SNS refuses is a failure, so SNS tries again" do
    stub_sns(subscribe_code: "500")
    deliver(sns_message(type: "SubscriptionConfirmation"))
    assert_response :bad_gateway
  end

  test "an unsigned or tampered subscription confirmation is never confirmed" do
    fields = sns_message(type: "SubscriptionConfirmation")
    deliver(fields.merge("SubscribeURL" => fields["SubscribeURL"] + "&x=1"))
    assert_response :forbidden
    deliver(fields.except("Signature"))
    assert_response :forbidden
    assert @requests.none? { |url| url.include?("ConfirmSubscription") }
  end

  test "a subscription confirmation pointing anywhere but SNS in our region is refused" do
    fields = sns_message(type: "SubscriptionConfirmation", "SubscribeURL" => "https://evil.example/?Action=ConfirmSubscription")
    deliver(fields)
    assert_response :forbidden
    assert @requests.none? { |url| url.include?("evil") }
  end

  test "a certificate from anywhere but sns.<region>.amazonaws.com is never fetched" do
    signup = confirmed_signup
    [
      "https://sns.eu-central-1.amazonaws.com.evil.example/cert.pem",
      "https://evil.example/sns.eu-central-1.amazonaws.com/cert.pem",
      "http://sns.eu-central-1.amazonaws.com/cert.pem",
      "https://sns.us-east-1.amazonaws.com/cert.pem",
      "https://user@sns.eu-central-1.amazonaws.com/cert.pem",
      "https://sns.eu-central-1.amazonaws.com:8443/cert.pem",
      "https://sns.eu-central-1.amazonaws.com/cert.txt"
    ].each do |url|
      deliver(sns_message(message: ses_event("Complaint", signup.email), "SigningCertURL" => url))
      assert_response :forbidden, url
    end
    assert_empty @requests
    assert Signup.exists?(signup.id)
  end

  test "a message signed by another key, for another topic, or altered is refused" do
    signup = confirmed_signup
    deliver(sns_message(message: ses_event("Complaint", signup.email), key: OpenSSL::PKey::RSA.new(2048)))
    assert_response :forbidden

    # A valid AWS signature from someone else's topic proves nothing.
    deliver(sns_message(message: ses_event("Complaint", signup.email),
      "TopicArn" => "arn:aws:sns:eu-central-1:999999999999:waitlist-ses-events"))
    assert_response :forbidden

    fields = sns_message(message: ses_event("Complaint", "someone@example.com"))
    deliver(fields.merge("Message" => ses_event("Complaint", signup.email)))
    assert_response :forbidden

    deliver(sns_message(message: ses_event("Complaint", signup.email), version: "3", "Signature" => "AAAA"))
    assert_response :forbidden

    post "/hooks/ses_events", params: "not json", headers: { "Content-Type" => "text/plain" }
    assert_response :forbidden
    assert Signup.exists?(signup.id)
  end

  test "a null Subject is left out of what is signed, as SNS does" do
    signup = confirmed_signup
    deliver(sns_message(message: ses_event("Complaint", signup.email), "Subject" => nil))
    assert_response :success
    assert_not Signup.exists?(signup.id)
  end

  test "only SignatureVersion 2 is accepted, as the topic is set to sign" do
    signup = confirmed_signup
    deliver(sns_message(message: ses_event("Complaint", signup.email), version: "1"))
    assert_response :forbidden
    assert Signup.exists?(signup.id)
  end

  test "a message older than an hour, or from the future, is refused" do
    signup = confirmed_signup
    [61.minutes.ago, 10.minutes.from_now].each do |at|
      deliver(sns_message(message: ses_event("Complaint", signup.email), "Timestamp" => at.utc.iso8601(3)))
      assert_response :forbidden
    end
    deliver(sns_message(message: ses_event("Complaint", signup.email), "Timestamp" => "yesterday"))
    assert_response :forbidden
    assert Signup.exists?(signup.id)
  end

  test "a repeated MessageId is answered 200 and not handled again" do
    cache, Rails.cache = Rails.cache, ActiveSupport::Cache::MemoryStore.new
    fields = sns_message(message: ses_event("Complaint", "dj@example.com", sent_at: 2.hours.ago))
    deliver(fields)
    rejoined = confirmed_signup
    # Even a replay that would otherwise act is dropped before it is read.
    Signup.where(id: rejoined.id).update_all(created_at: 3.hours.ago)
    deliver(fields)
    assert_response :success
    assert Signup.exists?(rejoined.id)
  ensure
    Rails.cache = cache
  end

  test "a complaint a provider takes back (not-spam) changes nothing" do
    signup = confirmed_signup
    event = JSON.parse(ses_event("Complaint", signup.email))
    event["complaint"]["complaintFeedbackType"] = "not-spam"
    deliver(sns_message(message: JSON.generate(event)))
    assert_response :success
    assert Signup.exists?(signup.id)
    assert_not Suppression.suppressed?(acme, signup.email)
  end

  # Feedback

  test "a complaint forgets the signup for the tagged product, keeps a digest and sends nothing" do
    signup = confirmed_signup("DJ@Example.com")
    other = confirmed_signup("dj@example.com", product: plain)
    assert_no_enqueued_emails { notify("Complaint", "DJ@Example.com", product: "acme") }
    assert_response :success
    assert_nil response.headers["Set-Cookie"]
    assert_not Signup.exists?(signup.id)
    assert Suppression.suppressed?(acme, "dj@example.com")
    assert Signup.exists?(other.id), "the other product's signup stays"
    assert_not Suppression.suppressed?(plain, "dj@example.com")
  end

  test "a permanent bounce forgets the signup and sends nothing" do
    signup = acme.signups.create!(email: "gone@example.com", consent_text: "test")
    assert_no_enqueued_emails { notify("Bounce", "gone@example.com") }
    assert_response :success
    assert_not Signup.exists?(signup.id)
    assert Suppression.suppressed?(acme, "gone@example.com")
  end

  test "transient and undetermined bounces are only logged" do
    signup = confirmed_signup
    %w[Transient Undetermined].each do |bounce_type|
      notify("Bounce", signup.email, bounce_type:)
      assert_response :success
    end
    assert Signup.exists?(signup.id)
    assert_not Suppression.suppressed?(acme, signup.email)
  end

  test "without a product tag, every product holding the address is affected" do
    first = confirmed_signup
    second = confirmed_signup(product: plain)
    bystander = confirmed_signup("other@example.com")
    notify("Complaint", "dj@example.com", product: nil)
    assert_not Signup.exists?(first.id)
    assert_not Signup.exists?(second.id)
    assert Signup.exists?(bystander.id)
    assert Suppression.suppressed?(acme, "dj@example.com")
    assert Suppression.suppressed?(plain, "dj@example.com")
  end

  test "an unknown product tag falls back to every product holding the address" do
    signup = confirmed_signup(product: plain)
    notify("Complaint", signup.email, product: "elsewhere")
    assert_not Signup.exists?(signup.id)
  end

  test "a complaint about an address no longer on the list still suppresses it for the tagged product" do
    notify("Complaint", "left@example.com")
    assert_response :success
    assert Suppression.suppressed?(acme, "left@example.com")
  end

  test "every recipient of a bounce counts, in any address form" do
    one = confirmed_signup("one@example.com")
    two = confirmed_signup("two@example.com")
    notify("Bounce", ["one@example.com", "Two <TWO@example.com>"])
    assert_not Signup.exists?(one.id)
    assert_not Signup.exists?(two.id)
  end

  test "the same event twice changes nothing more" do
    signup = confirmed_signup
    fields = sns_message(message: ses_event("Complaint", signup.email))
    2.times do
      deliver(fields)
      assert_response :success
    end
    assert_not Signup.exists?(signup.id)
    assert_equal 1, Suppression.where(product: acme).count
  end

  test "an old event repeated after the person signed up again leaves the new signup alone" do
    fields = sns_message(message: ses_event("Complaint", "dj@example.com", sent_at: 2.hours.ago))
    deliver(fields)
    rejoined = acme.signups.create!(email: "dj@example.com", consent_text: "test")
    deliver(fields)
    assert_response :success
    assert Signup.exists?(rejoined.id)
  end

  test "SES's plain-text test message and other event types are accepted and ignored" do
    signup = confirmed_signup
    deliver(sns_message(message: "Successfully validated SNS topic for Amazon SES event publishing."))
    assert_response :success
    deliver(sns_message(message: JSON.generate("eventType" => "Delivery", "mail" => { "destination" => [signup.email] })))
    assert_response :success
    assert Signup.exists?(signup.id)
  end

  test "identity notifications (notificationType) are understood too" do
    signup = confirmed_signup
    event = JSON.parse(ses_event("Complaint", signup.email, product: nil))
    event["notificationType"] = event.delete("eventType")
    deliver(sns_message(message: JSON.generate(event)))
    assert_not Signup.exists?(signup.id)
  end

  test "the certificate is fetched once and reused" do
    2.times { notify("Bounce", "nobody@example.com", bounce_type: "Transient") }
    assert_equal 1, @requests.count { |url| url.end_with?(".pem") }
  end
end
