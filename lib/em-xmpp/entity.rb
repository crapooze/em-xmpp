
require 'em-xmpp/jid'
require 'em-xmpp/namespaces'
require 'fiber'

module EM::Xmpp
  class Entity
    attr_reader :jid, :connection

    def initialize(connection, jid)
      @connection = connection
      @jid        = JID.parse jid.to_s
      yield self if block_given?
    end

    def domain
      Entity.new(connection, jid.domain)
    end

    def bare
      Entity.new(connection, jid.bare)
    end

    def to_s
      jid.to_s
    end

    #TODO: subscribe, unsubscribe, say, pub, sub, etc.

    def discover_infos(node=nil)
      f = Fiber.current
      hash = {'xmlns' => Namespaces::DiscoverInfos}
      hash['node'] = node if node
      iq = connection.iq_stanza('to'=>jid) do |xml|
        xml.query(hash)
      end
      connection.send_stanza(iq) do |ctx|
        f.resume ctx
      end
      Fiber.yield
    end

    def discover_items(node=nil)
      f = Fiber.current
      iq = connection.iq_stanza('to'=>jid.to_s) do |xml|
        xml.query('xmlns' => Namespaces::DiscoverItems)
      end
      connection.send_stanza(iq) do |ctx|
        f.resume ctx
      end
      Fiber.yield
    end
  end
end
