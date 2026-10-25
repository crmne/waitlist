require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module Waitlist
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])
    config.generators.system_tests = nil

    config.time_zone = "UTC"
    config.i18n.default_locale = :"en-GB"
    config.i18n.available_locales = [:"en-GB", :en]

    # The public address of this service; links in emails point here.
    config.x.public_host = ENV.fetch("PUBLIC_HOST", "localhost")

    # Signups that never confirm are deleted after this long (docs/privacy.md).
    config.x.unconfirmed_retention = 7.days
    # A confirmation link works for this long.
    config.x.confirmation_validity = 7.days
    # A second confirmation email for the same address waits at least this long.
    config.x.confirmation_resend_after = 15.minutes

    # No cookies on public pages: sessions exist only for the admin's forms.
    config.session_store :cookie_store, key: "_waitlist_admin", same_site: :strict, secure: Rails.env.production?
  end
end
