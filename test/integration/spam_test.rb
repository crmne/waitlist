require "test_helper"

class SpamTest < ActionDispatch::IntegrationTest
  def assert_quietly_refused
    assert_includes [202, 303], response.status
    assert_equal 0, Signup.count
    assert_no_enqueued_emails
  end

  test "the honeypot is refused quietly on JSON, the hosted form and the plain form" do
    post "/p/acme/signups", params: { email: "bot@example.com", website: "x", elapsed_ms: 9000 }, as: :json
    assert_equal({ "status" => "check_email" }, response.parsed_body)
    assert_quietly_refused
    post "/p/acme/signups", params: { email: "bot@example.com", website: "x", started: SpamCheck.started_token(1.minute.ago) }
    assert_redirected_to "/p/acme/thanks"
    assert_quietly_refused
  end

  test "a form sent within three seconds, or with no timing at all, is refused quietly" do
    post "/p/acme/signups", params: { email: "bot@example.com", elapsed_ms: 900 }, as: :json
    assert_quietly_refused
    post "/p/acme/signups", params: { email: "bot@example.com" }, as: :json
    assert_quietly_refused
    post "/p/acme/signups", params: { email: "bot@example.com", started: SpamCheck.started_token(1.second.ago) }
    assert_quietly_refused
    post "/p/acme/signups", params: { email: "bot@example.com", started: "forged" }
    assert_quietly_refused
  end

  test "the hosted form carries a signed start time and works after three seconds" do
    get "/p/acme"
    token = response.body[/name="started" value="([^"]+)"/, 1]
    assert token
    travel 4.seconds do
      post "/p/acme/signups", params: { email: "dj@example.com", started: token }
    end
    assert_redirected_to "/p/acme/thanks"
    assert_equal 1, Signup.count
  end

  test "a domain that takes no mail gets a clear error and nothing is stored" do
    post "/p/acme/signups", params: { email: "dj@nomail.test", elapsed_ms: 9000 }, as: :json
    assert_response :unprocessable_content
    assert_equal "Please check your email address: nomail.test doesn't seem to receive email.", response.parsed_body["message"]
    post "/p/acme/signups", params: { email: "dj@nomail.test", started: SpamCheck.started_token(1.minute.ago) }
    assert_response :unprocessable_content
    assert_match "check your email address", response.body
    assert_equal 0, Signup.count
  end

  test "more than ten tries in ten minutes from one address are refused" do
    10.times { |i| post "/p/acme/signups", params: { email: "dj#{i}@example.com", elapsed_ms: 9000 }, as: :json }
    assert_response :accepted
    post "/p/acme/signups", params: { email: "dj11@example.com", elapsed_ms: 9000 }, as: :json
    assert_response :too_many_requests
    assert_equal 10, Signup.count
  end
end

class EmailDomainTest < ActiveSupport::TestCase
  test "MX, null MX and the A fallback" do
    answers = { "mail.test" => true, "nullmx.test" => false }
    EmailDomain.resolver = ->(domain) { answers.fetch(domain) }
    assert EmailDomain.deliverable?("a@mail.test")
    assert_not EmailDomain.deliverable?("a@nullmx.test")
    assert_not EmailDomain.deliverable?("a@localhost")
    assert_not EmailDomain.deliverable?("no-at-sign")
  end

  test "the real lookup treats a null MX as no mail" do
    dns = Object.new
    def dns.timeouts=(_value)
    end
    def dns.getresources(_domain, type)
      type == Resolv::DNS::Resource::IN::MX ? [Resolv::DNS::Resource::IN::MX.new(0, Resolv::DNS::Name.create("."))] : []
    end
    original = Resolv::DNS.method(:open)
    Resolv::DNS.define_singleton_method(:open) { |&block| block.call(dns) }
    assert_not EmailDomain.lookup("nullmx.test")
  ensure
    Resolv::DNS.define_singleton_method(:open, original)
  end
end
