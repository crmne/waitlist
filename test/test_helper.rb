ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    include ActiveJob::TestHelper
    parallelize(workers: 2)

    setup do
      Product.sync!
      Rails.configuration.x.admin_password = "correct horse"
    end

    def acme = Product.find_by!(slug: "acme")

    def confirmed_signup(email = "dj@example.com", product: acme, at: Time.current)
      product.signups.create!(email:, consent_text: "test", confirmed_at: at, created_at: at)
    end
  end
end

class ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  def admin_headers = { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "correct horse") }
end
