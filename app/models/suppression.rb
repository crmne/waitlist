class Suppression < ApplicationRecord
  belongs_to :product

  def self.digest(email)
    key = Rails.application.key_generator.generate_key("suppression email digest", 32)
    OpenSSL::HMAC.hexdigest("SHA256", key, email.to_s.strip.downcase)
  end

  def self.add(product, email)
    find_or_create_by!(product:, email_digest: digest(email))
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def self.lift(product, email) = where(product:, email_digest: digest(email)).delete_all

  def self.suppressed?(product, email) = exists?(product:, email_digest: digest(email))
end
