source "https://rubygems.org"

gem "rails", "~> 8.1.4"
gem "propshaft"
gem "sqlite3", ">= 2.1"
gem "puma", ">= 5.0"
# Confirmation emails and retention jobs, in the same process (SOLID_QUEUE_IN_PUMA)
gem "solid_queue"
gem "csv"
# Honeypot spam check, as Chat with Work used on its waitlist
gem "invisible_captcha", "~> 2.3"
gem "bootsnap", require: false
gem "tzinfo-data", platforms: %i[windows jruby]

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
end
# Aggregate counts to our Seq over OTLP (app/models/metrics_report.rb); only
# where OTEL_EXPORTER_OTLP_ENDPOINT and SEQ_API_KEY_FILE are set.
gem "opentelemetry-metrics-sdk"
gem "opentelemetry-exporter-otlp-metrics"
