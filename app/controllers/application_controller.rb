class ApplicationController < ActionController::Base
  # A per-process random key: rate-limit buckets never hold an address, and
  # they expire from memory within the limit's window.
  ADDRESS_KEY = SecureRandom.bytes(32)

  private

  # The tunnel is the only way in, so Cloudflare's header names the client.
  # The address is hashed at once and never stored or logged.
  def client_bucket
    address = request.headers["CF-Connecting-IP"].presence || request.remote_ip
    OpenSSL::HMAC.hexdigest("SHA256", ADDRESS_KEY, address.to_s)[0, 32]
  end

  def find_product
    @product = Product.find_by(slug: params[:product]) or raise ActionController::RoutingError, "no such product"
  end
end
