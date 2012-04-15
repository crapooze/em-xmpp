
require 'resolv'
module EM::Xmpp
  module Resolver
    extend self

    def resolve(domain)
      resolve_all(domain).first
    end

    def resolve_all(domain)
      srv = []
      Resolv::DNS.open do |dns|
        record = "_xmpp-client._tcp.#{domain}"
        srv = dns.getresources(record, Resolv::DNS::Resource::IN::SRV)
      end

      srv.sort do |a,b|
        (a.priority != b.priority) ? (a.priority <=> b.priority) : (b.weight <=> a.weight)
      end
    end
  end
end
