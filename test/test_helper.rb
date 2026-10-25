ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    include ActiveJob::TestHelper
    include ActionMailer::TestHelper
    parallelize(workers: 2)

    # No DNS in tests: every domain takes mail except these.
    NO_MAIL = %w[nomail.test example.net].freeze

    setup do
      EmailDomain.resolver = ->(domain) { !NO_MAIL.include?(domain) }
      EmailDomain::CACHE.clear
      SignupsController::RATE_LIMIT_STORE.clear
      Product.sync!(Rails.root.join("test/fixtures/products.yml"))
      ApprovalWebhook.transport = ->(_uri, _request) { raise "no webhook in this test" }
      Rails.configuration.x.admin_password = "correct horse"
    end

    def acme = Product.find_by!(slug: "acme")

    WebhookResponse = Struct.new(:code, :body)

    # Answers the approval webhook like the fixture product's service:
    # register returns a licence id, a key and an expiry; sent returns 200.
    def fake_webhook(requests = [], key: "KEY-123", fail_with: nil)
      ApprovalWebhook.transport = lambda do |uri, request|
        requests << [uri.to_s, ::JSON.parse(request.body), request["Authorization"]]
        next WebhookResponse.new(fail_with.to_s, "{}") if fail_with
        if uri.path == "/approved"
          WebhookResponse.new("201", ::JSON.generate(licence_id: "0b7e4f7a-8f6c-4c1e-9a43-2f1d8f0b5c11", key: key, expires_at: "2027-04-23T10:00:00Z"))
        else
          WebhookResponse.new("200", "{}")
        end
      end
      requests
    end

    def confirmed_signup(email = "dj@example.com", product: acme, at: Time.current)
      product.signups.create!(email:, consent_text: "test", confirmed_at: at, created_at: at)
    end
  end
end

class ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  def admin_headers = { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "correct horse") }
end
