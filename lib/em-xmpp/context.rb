
require 'em-xmpp/jid'
require 'em-xmpp/entity'
require 'em-xmpp/namespaces'
require 'time'
require 'date'
require 'ostruct'

module EM::Xmpp
  class Context
    attr_reader :connection, :stanza, :env, :bits

    def []key
      env[key]
    end

    def []=key,val
      env[key]= val
    end

    def default_env
      {'modules' => [], 'done' => false}
    end

    def done!
      env['ctx.done'] = true
      self
    end

    def done?
      env['ctx.done']
    end

    def delete_xpath_handler!
      env.delete 'xpath.handler'
      self
    end

    def reuse_handler?
      env['xpath.handler']
    end

    def initialize(conn, stanza, env={})
      @bits       = {}
      @connection = conn
      @stanza     = stanza
      @env        = default_env.merge env
    end

    def xpath(path, args={})
      stanza.xpath(path, args) || []
    end

    def xpath?(path, args={})
      xpath(path, args).any?
    end

    def read_attr(node, name, sym=:to_s, &blk)
      val = node[name]
      if val
        if blk
          blk.call val
        else
          val.send sym
        end
      end
    end

    def with(modname)
      if $DEBUG
        $stderr.puts "using outdated <with> which is slow"
      end
      bit! modname
      slow_with modname
    end

    def slow_with(modname)
      mod = if modname.is_a?(Module)
              modname
            else
              Contexts.const_get(modname.to_s.capitalize)
            end
      env['modules'] << mod
      obj = self
      obj.extend mod
      obj
    end

    def bit(klassname)
      bits[bit_klass_name(klassname)] 
    end

    def bit!(klassname)
      ret = bit klassname
      unless ret
        klass = if klassname.is_a?(Class)
                  klassname
                else
                  Bits.const_get(klassname.to_s.capitalize)
                end
        ret = bit_from_klass klass
      end
      ret
    end

    def bit?(klassname)
      bits.has_key? bit_klass_name(klassname)
    end

    private 

    def bit_klass_name(obj)
      obj.to_s.split('::').last.capitalize
    end

    def bit_from_klass(klass)
      obj = klass.new(self)
      bits[bit_klass_name(klass)] = obj
      obj
    end

    public

    module Contexts
      module IncomingStanza
        include Namespaces
        %w{type id lang}.each do |w|
          define_method w do
            read_attr stanza, w
          end
        end
        def to
          read_attr(stanza, 'to'){|j| connection.entity(j)}
        end
        def from
          read_attr(stanza, 'from'){|j| connection.entity(j)}
        end
        def error?
          type == 'error'
        end
        def delay?
          false
        end
      end

      module Error
        def error_node
          xpath('//xmlns:error',{'xmlns' => Client}).first
        end

        def error_code
          n = error_node
          read_attr(n, 'code') if n
        end

        def error_type
          n = error_node
          read_attr(n, 'type') if n
        end

        def error_condition_node
          n = error_node
          n.children.first if n
        end

        def error_condition
          n = error_condition_node
          n.name if n
        end
      end

      module Presence
        include IncomingStanza
        def reply_default_params
          jid = connection.jid.full
          {'from' => jid, 'to' => from, 'id' => id}
        end
        def reply(args={},&blk)
          args = reply_default_params.merge args
          connection.presence_stanza(args,&blk)
        end
        def priority_node
          xpath('//xmlns:priority',{'xmlns' => Client}).first
        end
        def status_node
          xpath('//xmlns:status',{'xmlns' => Client}).first
        end
        def show_node
          xpath('//xmlns:show',{'xmlns' => Client}).first
        end
        def priority
          node = priority_node
          node.content if node
        end
        def status
          node = status_node
          node.content if node
        end
        def show
          node = show_node
          node.content if node
        end
        def subscription_request?
          type == 'subscribe'
        end
        def entity_left?
          type == 'unavailable'
        end
      end

      module Message
        include IncomingStanza
        def subject_node
          xpath('//xmlns:subject',{'xmlns' => Client}).first
        end

        def subject
          node = subject_node
          node.text if node
        end

        def body_node
          xpath('//xmlns:body',{'xmlns' => Client}).first
        end

        def body
          node = body_node
          node.text if node
        end

        def reply_default_params
          h = {'to' => from, 'type' => type}
          h['id'] = id.succ if id
          h
        end

        def reply(args={},&blk)
          args = reply_default_params.merge args
          connection.message_stanza(args,&blk)
        end

        def groupchat?
          type == 'groupchat'
        end
      end

      module Iq
        include IncomingStanza
        def reply_default_params
          jid = connection.jid.full
          {'from' => jid, 'to' => from, 'type' => 'result', 'id' => id}
        end

        def reply(args={},&blk)
          args = reply_default_params.merge args
          connection.iq_stanza(args,&blk)
        end
      end

      module Delay
        def delay?
          true
        end
        #does not handle legacy delay
        def delay_node
          xpath('//xmlns:delay',{'xmlns' => EM::Xmpp::Namespaces::Delay}).first
        end
        def stamp
          n = delay_node
          Time.parse read_attr(n, 'stamp') if n
        end
      end

      module Discoveries
        include Iq
        %w{node}.each do |word|
          define_method word do
            n = query_node
            read_attr(n, word) if n
          end
        end
      end

      module Discoinfos
        include Discoveries
        Identity = Struct.new(:name, :category, :type)
        Feature  = Struct.new(:var)
        def query_node
          xpath('//xmlns:query',{'xmlns' => DiscoverInfos}).first
        end
        def identities
          n = query_node
          if n
            n.xpath('xmlns:identity',{'xmlns' => DiscoverInfos}).map do |x|
              cat   = read_attr(x, 'category')
              type  = read_attr(x, 'type')
              name  = read_attr(x, 'name')
              Identity.new name, cat, type
            end
          else 
            []
          end
        end
        def features
          n = query_node
          if n
            n.xpath('xmlns:feature',{'xmlns' => DiscoverInfos}).map do |x|
              var = read_attr(x, 'var')
              Feature.new var
            end
          end
        end
      end

      module Discoitems
        include Discoveries
        Item = Struct.new(:entity, :node, :name)
        def query_node
          xpath('//xmlns:query',{'xmlns' => DiscoverItems}).first
        end
        def item_nodes
          xpath('//xmlns:item',{'xmlns' => DiscoverItems})
        end
        def items
          item_nodes.map do |n| 
            entity = read_attr(n, 'jid'){|x| connection.entity(x)}
            node   = read_attr(n, 'node')
            name   = read_attr(n, 'name')
            Item.new(entity, node, name)
          end
        end
      end

      module Command
        def command_node
          xpath('//xmlns:command',{'xmlns' => Commands}).first
        end

        %w{node sessionid action}.each do |word|
          define_method word do
            n = command_node
            read_attr(n, word) if n
          end
        end

        def previous?
          action == 'prev'
        end
      end

      module Dataforms
        Form  = Struct.new(:type, :fields, :title, :instructions)
        Field = Struct.new(:var, :type, :label, :values, :options) do
          def value
            values.first
          end
        end
        Option = Struct.new(:label, :value)

        def x_form_nodes
          xpath('//xmlns:x',{'xmlns' => Namespaces::DataForms})
        end

        def x_forms
          x_form_nodes.map do |form|
            instruction_node = form.xpath('xmlns:instructions',{'xmlns' => Namespaces::DataForms}).first
            title_node = form.xpath('xmlns:title',{'xmlns' => Namespaces::DataForms}).first

            instr = instruction_node.content if instruction_node
            title = title_node.content if instruction_node

            form_type = read_attr(form, 'type')
            field_nodes = form.xpath('xmlns:field',{'xmlns' => Namespaces::DataForms})
            fields = field_nodes.map do |field|
              var  = read_attr(field, 'var')
              type = read_attr(field, 'type')
              label = read_attr(field, 'label')
              option_nodes = field.xpath('.//xmlns:option',{'xmlns' => Namespaces::DataForms})
              options = option_nodes.map do |opt|
                opt_label = read_attr(opt, 'label')
                opt_value_nodes = opt.xpath('.//xmlns:value',{'xmlns' => Namespaces::DataForms})
                opt_value = opt_value_nodes.map(&:content).first

                Option.new(opt_label, opt_value)
              end
              value_nodes = field.xpath('./xmlns:value',{'xmlns' => Namespaces::DataForms})
              values = value_nodes.map(&:content)

              Field.new(var,type,label,values,options)
            end
            Form.new form_type, fields, title, instr
          end
        end

        def form
          x_forms.first
        end
      end

      module Capabilities
        def c_node
          xpath('//xmlns:c',{'xmlns' => EM::Xmpp::Namespaces::Capabilities}).first
        end

        %w{node ver ext}.each do |word|
          define_method word do
            n = c_node
            read_attr(n, word) if n
          end
        end
      end

      module Roster
        include Contexts::Iq
        def query_node
          xpath('//xmlns:query',{'xmlns' => EM::Xmpp::Namespaces::Roster}).first
        end

        def items
          n = query_node
          if n
            n.children.map do |xml|
              new_subscription(xml)
            end
          end
        end

        private

        Subscription = Struct.new(:type, :jid, :name, :groups)

        def new_subscription(n)
          type = read_attr(n,'subscription')
          jid  = read_attr(n,'jid') {|x| connection.entity x}
          name = read_attr(n,'name')
          groups = n.xpath('xmlns:group', 'xmlns' => EM::Xmpp::Namespaces::Roster).map{|n| n.content}
          Subscription.new(type, jid, name, groups)
        end
      end

      module Tune
        def tune_node
          xpath('//xmlns:tune',{'xmlns' => Namespaces::Tune}).first
        end

        DecimalFields = %w{length rating}.freeze
        StringFields = %w{artist source title track uri}.freeze

        DecimalFields.each do |decimal|
          define_method(decimal) do 
            n = tune_node
            if n
              d = n.children.find{|c| c.name == decimal}
              d.content.to_i if d
            end
          end
        end


        StringFields.each do |str|
          define_method(str) do 
            n = tune_node
            if n
              d = n.children.find{|c| c.name == str}
              d.content
            end
          end
        end

        def tune
          ostruct = OpenStruct.new
          (StringFields + DecimalFields).each do |field|
            val = send field
            ostruct.send("#{field}=", val)
          end
          ostruct
        end
      end

      module Nickname
        def nickname_node
          xpath('//xmlns:nick',{'xmlns' => Nick}).first
        end
        def nickname
          n = nickname_node
          n.content if n
        end
      end

      module Geolocation
        def geoloc_node
          xpath('//xmlns:nick',{'xmlns' => Geoloc}).first
        end

        def geoloc
          ostruct = OpenStruct.newt
          (StringFields + DecimalFields + %w{timestamp}).each do |field|
            val = send field
            ostruct.send("#{field}=", val)
          end
          ostruct
        end

        StringFields = %w{area building country countrycode datum description
        floor locality postalcode region room street text uri}.freeze
        DecimalFields = %w{accuracy error alt lat lon bearing speed}.freeze

        DecimalFields.each do |decimal|
          define_method(decimal) do 
            n = geoloc_node
            if n
              d = n.children.find{|c| c.name == decimal}
              d.content.to_i if d
            end
          end
        end

        StringFields.each do |str|
          define_method(str) do 
            n = geoloc_node
            if n
              d = n.children.find{|c| c.name == str}
              d.content
            end
          end
        end

        def timestamp
          n = geoloc_node
          if n
            d = n.children.find{|c| c.name == 'timestamp'}
            Time.parse d.content if d
          end
        end
      end

      module Useractivity
        def activity_node
          xpath('//xmlns:mood',{'xmlns' => Namespaces::Activity}).first
        end

        def activity_category_node
          n = activity_node
          n.children.first if n
        end

        def activity_text_node
          n = activity_node
          n.children.find{|n| n.name == 'text'} if n
        end

        def activity
          ret = []
          n = activity_category_node
          if n
            ret << n.name 
            detail = n.children.first
            ret << detail.name if detail
          end
          ret
        end

        def activity_text
          n = activity_text_node
          n.content if n
        end
      end

      module Mood
        DefinedMoods = %w{afraid amazed angry amorous annoyed anxious aroused
        ashamed bored brave calm cautious cold confident confused contemplative
        contented cranky crazy creative curious dejected depressed disappointed
        disgusted dismayed distracted embarrassed envious excited flirtatious
        frustrated grumpy guilty happy hopeful hot humbled humiliated hungry hurt
        impressed in_awe in_love indignant interested intoxicated invincible jealous
        lonely lucky mean moody nervous neutral offended outraged playful proud relaxed
        relieved remorseful restless sad sarcastic serious shocked shy sick sleepy
        spontaneous stressed strong surprised thankful thirsty tired undefined weak
        worried}.freeze

        def mood_node
          xpath('//xmlns:mood',{'xmlns' => Namespaces::Mood}).first
        end
        def mood_name_node
          n = mood_node
          n.children.find{|c| DefinedMoods.include?(c.name)} if n
        end
        def mood_text_node
          n = mood_node
          n.children.find{|c| c.name == 'text'}
        end
        def mood
          n = mood_name_node
          n.name if n
        end
        def mood
          n = mood_text_node
          n.content if n
        end
      end

      module Bytestreams
        include Iq
        StreamHost = Struct.new(:host, :port, :jid)
        def query_node
          xpath('//xmlns:query',{'xmlns' => Namespaces::ByteStreams}).first
        end
        def transport_mode
          n = query_node
          read_attr(n,'mode') if n
        end
        def sid
          n = query_node
          read_attr(n,'sid') if n
        end
        def stream_hosts
          n = query_node
          if n
            n.children.select{|c| c.name == 'streamhost'}.map do |c|
              host = read_attr(c,'host')
              port = read_attr(c,'port',:to_i)
              jid  = read_attr(c,'jid')
              StreamHost.new(host, port, jid)
            end
          else
            []
          end
        end
        def used_stream_hosts
          n = query_node
          if n
            n.children.select{|c| c.name == 'streamhost-used'}.map do |c|
              host = read_attr(c,'host')
              port = read_attr(c,'port',:to_i)
              jid  = read_attr(c,'jid')
              StreamHost.new(host, port, jid)
            end
          else
            []
          end
        end
        def support_fast_mode?
          xpath('//xmnls:fast',{'xmlns'=> Namespaces::FastByteStreams}).any?
        end
      end

      module Featurenegotiation
        include Dataforms
        def feature_node
          xpath('//xmlns:feature',{'xmnls' => Namespaces::FeatureNeg})
        end
      end

      module Streaminitiation
        include Iq
        include Featurenegotiation
        def si_node
          xpath('//xmlns:si',{'xmlns' => Namespaces::StreamInitiation}).first
        end
        def file_node
          xpath('//xmlns:file',{'xmlns' => Namespaces::FileTransfer}).first
        end
        def range_node
          xpath('//xmlns:range',{'xmlns' => Namespaces::FileTransfer}).first
        end
        def range_length
          n = range_node
          read_attr(n, 'length') {|x| Integer(x)} if n
        end
        def range_offset
          n = range_node
          read_attr(n, 'offset') {|x| Integer(x)} if n
        end
        def mime_type
          n = si_node
          read_attr(n, 'mime-type') if n
        end
        def profile
          n = si_node
          read_attr(n, 'profile') if n
        end
        def file_name
          n = file_node
          read_attr(n, 'name') if n
        end
        def file_size
          n = file_node
          read_attr(n, 'size') if n
        end
        def file_date
          n = file_node
          read_attr(n, 'date') if n
        end
        def file_md5
          n = file_node
          read_attr(n, 'hash') if n
        end
        def can_do_range?
          n = file_node
          n.children.find{|n| n.name == 'range'} if n
        end
        def description
          n = file_node
          if n
            node = n.children.find{|n| n.name == 'desc'}
            node.content if node
          end
        end
        def stream_methods
          form = x_forms.first
          if form
            field = form.fields.first
            field.values if field
          end
        end
      end

      module Ibb
        include IncomingStanza
        def open_node
          xpath('//xmlns:open',{'xmlns' => Namespaces::IBB}).first
        end
        def data_node
          xpath('//xmlns:data',{'xmlns' => Namespaces::IBB}).first
        end
        def close_node
          xpath('//xmlns:close',{'xmlns' => Namespaces::IBB}).first
        end
        def block_size
          n = open_node
          read_attr(n,'block-size'){|x| Integer(x)} if n
        end
        def sid
          n = open_node || data_node || close_node
          read_attr(n,'sid') if n
        end
        def seq
          n = data_node
          read_attr(n,'seq') if n
        end
        def stanza_type
          n = open_node
          read_attr(n,'stanza') if n
        end
        def data
          n = data_node
          n.content if n
        end
      end

      module PubsubMain
        include IncomingStanza
        Subscription = Struct.new(:jid, :node, :subscription, :sub_id, :expiry)
        Affiliation  = Struct.new(:jid, :node, :affiliation)
        Item         = Struct.new(:node, :item_id, :payload, :publisher)
        Retraction   = Struct.new(:node, :item_id)
        Deletion     = Struct.new(:node, :redirect)
        Configuration= Struct.new(:node, :config)
        Purge        = Struct.new(:node)

        def service
          from.jid
        end
      end

      module Pubsubevent
        include PubsubMain

        def node_id
          ret = nil
          n = event_node
          ret = read_attr(n, 'node') if n
          unless ret
            n = items_node
            ret = read_attr(n, 'node') if n
          end
          ret
        end

        def event_node
          xpath('//xmlns:event',{'xmlns' => EM::Xmpp::Namespaces::PubSubEvent}).first
        end
        def items_node
          n = event_node
          if n
            n.xpath('.//xmlns:items',{'xmlns' => EM::Xmpp::Namespaces::PubSubEvent}).first
          end
        end
        def items
          node = items_node
          if node
            node_id = read_attr(node, 'node')
            node.xpath(".//xmlns:item",{'xmlns' => EM::Xmpp::Namespaces::PubSubEvent}).map do |n|
              item_id = read_attr n, 'id'
              publisher = read_attr n, 'publisher'
              Item.new(node_id, item_id, n.children, publisher)
            end
          else
            []
          end
        end
        def retractions
          node = items_node
          if node
            node_id = read_attr(node, 'node')
            node.xpath(".//xmlns:retract",{'xmlns' => EM::Xmpp::Namespaces::PubSubEvent}).map do |n|
              item_id = read_attr n, 'id'
              Retraction.new(node_id, item_id)
            end
          else
            []
          end
        end

        def purge_node
          n = event_node
          if n
            n.xpath('//xmlns:purge',{'xmlns' => EM::Xmpp::Namespaces::PubSubEvent}).first
          end
        end

        def purge
          node = purge_node
          if node
            node_id = read_attr(node, 'node')
            Purge.new(node_id) if node
          end
        end

        def configuration_node
          n = event_node
          if n
            n.xpath('//xmlns:configuration',{'xmlns' => EM::Xmpp::Namespaces::PubSubEvent}).first
          end
        end

        def configuration
          node = configuration_node
          if node
            node_id = read_attr(node, 'node')
            Configuration.new(node_id, node.children)
          end
        end

        def deletion_node
          n = event_node
          if n
            n.xpath('//xmlns:delete',{'xmlns' => EM::Xmpp::Namespaces::PubSubEvent}).first
          end
        end

        def deletion
          node = deletion_node
          if node
            node_id = read_attr(node, 'node')
            r = node.xpath('//xmlns:redirect',{'xmlns' => EM::Xmpp::Namespaces::PubSubEvent}).first
            uri = read_attr(r, 'uri') if r
            Deletion.new(node_id, uri)
          end
        end
      end

      module Pubsub
        include PubsubMain
        def pubsub_node
          xpath('//xmlns:pubsub',{'xmlns' => EM::Xmpp::Namespaces::PubSub}).first
        end
        def publish_node
          xpath('//xmlns:publish',{'xmlns' => EM::Xmpp::Namespaces::PubSub}).first
        end
        def subscriptions_container_node
          n = pubsub_node
          if n
            n.xpath('//xmlns:subscriptions',{'xmlns' => EM::Xmpp::Namespaces::PubSub}).first
          end
        end
        def subscriptions
          node = subscriptions_container_node || pubsub_node
          if node
            node.xpath('//xmlns:subscription',{'xmlns' => EM::Xmpp::Namespaces::PubSub}).map do |n|
              node_id = read_attr n, 'node'
              jid     = read_attr(n,'jid') {|x| connection.entity x}
              sub     = read_attr(n,'subscription')
              sub_id  = read_attr(n,'subid')
              expiry  = read_attr(n,'expiry'){|x| Date.parse x}
              Subscription.new(jid,node_id,sub,sub_id,expiry)
            end
          else
            []
          end
        end

        def affiliations_container_node
          n = pubsub_node
          if n
            n.xpath('//xmlns:affiliations',{'xmlns' => EM::Xmpp::Namespaces::PubSub}).first
          end
        end
        def affiliations
          node = affiliations_container_node
          if node
            node.xpath('//xmlns:affiliation',{'xmlns' => EM::Xmpp::Namespaces::PubSub}).map do |n|
              node_id = read_attr n, 'node'
              aff     = read_attr(n,'affiliation')
              Affiliation.new(to,node_id,aff)
            end
          else
            []
          end
        end

        def items_container_node
          n = pubsub_node
          if n
            n.xpath('//xmlns:items',{'xmlns' => EM::Xmpp::Namespaces::PubSub}).first
          end
        end

        def items
          node = items_container_node || publish_node
          if node
            item_node = read_attr node, 'node'
            node.xpath('//xmlns:item',{'xmlns' => EM::Xmpp::Namespaces::PubSub}).map do |n|
              item_id = read_attr n, 'id'
              Item.new(item_node,item_id,n.children.first,nil)
            end
          else
            []
          end
        end

        def creation_node
          n = pubsub_node
          if n
            n.xpath('//xmlns:create',{'xmlns' => EM::Xmpp::Namespaces::PubSub}).first
          end
        end

        def created_node
          n = creation_node
          read_attr(n, 'node') if n
        end
      end


      module Pubsubowner
        include PubsubMain
        def pubsub_node
          xpath('//xmlns:pubsub',{'xmlns' => EM::Xmpp::Namespaces::PubSubOwner}).first
        end
        def publish_node
          xpath('//xmlns:publish',{'xmlns' => EM::Xmpp::Namespaces::PubSubOwner}).first
        end
        def subscriptions_container_node
          n = pubsub_node
          if n
            n.xpath('//xmlns:subscriptions',{'xmlns' => EM::Xmpp::Namespaces::PubSubOwner}).first
          end
        end
        def subscriptions
          node = subscriptions_container_node
          node_id = read_attr node, 'node'
          if node
            node.xpath('//xmlns:subscription',{'xmlns' => EM::Xmpp::Namespaces::PubSubOwner}).map do |n|
              jid     = read_attr(n,'jid') {|x| connection.entity x}
              sub     = read_attr(n,'subscription')
              sub_id  = read_attr(n,'subid')
              expiry  = read_attr(n,'expiry'){|x| Date.parse x}
              Subscription.new(jid,node_id,sub,sub_id,expiry)
            end
          else
            []
          end
        end

        def affiliations_container_node
          n = pubsub_node
          if n
            n.xpath('//xmlns:affiliations',{'xmlns' => EM::Xmpp::Namespaces::PubSubOwner}).first
          end
        end
        def affiliations
          node = affiliations_container_node
          if node
            node_id = read_attr(node, 'node')
            node.xpath('//xmlns:affiliation',{'xmlns' => EM::Xmpp::Namespaces::PubSubOwner}).map do |n|
              jid = read_attr(n, 'jid') {|x| connection.entity x}
              aff = read_attr(n,'affiliation')
              Affiliation.new(jid,node_id,aff)
            end
          else
            []
          end
        end
      end

      module Mucuser
        def x_node
          xpath('//xmlns:x',{'xmlns' => EM::Xmpp::Namespaces::MucUser}).first
        end

        def item_node
          xpath('//xmlns:item',{'xmlns' => EM::Xmpp::Namespaces::MucUser}).first
        end

        def status_node
          xpath('//xmlns:status',{'xmlns' => EM::Xmpp::Namespaces::MucUser}).first
        end

        def status
          n = status_node
          read_attr(n, 'code') if n
        end

        def jid
          n = item_node
          jid_str = read_attr(n, 'jid') if n
          connection.entity jid_str if jid_str
        end

        def affiliation
          n = item_node
          read_attr(n, 'affiliation') if n
        end

        def role
          n = item_node
          read_attr(n, 'role') if n
        end
      end
    end

    class Bit
      include Namespaces
      attr_reader :ctx

      def initialize(ctx)
        @ctx = ctx
      end

      def connection
        ctx.connection
      end

      def stanza
        ctx.stanza
      end

      def read_attr(*args,&blk)
        ctx.read_attr(*args,&blk)
      end

      def xpath(*args)
        ctx.xpath(*args)
      end

      def xpath?(*args)
        ctx.xpath(*args)
      end
    end

    module Bits
      class Stanza < Bit
        include Contexts::IncomingStanza
      end
      class Error < Bit
        include Contexts::Error
      end
      class Presence < Bit
        include Contexts::Presence
      end
      class Message < Bit
        include Contexts::Message
      end
      class Iq < Bit
        include Contexts::Iq
      end
      class Delay < Bit
        include Contexts::Delay
      end
      class Discoinfos < Bit
        include Contexts::Discoinfos
      end
      class Discoitems < Bit
        include Contexts::Discoitems
      end
      class Command < Bit
        include Contexts::Command
      end
      class Dataforms < Bit
        include Contexts::Dataforms
      end
      class Capabilities < Bit
        include Contexts::Capabilities
      end
      class Roster < Bit
        include Contexts::Roster
      end
      class Tune < Bit
        include Contexts::Tune
      end
      class Nickname < Bit
        include Contexts::Nickname
      end
      class Geolocation < Bit
        include Contexts::Geolocation
      end
      class Useractivity < Bit
        include Contexts::Useractivity
      end
      class Mood < Bit
        include Contexts::Mood
      end
      class Bytestreams < Bit
        include Contexts::Bytestreams
      end
      class Streaminitiation < Bit
        include Contexts::Streaminitiation
      end
      class Ibb < Bit
        include Contexts::Ibb
      end
      class Pubsub < Bit
        include Contexts::Pubsub
      end
      class Pubsubowner < Bit
        include Contexts::Pubsubowner
      end
      class Pubsubevent < Bit
        include Contexts::Pubsubevent
      end
      class Mucuser < Bit
        include Contexts::Mucuser
      end
    end

  end
end
