# The owner's view. HTTP Basic over HTTPS, with the password from a tmpfs
# file (ADMIN_PASSWORD_FILE). Without a password, the admin is closed.
# Only requests without the right password are rate limited, to slow
# guessing; the signed-in owner can approve a whole list at once.
class Admin::BaseController < ApplicationController
  layout "admin"

  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new(size: 1.megabyte)

  rate_limit to: 20, within: 1.minute, by: -> { client_bucket }, store: RATE_LIMIT_STORE, unless: :signed_in?

  before_action :authenticate

  private

  def expected_password = Rails.configuration.x.admin_password.presence

  def authenticate
    return head(:not_found) unless expected_password

    authenticate_or_request_with_http_basic("Waitlist admin") { |user, password| valid_credentials?(user, password) }
  end

  def signed_in?
    return false unless expected_password && ActionController::HttpAuthentication::Basic.has_basic_credentials?(request)

    valid_credentials?(*ActionController::HttpAuthentication::Basic.user_name_and_password(request))
  end

  def valid_credentials?(user, password)
    ActiveSupport::SecurityUtils.secure_compare(user.to_s, "admin") &
      ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(password.to_s), Digest::SHA256.hexdigest(expected_password))
  end
end
