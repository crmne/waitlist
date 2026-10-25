require "test_helper"

class AcmeLicenceTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body)
  LICENCE_ID = "0b7e4f7a-8f6c-4c1e-9a43-2f1d8f0b5c11"

  setup do
    @dir = Dir.mktmpdir("licence-token", Rails.root.join("tmp"))
    @token_file = File.join(@dir, "token")
    File.write(@token_file, "secret-token\n")
    @signup = confirmed_signup("dj@example.com")
    @requests = []
  end

  teardown { FileUtils.rm_rf(@dir) }

  def issuer(code: "201", body: JSON.generate(licence_id: LICENCE_ID, number: 1, expires_at: "2027-04-23T00:00:00Z"), token_file: @token_file, &block)
    transport = block || ->(uri, request) { @requests << [uri, request]; Response.new(code, body) }
    LicenceIssuers::AcmeLicence.new(url: "http://licence-server-origin:3000/internal/licences", token_file:, transport:)
  end

  test "registers the licence over the Docker network and returns its licence_id" do
    assert_equal LICENCE_ID, issuer.issue(@signup)
    uri, request = @requests.sole
    assert_equal "http://licence-server-origin:3000/internal/licences", uri.to_s
    assert_equal "POST", request.method
    assert_equal "Bearer secret-token", request["Authorization"]
    assert_equal "application/json", request["Content-Type"]
    assert_equal({ "email" => "dj@example.com", "reference" => "waitlist-signup-#{@signup.id}" }, JSON.parse(request.body))
    assert_nil request["CF-Connecting-IP"]
  end

  test "a repeat answered 200 is the same licence" do
    assert_equal LICENCE_ID, issuer(code: "200").issue(@signup)
  end

  test "anything but a 2xx with a licence_id raises, naming only licence-server's error code" do
    error = assert_raises(LicenceIssuers::AcmeLicence::Error) do
      issuer(code: "400", body: JSON.generate(error: { code: "invalid_request", message: "dj@example.com was refused" })).issue(@signup)
    end
    assert_equal "licence-server refused the licence registration (HTTP 400, invalid_request)", error.message
    assert_raises(LicenceIssuers::AcmeLicence::Error) { issuer(code: "401", body: "").issue(@signup) }
    assert_raises(LicenceIssuers::AcmeLicence::Error) { issuer(code: "404", body: "<html>").issue(@signup) }
    assert_raises(LicenceIssuers::AcmeLicence::Error) { issuer(code: "201", body: JSON.generate(licence_id: "nope")).issue(@signup) }
    assert_raises(LicenceIssuers::AcmeLicence::Error) { issuer { raise Errno::ECONNREFUSED }.issue(@signup) }
  end

  test "without a token nothing is sent" do
    assert_raises(LicenceIssuers::AcmeLicence::Error) { issuer(token_file: File.join(@dir, "missing")).issue(@signup) }
    assert_raises(LicenceIssuers::AcmeLicence::Error) { issuer(token_file: nil).issue(@signup) }
    assert_empty @requests
  end
end
