require "opentelemetry/sdk"
require "opentelemetry-metrics-sdk"
require "opentelemetry-exporter-otlp-metrics"

# How each product's waitlist stands, as counts only, sent to our Seq
# (logs.paolino.me) over OTLP every ten minutes by MetricsJob
# (config/recurring.yml). Every value is a count of rows and every attribute
# a fixed word: the product's slug, a status, a source, yes or no. Never an
# address, an answer, a referral code, a reference or a time of day
# (docs/privacy.md).
#
# Sent only where OTEL_EXPORTER_OTLP_ENDPOINT names the endpoint and
# SEQ_API_KEY_FILE an ingest key (config.x.seq_api_key); otherwise nothing.
class MetricsReport
  Gauge = Data.define(:name, :value, :attributes)

  STATUSES = %w[unconfirmed waiting approved].freeze
  INVITES = %w[pending registered sent failed approved].freeze
  SOURCES = ["form", "site", GetwaitlistImport::SOURCE].freeze
  REFERRED = %w[yes no].freeze

  DESCRIPTIONS = {
    "waitlist.signups.by_status" => "People on the list, by status",
    "waitlist.signups.total" => "People on the list",
    "waitlist.signups.today" => "Signups since midnight UTC still on the list",
    "waitlist.signups.by_source" => "People on the list, by where they signed up",
    "waitlist.confirmed.by_referral" => "People who confirmed, by whether a referral brought them",
    "waitlist.confirmations.today" => "Confirmations since midnight UTC, by whether a referral brought them",
    "waitlist.invites.by_state" => "Approved people, by where their invitation stands",
    "waitlist.invites.today" => "Invitations emailed or failed since midnight UTC"
  }.freeze

  def self.enabled? = endpoint.present? && Rails.configuration.x.seq_api_key.present?
  def self.endpoint = ENV["OTEL_EXPORTER_OTLP_ENDPOINT"]

  def initialize(now: Time.current)
    @now = now
    @today = now.utc.beginning_of_day
  end

  def gauges
    Product.order(:slug).flat_map { |product| gauges_for(product) }
  end

  # Records every gauge on a meter of its own and exports it once. Returns
  # true when the endpoint took it. The default reader is the OTLP exporter,
  # with the ingest key as Seq's X-Seq-ApiKey header.
  def deliver(reader: self.class.exporter)
    provider = OpenTelemetry::SDK::Metrics::MeterProvider.new(resource: self.class.resource)
    provider.add_metric_reader(reader)
    meter = provider.meter("waitlist")
    instruments = DESCRIPTIONS.to_h { |name, description| [name, meter.create_gauge(name, unit: "{person}", description:)] }
    gauges.each { |gauge| instruments.fetch(gauge.name).record(gauge.value, attributes: gauge.attributes) }
    result = reader.pull
    result.nil? || result == OpenTelemetry::SDK::Metrics::Export::SUCCESS
  ensure
    provider&.shutdown
  end

  def self.exporter
    OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter.new(
      endpoint: URI.join("#{endpoint.chomp("/")}/", "v1/metrics").to_s,
      headers: { "X-Seq-ApiKey" => Rails.configuration.x.seq_api_key }, compression: "gzip", timeout: 10
    )
  end

  # service.name and the environment, overridden by OTEL_RESOURCE_ATTRIBUTES
  # (config/deploy.yml in the deployment), which the SDK reads.
  def self.resource
    OpenTelemetry::SDK::Resources::Resource.create(
      "service.name" => "waitlist", "deployment.environment.name" => Rails.env.to_s
    ).merge(OpenTelemetry::SDK::Resources::Resource.telemetry_sdk)
  end

  private

  def gauges_for(product)
    signups = product.signups
    base = { "waitlist.product" => product.slug }
    list = []
    add = ->(name, value, extra = {}) { list << Gauge.new(name:, value:, attributes: base.merge(extra)) }

    by_status = { "unconfirmed" => signups.unconfirmed.count, "waiting" => signups.waiting.count, "approved" => signups.approved.count }
    STATUSES.each { |status| add.("waitlist.signups.by_status", by_status[status], "waitlist.status" => status) }
    add.("waitlist.signups.total", by_status.values.sum)
    add.("waitlist.signups.today", signups.where(created_at: @today..).count)

    by_source = signups.group(:source).count
    (SOURCES | by_source.keys).each { |source| add.("waitlist.signups.by_source", by_source.fetch(source, 0), "waitlist.source" => source) }

    confirmed = signups.confirmed
    today = confirmed.where(confirmed_at: @today..)
    { "yes" => confirmed.where.not(referred_by_id: nil), "no" => confirmed.where(referred_by_id: nil) }.each do |referred, scope|
      add.("waitlist.confirmed.by_referral", scope.count, "waitlist.referred" => referred)
    end
    { "yes" => today.where.not(referred_by_id: nil), "no" => today.where(referred_by_id: nil) }.each do |referred, scope|
      add.("waitlist.confirmations.today", scope.count, "waitlist.referred" => referred)
    end

    invites = invite_states(product)
    INVITES.each { |state| add.("waitlist.invites.by_state", invites.fetch(state, 0), "waitlist.invite" => state) }
    add.("waitlist.invites.today", signups.where(approval_emailed_at: @today..).count, "waitlist.invite" => "sent")
    add.("waitlist.invites.today", signups.where(approval_failed_at: @today..).where(approval_emailed_at: nil).count, "waitlist.invite" => "failed")
    list
  end

  # Signup#approval_state, counted in SQL.
  def invite_states(product)
    approved = product.signups.approved
    return { "approved" => approved.count } unless product.on_approve
    {
      "sent" => approved.where.not(approval_emailed_at: nil).count,
      "failed" => approved.where(approval_emailed_at: nil).where.not(approval_failed_at: nil).count,
      "registered" => approved.where(approval_emailed_at: nil, approval_failed_at: nil).where.not(approval_registered_at: nil).count,
      "pending" => approved.where(approval_emailed_at: nil, approval_failed_at: nil, approval_registered_at: nil).count
    }
  end
end
