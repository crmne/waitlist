require "active_support/core_ext/integer/time"
require "active_support/core_ext/numeric/bytes"

# Runtime secrets are files on the host's tmpfs, mounted read-only
# (docs/deployment.md). Nothing secret is in the image, the environment or
# Rails credentials.
secret_file = ->(variable) do
  path = ENV[variable].presence
  path && File.file?(path) ? File.read(path).strip.presence : nil
end

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  config.secret_key_base = secret_file.call("SECRET_KEY_BASE_FILE") ||
    (ENV["SECRET_KEY_BASE_DUMMY"] && "precompile-only") ||
    raise("SECRET_KEY_BASE_FILE must name a readable file (docs/deployment.md)")

  # Cloudflare terminates TLS; the tunnel reaches the container over HTTP.
  config.assume_ssl = true
  config.force_ssl = true
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # No request or application logs: the container uses Docker's `none`
  # driver too, so no address, email or token is written anywhere.
  config.logger = ActiveSupport::Logger.new(nil)
  config.log_level = :fatal
  config.active_support.report_deprecations = false

  # Only the in-process rate limiter uses the cache.
  config.cache_store = :memory_store, { size: 8.megabytes }

  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }
  config.solid_queue.logger = ActiveSupport::Logger.new(nil)

  host = config.x.public_host
  config.action_mailer.default_url_options = { host:, protocol: "https" }
  Rails.application.routes.default_url_options = { host:, protocol: "https" }

  # Mail goes out through SMTP only when its credentials are on the host.
  # Without them, nothing is sent: messages are written to the storage
  # volume (storage/mail) so a deploy without mail can't email anyone.
  smtp_user = secret_file.call("SMTP_USERNAME_FILE")
  smtp_password = secret_file.call("SMTP_PASSWORD_FILE")
  if ENV["SMTP_ADDRESS"].present? && smtp_user && smtp_password
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: ENV["SMTP_ADDRESS"],
      port: Integer(ENV.fetch("SMTP_PORT", "587")),
      user_name: smtp_user,
      password: smtp_password,
      authentication: :plain,
      enable_starttls_auto: true
    }
    config.action_mailer.raise_delivery_errors = true
  else
    config.action_mailer.delivery_method = :file
    config.action_mailer.file_settings = { location: Rails.root.join("storage/mail").to_s }
  end

  config.x.admin_password = secret_file.call("ADMIN_PASSWORD_FILE")

  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [:id]
  config.hosts = [host]
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
