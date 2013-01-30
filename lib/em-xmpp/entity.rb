
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

    private

    def send_iq_stanza_fibered(iq)
      f = Fiber.current
      connection.send_stanza(iq) do |ctx|
        f.resume ctx
      end
      Fiber.yield
    end

    public

    def add_to_roster(display_name=nil,groups=[])
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

      send_iq_stanza_fibered query
    end

    def remove_from_roster
      item_fields = {:jid => jid.bare, :subscription => 'remove'}

      query = connection.iq_stanza(:type => 'set') do |iq|
        iq.query(:xmlns => Roster) do |q|
          q.item item_fields
        end
      end

      send_iq_stanza_fibered query
    end

    def discover_infos(node=nil)
      hash = {'xmlns' => Namespaces::DiscoverInfos}
      hash['node'] = node if node
      iq = connection.iq_stanza('to'=>jid) do |xml|
        xml.query(hash)
      end
      send_iq_stanza_fibered iq
    end

    def discover_items(node=nil)
      iq = connection.iq_stanza('to'=>jid.to_s) do |xml|
        xml.query('xmlns' => Namespaces::DiscoverItems)
      end
      send_iq_stanza_fibered iq
    end

    def pubsub(nid=nil)
      node_jid = if nid
                   JID.new(jid.node, jid.domain, nid)
                 else
                   jid.to_s
                 end
      PubSub.new(connection, node_jid)
    end

    class PubSub < Entity
      def node(node_id)
        pubsub(node_id)
      end

      def node_id
        jid.resource
      end

      def subscriptions
        iq = connection.iq_stanza('to'=>jid.bare) do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |pubsub|
            pubsub.subscriptions
          end
        end
        send_iq_stanza_fibered iq
      end

      def affiliations
        iq = connection.iq_stanza('to'=>jid.bare) do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |pubsub|
            pubsub.affiliations
          end
        end
        send_iq_stanza_fibered iq
      end

      def subscribe(subscribed_node_id=nil)
        subscribed_node_id ||= node_id
        subscribee = connection.jid.bare

        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'set') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |sub|
            sub.subscribe('node' => subscribed_node_id, 'jid'=>subscribee)
          end
        end

        send_iq_stanza_fibered iq
      end

      def unsubscribe(subscription_id=nil,subscribed_node_id=nil)
        params = {}
        params['subid'] = subscription_id if subscription_id
        subscribed_node_id ||= node_id
        subscribee = connection.jid.bare

        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'set') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |sub|
            sub.unsubscribe({'node' => subscribed_node_id, 'jid'=>subscribee}.merge(params))
          end
        end

        send_iq_stanza_fibered iq
      end

      def items(max_items=nil,item_ids=nil,node=nil)
        node ||= node_id
        params = {}
        params['max_items'] = max_items if max_items
        iq = connection.iq_stanza('to'=>jid.bare) do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |retrieve|
            retrieve.items({'node' => subscribed_node_id}.merge(params)) do |items|
              if item_ids.respond_to?(:each)
                item_ids.each do |item_id|
                  items('id' => item_id)
                end
              end
            end
          end
        end

        send_iq_stanza_fibered iq
      end

      def publish(item_payload,node=nil,item_id=nil)
        node ||= node_id
        params = {}
        params['id'] = item_id if item_id
        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'set') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |pubsub|
            pubsub.publish(:node => node) do |publish|
              if item_payload.respond_to?(:call)
                publish.item(params) { |payload| item_payload.call payload }
              else
                publish.item(params) do |item|
                  item.entry(item_payload)
                end
              end

            end
          end
        end

        send_iq_stanza_fibered iq
      end

      #TODO: configure
      #      subscribe_and_configure
    end
  end
end
