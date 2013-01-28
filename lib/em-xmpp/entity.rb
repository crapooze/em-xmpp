
require 'em-xmpp/jid'
require 'em-xmpp/namespaces'
require 'fiber'

module EM::Xmpp
  class Entity
    include Namespaces
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

    def full
      jid.full
    end

    def to_s
      jid.to_s
    end

    #TODO: pub, sub, etc.

    def say(body, &blk)
      msg = connection.message_stanza(:to => jid) do |x|
        x.body body
      end
      connection.send_stanza msg, &blk
    end

    def subscribe(&blk)
      pres = connection.presence_stanza('to'=>jid.bare, 'type' => 'subscribe')
      connection.send_stanza pres, &blk
    end

    def unsubscribe(&blk)
      pres = connection.presence_stanza('to'=>jid.bare, 'type' => 'unsubscribe')
      connection.send_stanza pres, &blk
    end

    def add_to_roster(display_name=nil,groups=[])
      f = Fiber.current
      item_fields = {:jid => jid.bare}
      item_fields[:name] = display_name if display_name

      query = connection.iq_stanza(:type => 'set') do |iq|
        iq.query(:xmlns => Roster) do |q|
          q.item item_fields
          groups.each do |grp|
            q.group grp
          end
        end
      end

      connection.send_stanza(query) do |ctx|
        f.resume ctx
      end
      Fiber.yield
    end

    def remove_from_roster
      f = Fiber.current
      item_fields = {:jid => jid.bare, :subscription => 'remove'}

      query = connection.iq_stanza(:type => 'set') do |iq|
        iq.query(:xmlns => Roster) do |q|
          q.item item_fields
        end
      end
      connection.send_stanza(query) do |ctx|
        f.resume ctx
      end
      Fiber.yield
    end

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
