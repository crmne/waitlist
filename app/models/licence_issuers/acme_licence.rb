require "net/http"

module LicenceIssuers
  # Registers a Acme alpha licence for an approved signup (licence-server ADR
  # 0009, docs/api.md "Internal licences"). licence-server only records it;
  # Carmine's `bin/issue-licence --pending` signs the key and emails it, so
  # this app never sees a key.
  #
  # The request goes over the Docker network (`kamal`) to licence-server's
  # origin alias, never through the public tunnel: licence-server answers 404
  # to anything carrying Cloudflare's headers. It is idempotent on the
  # reference (reference_for), so a retried job registers nothing twice.
  class AcmeLicence
    class Error < StandardError; end

    DEFAULT_URL = "http://licence-server-origin:3000/internal/licences"

    # transport: anything answering call(uri, request) with an object that
    # has code and body. Tests pass a fake; nothing else does.
    def initialize(url: ENV.fetch("ACME_LICENCE_URL", DEFAULT_URL), token_file: ENV["ACME_LICENCE_TOKEN_FILE"], transport: nil)
      @uri = URI(url)
      @token_file = token_file
      @transport = transport || method(:net_http)
    end

    # Stable and never reused: SQLite reuses the ids of deleted rows, so the
    # signup's random referral code names it, not its id.
    def self.reference_for(signup) = "waitlist-#{signup.referral_code}"

    # Returns licence-server's licence_id. Raises on anything but a 2xx answer
    # with a licence_id, so ApprovalJob retries.
    def issue(signup)
      request = Net::HTTP::Post.new(@uri)
      request["Authorization"] = "Bearer #{token}"
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request.body = JSON.generate(email: signup.email, reference: self.class.reference_for(signup))
      response = @transport.call(@uri, request)
      code = response.code.to_i
      raise Error, "licence-server refused the licence registration (HTTP #{code}#{error_code(response)})" unless (200..299).cover?(code)
      licence_id = parse(response.body)["licence_id"]
      raise Error, "licence-server answered without a licence_id" unless licence_id.is_a?(String) && licence_id.match?(/\A[0-9a-f-]{36}\z/i)
      licence_id
    rescue SocketError, SystemCallError, Timeout::Error, IOError => error
      raise Error, "Could not reach licence-server: #{error.class}"
    end

    private

    def token
      value = @token_file.present? && File.file?(@token_file) ? File.read(@token_file).strip : ""
      raise Error, "No licence issuer token (ACME_LICENCE_TOKEN_FILE)" if value.empty?
      value
    end

    def parse(body)
      parsed = JSON.parse(body.to_s)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    # Only licence-server's fixed error code, never the body.
    def error_code(response)
      code = parse(response.body).dig("error", "code")
      code.is_a?(String) && code.match?(/\A[a-z_]{1,40}\z/) ? ", #{code}" : ""
    end

    def net_http(uri, request)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 15) { |http| http.request(request) }
    end
  end
end
