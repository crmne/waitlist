# What approving someone does, per product (`approval` in
# config/products.yml). Each issuer answers `issue(signup)` with a reference
# to the licence it created (never the key itself), or nil when nothing was
# issued yet.
module LicenceIssuers
  NAMES = %w[acme_licence].freeze

  def self.for(name)
    case name
    when "acme_licence" then AcmeLicence.new
    else raise ArgumentError, "unknown approval #{name.inspect}"
    end
  end
end
