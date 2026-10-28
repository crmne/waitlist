require "test_helper"
require "socket"
require "zlib"
require "opentelemetry/proto/collector/metrics/v1/metrics_service_pb"

class MetricsReportTest < ActiveSupport::TestCase
  def value(gauges, name, product: "acme", **attributes)
    wanted = { "waitlist.product" => product }.merge(attributes.transform_keys { "waitlist.#{it}" })
    gauges.select { it.name == name && it.attributes == wanted }.sole.value
  end

  def build_list(now)
    acme.signups.create!(email: "new@example.com", consent_text: "t", source: "site", created_at: now - 1.hour)
    acme.signups.create!(email: "old@example.com", consent_text: "t", created_at: now - 2.days)
    referrer = confirmed_signup("ref@example.com", at: now - 3.days)
    confirmed_signup("today@example.com", at: now - 1.hour).update!(referred_by: referrer)
    confirmed_signup("w@example.com", at: now - 2.days)
    { "sent@example.com" => { approval_emailed_at: now - 1.hour, approval_registered_at: now - 1.hour },
      "failed@example.com" => { approval_failed_at: now - 1.hour, approval_registered_at: now - 1.hour },
      "registered@example.com" => { approval_registered_at: now - 2.days },
      "pending@example.com" => {} }.each do |email, fields|
      confirmed_signup(email, at: now - 5.days).update!(approved_at: now - 2.days, **fields)
    end
  end

  test "counts each product's list by status, source, referral and invitation, zero included" do
    now = Time.utc(2026, 10, 29, 12)
    build_list(now)
    gauges = MetricsReport.new(now:).gauges

    assert_equal 2, value(gauges, "waitlist.signups.by_status", status: "unconfirmed")
    assert_equal 3, value(gauges, "waitlist.signups.by_status", status: "waiting")
    assert_equal 4, value(gauges, "waitlist.signups.by_status", status: "approved")
    assert_equal 9, value(gauges, "waitlist.signups.total")
    assert_equal 2, value(gauges, "waitlist.signups.today")
    assert_equal 1, value(gauges, "waitlist.signups.by_source", source: "site")
    assert_equal 8, value(gauges, "waitlist.signups.by_source", source: "form")
    assert_equal 0, value(gauges, "waitlist.signups.by_source", source: "getwaitlist")
    assert_equal 1, value(gauges, "waitlist.confirmed.by_referral", referred: "yes")
    assert_equal 6, value(gauges, "waitlist.confirmed.by_referral", referred: "no")
    assert_equal 1, value(gauges, "waitlist.confirmations.today", referred: "yes")
    assert_equal 0, value(gauges, "waitlist.confirmations.today", referred: "no")
    %w[sent failed registered pending].each { assert_equal 1, value(gauges, "waitlist.invites.by_state", invite: it) }
    assert_equal 1, value(gauges, "waitlist.invites.today", invite: "sent")
    assert_equal 1, value(gauges, "waitlist.invites.today", invite: "failed")
    # A product without an approval step: approved people are just approved.
    assert_equal 0, value(gauges, "waitlist.invites.by_state", product: "plain", invite: "approved")
    assert_equal 0, value(gauges, "waitlist.signups.total", product: "plain")
  end

  # Seq nests dotted names, so a metric named like another's prefix would
  # turn into an object inside the other's samples.
  test "no name is a dotted prefix of another" do
    names = MetricsReport::DESCRIPTIONS.keys + %w[waitlist.product waitlist.status waitlist.source waitlist.referred waitlist.invite]
    names.each { |name| assert_empty names.select { |other| other.start_with?("#{name}.") }, name }
  end

  test "sends nothing without an endpoint and a key" do
    Rails.configuration.x.seq_api_key = nil
    assert_not MetricsReport.enabled?
    assert_nothing_raised { MetricsJob.perform_now }
  end

  test "posts the counts to Seq over OTLP with the ingest key, and nothing personal" do
    build_list(Time.current)
    server = TCPServer.new("127.0.0.1", 0)
    received = Queue.new
    thread = Thread.new do
      client = server.accept
      head = +""
      head << client.gets until head.end_with?("\r\n\r\n")
      body = client.read(head[/content-length: (\d+)/i, 1].to_i)
      client.write("HTTP/1.1 200 OK\r\nContent-Type: application/x-protobuf\r\nContent-Length: 0\r\n\r\n")
      client.close
      received << [head, body]
    end

    with_env("OTEL_EXPORTER_OTLP_ENDPOINT" => "http://127.0.0.1:#{server.addr[1]}/ingest/otlp",
      "OTEL_RESOURCE_ATTRIBUTES" => "service.name=waitlist,deployment.environment.name=production,host.name=prod") do
      Rails.configuration.x.seq_api_key = "test-ingest-key"
      assert MetricsReport.enabled?
      assert MetricsReport.new.deliver
    end
    head, body = received.pop
    thread.join

    assert_match %r{\APOST /ingest/otlp/v1/metrics }, head
    assert_match(/^X-Seq-ApiKey: test-ingest-key\r$/i, head)
    request = Opentelemetry::Proto::Collector::Metrics::V1::ExportMetricsServiceRequest.decode(Zlib.gunzip(body))
    resource = request.resource_metrics.sole.resource.attributes.to_h { [it.key, it.value.string_value] }
    assert_equal "waitlist", resource["service.name"]
    assert_equal "production", resource["deployment.environment.name"]
    assert_equal "prod", resource["host.name"]
    metrics = request.resource_metrics.sole.scope_metrics.sole.metrics
    assert_equal MetricsReport::DESCRIPTIONS.keys.sort, metrics.map(&:name).sort
    sent = request.to_json
    Signup.pluck(:email, :referral_code).flatten.each { assert_not_includes sent, it }
  ensure
    Rails.configuration.x.seq_api_key = nil
    server&.close
  end

  private

  def with_env(values)
    previous = values.to_h { |key, _| [key, ENV[key]] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end
