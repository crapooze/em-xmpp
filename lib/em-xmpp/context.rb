
require 'em-xmpp/jid'
require 'em-xmpp/namespaces'
require 'time'

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

    module Stanza
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
    end

    module Presence
      include Stanza
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
    end

    module Message
      include Stanza
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
    end

    module Iq
      include Stanza
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
  end
end
