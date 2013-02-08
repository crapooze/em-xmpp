
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

    # returns the domain entity of this entity
    def domain
      Entity.new(connection, jid.domain)
    end

    # returns the bare entity of this entity
    def bare
      Entity.new(connection, jid.bare)
    end

    # returns the full jid of this entity
    def full
      jid.full
    end

    # to_s is defined as the jid.to_s
    # so that you can just pass the entity when building stanzas
    # to refer to the entity (e.g., message_stanza('to' => some_entity) )
    def to_s
      jid.to_s
    end

    # sends a subscription request to the bare entity
    def subscribe(&blk)
      pres = connection.presence_stanza('to'=>jid.bare, 'type' => 'subscribe')
      connection.send_stanza pres, &blk
    end

    # send a subscription stanza to accept an incoming subscription request
    def accept_subscription(&blk)
      pres = connection.presence_stanza('to'=>jid.bare, 'type' => 'subscribed')
      connection.send_stanza pres, &blk
    end

    # unsubscribes from from the bare entity
    def unsubscribe(&blk)
      pres = connection.presence_stanza('to'=>jid.bare, 'type' => 'unsubscribe')
      connection.send_stanza pres, &blk
    end

    # sends some plain message to the entity (use type = 'chat')
    def say(body, type='chat', xmlproc=nil, &blk)
      msg = connection.message_stanza(:to => jid, :type => type) do |xml|
        xml.body body
        xmlproc.call xml if xmlproc
      end
      connection.send_stanza msg, &blk
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

    # add the entity (bare) to the roster
    # optional parameters can set the display name (or friendly name)
    # for the roster entity
    #
    # similarly, you can attach the entity to one or multiple groups
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

    # removes an entity (bare) from the roster
    def remove_from_roster
      item_fields = {:jid => jid.bare, :subscription => 'remove'}

      query = connection.iq_stanza(:type => 'set') do |iq|
        iq.query(:xmlns => Roster) do |q|
          q.item item_fields
        end
      end

      send_iq_stanza_fibered query
    end

    # discovers infos (disco#infos) about an entity
    # can optionally specify a node of the entity
    def discover_infos(node=nil)
      hash = {'xmlns' => Namespaces::DiscoverInfos}
      hash['node'] = node if node
      iq = connection.iq_stanza('to'=>jid) do |xml|
        xml.query(hash)
      end
      send_iq_stanza_fibered iq
    end

    # discovers items (disco#items) of an entity
    # can optionally specify a node to discover
    def discover_items(node=nil)
      iq = connection.iq_stanza('to'=>jid.to_s) do |xml|
        xml.query('xmlns' => Namespaces::DiscoverItems)
      end
      send_iq_stanza_fibered iq
    end

    # returns a PubSub entity with same bare jid
    # accepts an optional node-id
    def pubsub(nid=nil)
      node_jid = if nid
                   JID.new(jid.node, jid.domain, nid)
                 else
                   jid.to_s
                 end
      PubSub.new(connection, node_jid)
    end

    # returns a (file-)Transfer entity with same jid
    def transfer
      Transfer.new(connection, jid)
    end

    # returns an entity to communicate with the Avatar service
    def avatar
      Avatar.new(connection, jid.bare)
    end

    class Transfer < Entity
      def self.describe_file(path)
        ret = {}
        ret[:name] = File.basename path
        ret[:size] = File.read(path).size #FIXME use file stats
        ret[:mime] = 'text/plain' #FIXME
        ret[:hash] = nil #TODO
        ret[:date] = nil #TODO
        ret
      end

      def negotiation_request(filedesc,sid,form)
        si_args = {'profile'    => EM::Xmpp::Namespaces::FileTransfer,
                   'mime-type'  => filedesc[:mime]
        }
        file_args = {'name' => filedesc[:name],
          'size' => filedesc[:size],
          'hash' => filedesc[:md5],
          'date' => filedesc[:date]
        }
        iq = connection.iq_stanza('to'=>jid,'type'=>'set') do |xml|
          xml.si({:xmlns => EM::Xmpp::Namespaces::StreamInitiation, :id => sid}.merge(si_args)) do |si|
            si.file({:xmlns => EM::Xmpp::Namespaces::FileTransfer}.merge(file_args)) do |file|
              file.desc filedesc[:description]
            end
            si.feature(:xmlns => EM::Xmpp::Namespaces::FeatureNeg) do |feat|
              connection.build_submit_form(feat,form)
            end
          end
        end
        send_iq_stanza_fibered iq
      end

      def negotiation_reply(reply_id,form)
        iq = connection.iq_stanza('to'=>jid,'type'=>'result','id'=>reply_id) do |xml|
          xml.si(:xmlns => EM::Xmpp::Namespaces::StreamInitiation) do |si|
            si.feature(:xmlns => EM::Xmpp::Namespaces::FeatureNeg) do |feat|
              connection.build_submit_form(feat,form)
            end
          end
        end
        connection.send_stanza iq
      end
    end

    class Avatar < Entity
      Item = Struct.new(:sha1, :data, :width, :height, :mime) do
        def id
          sha1 || Digest::SHA1.hexdigest(data)
        end
        def b64
          Base64.strict_encode64 data
        end
        def bytes
          data.size
        end
      end

      def publish(item)
        publish_data item
        publish_metadata item
      end

      def publish_data(item)
        iq = connection.iq_stanza('type' => 'set','to' => jid) do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |pubsub|
            pubsub.publish(:node => EM::Xmpp::Namespaces::AvatarData) do |pub|
              pub.item(:id => item.id) do |i|
                i.data({:xmnls => EM::Xmpp::Namespaces::AvatarData}, item.b64)
              end
            end
          end
        end
        send_iq_stanza_fibered iq
      end

      def publish_metadata(item)
        iq = connection.iq_stanza('type' => 'set','to' => jid) do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |pubsub|
            pubsub.publish(:node => EM::Xmpp::Namespaces::AvatarMetaData) do |pub|
              pub.item(:id => item.id) do |i|
                i.metadata({:xmnls => EM::Xmpp::Namespaces::AvatarMetaData}) do |md|
                  md.info(:width => item.width, :height => item.height, :bytes => item.bytes, :type => item.mime, :id => item.id)
                end
              end
            end
          end
        end
        send_iq_stanza_fibered iq
      end
      
      def remove
        iq = connection.iq_stanza('type' => 'set','to' => jid) do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |pubsub|
            pubsub.publish(:node => EM::Xmpp::Namespaces::AvatarMetaData) do |pub|
              pub.item(:id => "current") do |i|
                i.metadata(:xmlns => EM::Xmpp::Namespaces::AvatarMetaData)
              end
            end
          end
        end
        send_iq_stanza_fibered iq
      end
    end

    class PubSub < Entity
      # returns the pubsub entity for a specific node_id of this entity
      def node(node_id)
        pubsub(node_id)
      end

      # returns the node_id of this pubsub entity
      def node_id
        jid.resource
      end

      # requests the list of subscriptions on this PubSub service
      # returns the iq context for the answer
      def service_subscriptions
        iq = connection.iq_stanza('to'=>jid.bare) do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |pubsub|
            pubsub.subscriptions
          end
        end
        send_iq_stanza_fibered iq
      end

      # requests the list of affiliations for this PubSub service
      # returns the iq context for the answer
      def service_affiliations
        iq = connection.iq_stanza('to'=>jid.bare) do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |pubsub|
            pubsub.affiliations
          end
        end
        send_iq_stanza_fibered iq
      end

      # list the subscription on that node
      # returns the iq context for the answer
      def subscription_options(subscription_id=nil)
        params = {}
        params['subid'] = subscription_id if subscription_id
        subscribee = connection.jid.bare

        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'get') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |sub|
            sub.options({'node' => node_id, 'jid'=>subscribee}.merge(params))
          end
        end

        send_iq_stanza_fibered iq
      end

      # sets configuration options on this entity
      # uses a DataForms form
      # returns the iq context for the answer
      def configure_subscription(form)
        subscribee = connection.jid.bare

        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'set') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |sub|
            sub.options({'node' => node_id, 'jid'=>subscribee}) do |options|
              connection.build_submit_form(options,form)
            end
          end
        end

        send_iq_stanza_fibered iq
      end

      # retrieve default configuration of this entity
      # returns the iq context for the answer
      def default_subscription_configuration
        subscribee = connection.jid.bare
        args = {'node' => node_id} if node_id
        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'get') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |sub|
            sub.default(args)
          end
        end

        send_iq_stanza_fibered iq
      end


      # subscribe to this entity
      # returns the iq context for the answer
      def subscribe
        subscribee = connection.jid.bare

        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'set') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |sub|
            sub.subscribe('node' => node_id, 'jid'=>subscribee)
          end
        end

        send_iq_stanza_fibered iq
      end

      # subscribe and configure this entity at the same time
      # see subscribe and configure
      # returns the iq context for the answer
      def subscribe_and_configure(form)
        subscribee = connection.jid.bare

        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'set') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |sub|
            sub.subscribe('node' => node_id, 'jid'=>subscribee)
            sub.options do |options|
              connection.build_submit_form(options,form)
            end
          end
        end

        send_iq_stanza_fibered iq
      end

      # unsubscribes from this entity. 
      # One must provide a subscription-id if there
      # are multiple subscriptions to this node.
      # returns the iq context for the answer
      def unsubscribe(subscription_id=nil)
        params = {}
        params['subid'] = subscription_id if subscription_id
        subscribee = connection.jid.bare

        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'set') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |sub|
            sub.unsubscribe({'node' => node_id, 'jid'=>subscribee}.merge(params))
          end
        end

        send_iq_stanza_fibered iq
      end

      # list items of this pubsub node
      # max_items is the maximum number of answers to return in the answer
      # item_ids is the list of IDs to select from the pubsub node
      #
      # returns the iq context for the answer
      def items(max_items=nil,item_ids=nil)
        params = {}
        params['max_items'] = max_items if max_items
        iq = connection.iq_stanza('to'=>jid.bare) do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |retrieve|
            retrieve.items({'node' => node_id}.merge(params)) do |items|
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

      # publishes a payload to the pubsub node
      # if the item_payload responds to :call (e.g., a proc)
      # then the item_payload will receive :call method with, as unique parameter,
      # the xml node of the xml builder. this method call should append an entry
      # node with the payload
      # otherwise it is just serialized in an entry node
      #
      # item_id is an optional ID to identify the payload, otherwise, the
      # pubsub service will attribute an ID
      #
      # returns the iq context for the answer
      def publish(item_payload,item_id=nil)
        params = {}
        params['id'] = item_id if item_id
        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'set') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |pubsub|
            pubsub.publish(:node => node_id) do |publish|
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

      # Retracts an item on a PubSub node given it's item_id.
      #
      # returns the iq context for the answer
      def retract(item_id=nil)
        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'set') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |pubsub|
            pubsub.retract(:node => node_id) do |retract|
              retract.item(:id => item_id) 
            end
          end
        end

        send_iq_stanza_fibered iq
      end

      # Creates the PubSub node.
      #
      # returns the iq context for the answer
      def create
        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'set') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |pubsub|
            pubsub.create(:node => node_id)
          end
        end

        send_iq_stanza_fibered iq
      end


      # Purges the PubSub node.
      #
      # returns the iq context for the answer
      def purge
        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'set') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSubOwner) do |pubsub|
            pubsub.purge(:node => node_id)
          end
        end

        send_iq_stanza_fibered iq
      end

      # requests the list of subscriptions on this pubsub node (for the owner)
      # returns the iq context for the answer
      def subscriptions
        iq = connection.iq_stanza('to'=>jid.bare) do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSubOwner) do |pubsub|
            pubsub.subscriptions(:node => node_id)
          end
        end
        send_iq_stanza_fibered iq
      end

      # requests the list of affiliations on this pubsub node (for the owner)
      # returns the iq context for the answer
      def affiliations
        iq = connection.iq_stanza('to'=>jid.bare) do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSubOwner) do |pubsub|
            pubsub.affiliations(:node => node_id)
          end
        end
        send_iq_stanza_fibered iq
      end

      # changes the subscription status of a pubsub node (for the owner)
      # returns the iq context for the answer
      def modify_subscriptions(subs)
        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'set') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSubOwner) do |pubsub|
            pubsub.subscriptions(:node => node_id) do |node|
              subs.each do  |s|
                node.subscription(:jid => s.jid, :subscription => s.subscription, :subid => s.sub_id)
              end
            end
          end
        end
        send_iq_stanza_fibered iq
      end

      # changes the affiliation status of a pubsub node (for the owner)
      # returns the iq context for the answer
      def modify_affiliations(affs)
        affs = [affs].flatten
        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'set') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSubOwner) do |pubsub|
            pubsub.affiliations(:node => node_id) do |node|
              affs.each do  |s|
                node.affiliation(:jid => s.jid, :affiliation => s.affiliation)
              end
            end
          end
        end
        send_iq_stanza_fibered iq
      end

      # deletes the subscription of one or multiple subscribees of a pubsub node (for the owner)
      # returns the iq context for the answer
      def delete_subscriptions(jids,subids=nil)
        jids = [jids].flatten
        subids = [subids].flatten
        subs = jids.zip(subids).map{|jid,subid| EM::Xmpp::Context::Contexts::PubsubMain::Subscription.new(jid, nil, 'none', subid, nil)}
        modify_subscriptions subs
      end

      # deletes the affiliation of one or multiple subscribees of a pubsub node (for the owner)
      # returns the iq context for the answer
      def delete_affiliations(jids)
        jids = [jids].flatten
        affs = jids.map{|jid| EM::Xmpp::Context::Contexts::PubsubMain::Affiliation.new(jid, node_id, 'none')}
        modify_affiliations affs
      end

      # Deletes the PubSub node.
      # Optionnaly redirects the node.
      #
      # returns the iq context for the answer
      def delete(redirect_uri=nil)
        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'set') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSubOwner) do |pubsub|
            pubsub.delete(:node => node_id) do |del|
              del.redirect(:uri => redirect_uri) if redirect_uri
            end
          end
        end

        send_iq_stanza_fibered iq
      end

      # Creates the PubSub node with a non-default configuration.
      #
      # returns the iq context for the answer
      def create_and_configure(form)
        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'set') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSub) do |node|
            node.create('node' => node_id)
            node.configure do |options|
              connection.build_submit_form(options,form)
            end
          end
        end

        send_iq_stanza_fibered iq
      end


      # requests the node configuration (for owners)
      #
      # returns the iq context for the answer
      def configuration_options
        iq = connection.iq_stanza('to'=>jid.bare) do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSubOwner) do |node|
            node.configure('node' => node_id)
          end
        end

        send_iq_stanza_fibered iq
      end

      # configures the node (for owners)
      #
      # returns the iq context for the answer
      def configure(form)
        iq = connection.iq_stanza('to'=>jid.bare,'type'=>'set') do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSubOwner) do |node|
            node.configure('node' => node_id) do |config|
              connection.build_submit_form(config,form)
            end
          end
        end

        send_iq_stanza_fibered iq
      end

      # retrieve default configuration of this pubsub service
      #
      # returns the iq context for the answer
      def default_configuration
        iq = connection.iq_stanza('to'=>jid.bare) do |xml|
          xml.pubsub(:xmlns => EM::Xmpp::Namespaces::PubSubOwner) do |sub|
            sub.default
          end
        end

        send_iq_stanza_fibered iq
      end


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
        send_iq_stanza_fibered iq
      end

      def set_affiliation(affiliation,affiliated_jid,reason=nil,&blk)
        iq = connection.iq_stanza(:to => jid,:type => 'set') do |xml|
          xml.query('xmlns' => Namespaces::MucAdmin) do |q|
            q.item('affiliation' => affiliation, 'jid' => affiliated_jid)  do |r|
              r.reason reason if reason
            end
          end
        end
        send_iq_stanza_fibered iq
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

      #TODO: 
      #      get configure-form
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
