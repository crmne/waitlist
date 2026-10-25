require "net/http"

# A product's "on approve" integration (`on_approve` in the products file):
#
#   on_approve:
#     url: http://hooks.internal:3000/approved   # called when someone is approved
#     token_file: /run/secrets/approve-token        # Bearer token, read at call time
#     id_field: id                                  # where the answer names what it created
#     sent_url: http://hooks.internal:3000/sent      # optional: told once the email went out
#
# POST url with {"email", "reference", "product"}. A 2xx JSON answer must
# carry id_field; its other fields become variables for the approval email
# (and are never stored). After the approval email is sent, POST sent_url
# with {id_field => id, "reference"}. Anything but a 2xx raises Error.
class ApprovalWebhook
  class Error < StandardError; end

  # Tests set this to a lambda (uri, request) answering code and body.
  class_attribute :transport

  def initialize(config, root:, transport: self.class.transport)
    @config = config
    @root = Pathname(root)
    @transport = transport || method(:net_http)
  end

  def id_field = @config.fetch("id_field", "id")

  # Returns [id, fields].
  def register(signup)
    answer = post(@config.fetch("url"), email: signup.email, reference: self.class.reference_for(signup), product: signup.product.slug)
    id = answer[id_field]
    raise Error, "the approval webhook answered without #{id_field}" unless id.is_a?(String) && id.match?(/\A[A-Za-z0-9._:-]{1,100}\z/)
    [id, answer.except(id_field)]
  end

  def acknowledge(signup)
    url = @config["sent_url"].presence or return
    post(url, id_field => signup.approval_reference, "reference" => self.class.reference_for(signup))
  end

  def acknowledges? = @config["sent_url"].present?

  # Stable and never reused: SQLite reuses the ids of deleted rows, so the
  # signup's random referral code names it.
  def self.reference_for(signup) = "waitlist-#{signup.referral_code}"

  private

  def post(url, body)
    uri = URI(url)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request.body = JSON.generate(body)
    response = @transport.call(uri, request)
    code = response.code.to_i
    raise Error, "the approval webhook refused (HTTP #{code}#{error_code(response)})" unless (200..299).cover?(code)
    parse(response.body)
  rescue SocketError, SystemCallError, Timeout::Error, IOError => error
    raise Error, "could not reach the approval webhook: #{error.class}"
  end

  def token
    file = @config["token_file"].presence
    path = file && (Pathname(file).absolute? ? Pathname(file) : @root.join(file))
    value = path&.file? ? path.read.strip : ""
    raise Error, "no token for the approval webhook (token_file)" if value.empty?
    value
  end

  def parse(body)
    parsed = JSON.parse(body.to_s)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  # Only a fixed error code from the answer, never its body.
  def error_code(response)
    code = parse(response.body).dig("error", "code")
    code.is_a?(String) && code.match?(/\A[a-z_]{1,40}\z/) ? ", #{code}" : ""
  end

  def net_http(uri, request)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 20) { |http| http.request(request) }
  end
end
