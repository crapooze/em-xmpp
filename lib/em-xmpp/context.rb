
require 'em-xmpp/jid'
require 'em-xmpp/namespaces'
require 'time'
require 'ostruct'

module EM::Xmpp
  class Context
    attr_reader :connection, :stanza, :env

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
      mod = if modname.is_a?(Module)
              modname
            else
              self.class.const_get(modname.to_s.capitalize)
            end
      env['modules'] << mod
      obj = self
      obj.extend mod
      obj
    end

    module IncomingStanza
      include Namespaces
      %w{type id lang}.each do |w|
        define_method w do
          read_attr stanza, w
        end
      end
      def to
        read_attr(stanza, 'to'){|j| JID.parse(j)}
      end
      def from
        read_attr(stanza, 'from'){|j| JID.parse(j)}
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
        jid = @connection.jid.full
        {'from' => jid, 'to' => from, 'id' => id}
      end
      def reply(args={},&blk)
        args = reply_default_params.merge args
        @connection.presence_stanza(args,&blk)
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
        @connection.message_stanza(args,&blk)
      end

      def groupchat?
        type == 'groupchat'
      end
    end

    module Iq
      include IncomingStanza
      def reply_default_params
        jid = @connection.jid.full
        {'from' => jid, 'to' => from, 'type' => 'result', 'id' => id}
      end

      def reply(args={},&blk)
        args = reply_default_params.merge args
        @connection.iq_stanza(args,&blk)
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
      def query_node
        xpath('//xmlns:query',{'xmlns' => DiscoverInfos}).first
      end
    end

    module Discoitems
      include Discoveries
      def query_node
        xpath('//xmlns:query',{'xmlns' => DiscoverItems}).first
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
      def x_node
        xpath('//xmlns:x',{'xmlns' => DataForms}).first
      end

      def x_type
        n = x_node
        read_attr(n, 'type') if n
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
        jid  = read_attr(n,'jid') {|x| JID.parse x}
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
        JID.parse jid_str if jid_str
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
end
