require "resolv"

# Whether an address's domain can receive mail: it has an MX record that
# isn't the "no mail" null MX (RFC 7505), or, with no MX at all, an A or
# AAAA record (RFC 5321's implicit MX). Positive answers are cached for an
# hour, negative ones for a minute, in memory only.
module EmailDomain
  CACHE = ActiveSupport::Cache::MemoryStore.new(size: 1.megabyte)

  # Tests replace this with a lambda; nothing else does.
  mattr_accessor :resolver, default: ->(domain) { EmailDomain.lookup(domain) }

  def self.deliverable?(email)
    domain = email.to_s.split("@", 2).last.to_s.strip.downcase.delete_suffix(".")
    return false unless domain.match?(/\A[a-z0-9-]+(\.[a-z0-9-]+)+\z/)
    cached = CACHE.read(domain)
    return cached unless cached.nil?
    resolver.call(domain).tap { |answer| CACHE.write(domain, answer, expires_in: answer ? 1.hour : 1.minute) }
  end

  def self.lookup(domain)
    Resolv::DNS.open do |dns|
      dns.timeouts = 3
      mx = dns.getresources(domain, Resolv::DNS::Resource::IN::MX)
      return mx.any? { |record| record.exchange.to_s.present? } if mx.any?
      dns.getresources(domain, Resolv::DNS::Resource::IN::A).any? ||
        dns.getresources(domain, Resolv::DNS::Resource::IN::AAAA).any?
    end
  end
end
