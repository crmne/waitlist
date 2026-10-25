# The owner's view. HTTP Basic over HTTPS, with the password from a tmpfs
# file (ADMIN_PASSWORD_FILE). Without a password, the admin is closed.
class Admin::BaseController < ApplicationController
  layout "admin"

  rate_limit to: 20, within: 1.minute, by: -> { client_bucket },
    store: ActiveSupport::Cache::MemoryStore.new(size: 1.megabyte)

  before_action :authenticate

  private

  def authenticate
    expected = Rails.configuration.x.admin_password.presence
    return head(:not_found) unless expected

    authenticate_or_request_with_http_basic("Waitlist admin") do |user, password|
      ActiveSupport::SecurityUtils.secure_compare(user, "admin") &
        ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(password), Digest::SHA256.hexdigest(expected))
    end
  end
end
