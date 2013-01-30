
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

    # Generates a MUC entity from this entity.
    # If the nick argument is null then the entity is the MUC itself.
    # If the nick argument is present, then the entity is the user with 
    # the corresponding nickname.
    def muc(nick=nil)
      muc_jid = JID.new jid.node, jid.domain, nick
      Muc.new(connection, muc_jid)
    end

    class Muc < Entity
      # The room corresponding to this entity.
      def room
        muc(nil)
      end

      # Join a MUC.
      def join(nick,pass=nil,historysize=0,&blk)
        pres = connection.presence_stanza('to'=> muc(nick).to_s) do |xml|
          xml.password pass if pass
          xml.x('xmlns' => Namespaces::Muc) do |x|
            x.history('maxchars' => historysize.to_s)
          end
        end
        connection.send_stanza pres, &blk
      end

      # Leave a MUC.
      def part(nick,msg=nil)
        pres = connection.presence_stanza('to'=> muc(nick).to_s,'type'=>'unavailable') do |xml|
          xml.status msg if msg
        end
        connection.send_stanza pres
      end

      # Changes nickname in this room.
      def change_nick(nick)
        join(nick)
      end

      # Say some message in the muc.
      def say(body, xmlproc=nil, &blk)
        msg = connection.message_stanza(:to => jid, :type => 'groupchat') do |xml|
          xml.body body
          xmlproc.call xml if xmlproc
        end
        connection.send_stanza msg, &blk
      end

      private

      def set_role(role,nick,reason=nil,&blk)
        iq = connection.iq_stanza(:to => jid,:type => 'set') do |xml|
          xml.query('xmlns' => Namespaces::MucAdmin) do |q|
            q.item('nick' => nick, 'role' => role) do |r|
              r.reason reason if reason
            end
          end
        end
        connection.send_stanza iq, &blk
      end

      def set_affiliation(affiliation,affiliated_jid,reason=nil,&blk)
        iq = connection.iq_stanza(:to => jid,:type => 'set') do |xml|
          xml.query('xmlns' => Namespaces::MucAdmin) do |q|
            q.item('affiliation' => affiliation, 'jid' => affiliated_jid)  do |r|
              r.reason reason if reason
            end
          end
        end
        connection.send_stanza iq, &blk
      end

      public

      # kick a user (based on his nickname) from the channel
      def kick(nick,reason="no reason",&blk)
        set_role 'none', nick, reason, &blk
      end

      # voice a user (based on his nickname) in a channel
      def voice(nick,reason=nil,&blk)
        set_role 'participant', nick, reason, &blk
      end

      # remove voice flag from a user (based on his nickname) in a channel
      def unvoice(nick,reason=nil,&blk)
        set_role 'visitor', nick, reason, &blk
      end

      # set a ban on a user (from his bare JID) from the channel
      def ban(jid,reason="no reason",&blk)
        set_affiliation 'outcast', jid, reason, &blk
      end

      # lifts the ban on a user (from his bare JID) from the channel
      def unban(jid,reason=nil,&blk)
        set_affiliation 'none', jid, reason, &blk
      end

      # sets membership to the room
      def member(jid,reason=nil,&blk)
        set_affiliation 'member', jid, reason, &blk
      end

      # removes membership to the room
      def unmember(jid,reason=nil,&blk)
        set_affiliation 'none', jid, reason, &blk
      end

      # sets moderator status
      def moderator(jid,reason=nil,&blk)
        set_role 'moderator', jid, reason, &blk
      end

      # removes moderator status
      def unmoderator(jid,reason=nil,&blk)
        set_role 'participant', jid, reason, &blk
      end

      # gives ownership of the room
      def owner(jid,reason=nil,&blk)
        set_affiliation 'owner', jid, reason, &blk
      end

      # removes membership of the room
      def unowner(jid,reason=nil,&blk)
        set_affiliation 'admin', jid, reason, &blk
      end

      # gives admin rights on the room
      def admin(jid,reason=nil,&blk)
        set_affiliation 'admin', jid, reason, &blk
      end

      # removes admin rights on of the room
      def unadmin(jid,reason=nil,&blk)
        set_affiliation 'member', jid, reason, &blk
      end

      #TODO: understand what needs jid and what needs nickname

      #      get configure form
      #      configure max users
      #      configure as reserved
      #      configure public jids
      #      create/destroy a room

      # asks for a nickname registration
      def register_nickname(nick)
        #TODO: fiber blocks on getting the registration form
        #      user fills-in the form and submit
        #      rooms returns result
        raise NotImplementedError
      end

      # request voice to the moderators
      def request_voice(nick)
        #TODO: fiber blocks on getting the registration form
        #      user fills-in the form and submit
        #      rooms returns result
        raise NotImplementedError
      end

      # gets the list of registered nicknames for that list
      def registered_nicknames
        raise NotImplementedError
      end

      def voice_list
        raise NotImplementedError
      end

      def banned_list
        raise NotImplementedError
      end

      def owner_list
        raise NotImplementedError
      end

      def admin_list
        raise NotImplementedError
      end

      # sets the room subject (Message Of The Day)
      def motd(subject,&blk)
        msg = connection.message_stanza(:to => jid) do |xml|
          xml.subject subject
        end
        connection.send_stanza msg, &blk
      end

      # invites someone (based on his jid) to the MUC
      def invite(invited_jid,reason="no reason",&blk)
        msg = connection.message_stanza(:to => jid) do |xml|
          xml.x('xmlns' => Namespaces::MucUser) do |x|
            x.invite('to' => invited_jid.to_s) do |invite|
              invite.reason reason
            end
          end
        end
        connection.send_stanza msg, &blk
      end

    end

  end
end
