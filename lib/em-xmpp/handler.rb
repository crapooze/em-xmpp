
require 'em-xmpp/namespaces'
require 'em-xmpp/context'
require 'base64'
require 'sasl/base'
require 'sasl'

module EM::Xmpp
  class Handler
    include Namespaces

    Xpath = Struct.new(:path, :args, :blk) do
      def match?(xml)
        path == :anything or xml.xpath(path, args).any?
      end
    end

    def initialize(conn)
      @connection         = conn
      @xpaths             = []
      @exception_xpaths   = []

      stack_decorators
    end

    def on_presence(&blk)
      on('//xmlns:presence', 'xmlns' => EM::Xmpp::Namespaces::Client, &blk)
    end

    def on_message(&blk)
      on('//xmlns:message', 'xmlns' => EM::Xmpp::Namespaces::Client, &blk)
    end

    def on_iq(&blk)
      on('//xmlns:iq', 'xmlns' => EM::Xmpp::Namespaces::Client, &blk)
    end

    def stack_decorators
      on_presence { |ctx| ctx.with(:presence) }
      on_message  { |ctx| ctx.with(:message) }
      on_iq       { |ctx| ctx.with(:iq) }
      on('//xmlns:delay', 'xmlns' => Delay) do |ctx|
        ctx.with(:delay)
      end
      on('//xmlns:query', 'xmlns' => DiscoverInfos) do |ctx|
        ctx.with(:discoinfos)
      end
      on('//xmlns:query', 'xmlns' => DiscoverItems) do |ctx|
        ctx.with(:discoitems)
      end
      on('//xmlns:command', 'xmlns' => Commands) do |ctx|
        ctx.with(:command)
      end
      on('//xmlns:x', 'xmlns' => DataForms) do |ctx|
        ctx.with(:dataforms)
      end
    end

    def on(path, args={}, &blk)
      @xpaths << Xpath.new(path, args, blk)
    end

    def on_exception(path, args={}, &blk)
      @exception_xpaths << Xpath.new(path, args, blk)
    end

    # wraps the stanza in a context and calls handle_context
    def handle(stanza)
      handle_context Context.new(@connection, stanza)
    end

    # runs all xpath_handlers against the stanza context
    # catches all exception (in which case, the context gets passed to all
    # exception_xpaths)
    #
    # an xpath handler can:
    # - throw :halt to shortcircuit everything
    # - set the context to "done!" to avoid invoking handlers
    # - delete_xpath_handler from the history, this is useful in one-time
    # handlers such as request/responses
    def handle_context(ctx)
      catch :halt do
        @xpaths = run_xpath_handlers ctx, @xpaths
      end
    rescue => err
      ctx.env['error'] = err
      @exception_xpaths = run_xpath_handlers ctx, @exception_xpaths
    end

    # runs all handlers and returns a list of handlers for the next stanza
    def run_xpath_handlers(ctx, handlers)
      handlers.map do |x|
        if (not ctx.done?) and (x.match?(ctx.stanza))
          ctx.env['xpath.handler'] = x
          ctx = x.blk.call(ctx)
          raise RuntimeError, "xpath handlers should return a Context" unless ctx.is_a?(Context)

          x if ctx.reuse_handler?
        else
          x
        end
      end.compact
    end
  end

  class XmppSASL < ::SASL::Preferences
    attr_accessor :handler
    def initialize(handler)
      @handler = handler
    end
    def realm
      handler.jid.domain
    end
    def digest_uri
      'xmpp/' + handler.jid.domain
    end
    def username
      handler.jid.node
    end
    def has_password?
      true
    end
    def password
      ret = handler.pass
    end
  end

  class Routine < Handler
  end

  class StreamNegotiation < Handler
    attr_reader :sasl

    def initialize(conn)
      super conn
      @sasl   = nil
      setup_handlers
    end

    def c
      @connection
    end

    def jid
      @connection.jid
    end

    def pass
      @connection.pass
    end

    def setup_handlers
      on('//xmlns:starttls', {'xmlns' => TLS}) do |ctx|
        @connection.ask_for_tls 
        ctx.delete_xpath_handler!.done!
      end

      on('//xmlns:proceed', {'xmlns' => TLS }) do |ctx|
        @connection.start_using_tls_and_reset_stream
        ctx.delete_xpath_handler!.done!
      end

      on('//xmlns:mechanisms', {'xmlns' => SASL}) do |ctx|
        search = ctx.xpath('//xmlns:mechanisms', {'xmlns' => SASL})
        if search.first
          mechanisms = search.first.children.map(&:content)
          start_sasl mechanisms
          ctx.delete_xpath_handler!.done!
        else
          raise RuntimeError, "how come there is no mechanism node?"
        end
      end

      on('//xmlns:challenge', {'xmlns' => SASL}) do |ctx|
        sasl_step ctx.stanza
        ctx.done!
      end

      on('//xmlns:success', {'xmlns' => SASL}) do |ctx|
        @connection.restart_xml_stream
        ctx.delete_xpath_handler!.done!
      end

      on('//xmlns:bind', {'xmlns' => Bind}) do |ctx|
        bind_to_resource  
        ctx.delete_xpath_handler!.done!
      end

      on('//xmlns:bind', {'xmlns' => Bind}) do |ctx|
        jid  = extract_jid ctx.stanza

        if jid
          @connection.jid_received jid 
          start_session
        else
          raise RuntimeError, "no jid despite binding"
        end

        ctx.delete_xpath_handler!.done!
      end

      on('//xmlns:session', {'xmlns' => Session}) do |ctx|
        @connection.negotiation_finished
        ctx.delete_xpath_handler!.done!
      end

      on('//xmlns:failure', {'xmlns' => SASL}) do |ctx|
        @connection.negotiation_failed(ctx.stanza)
        ctx.done!
      end

      on(:anything) do |ctx|
        @connection.unhandled ctx.stanza
      end
    end

    def extract_jid(stanza)
      jid = stanza.xpath('//bind:jid', {'bind' => Bind})
      jid.text if jid.any?
    end

    def bind_to_resource(wanted_res=nil)
      c.send_raw(c.iq_stanza('type' => 'set') do |x|
        x.bind('xmlns' => Bind) do |y|
          y.resource(wanted_res) if wanted_res
        end
      end)
    end

    def start_session
      c.send_raw(c.iq_stanza('type' => 'set', 'to' => jid.domain) do |x|
        x.session('xmlns' => Session) 
      end)
    end

    def start_sasl(methods)
      @sasl = ::SASL.new(methods, XmppSASL.new(self))
      msg,val = sasl.start
      mech = sasl.mechanism
      reply_sasl(msg,val,mech)
    end

    def sasl_step(stanza)
      msg       = stanza.name
      inStr     = Base64.strict_decode64(stanza.text)
      meth,str  = sasl.receive msg, inStr
      b64       = str ? Base64.strict_encode64(str) : ''
      reply_sasl(meth, b64)
    end

    def reply_sasl(msg, val=nil, mech=nil)
      c.send_xml do |x|
        if val
          x.send(msg, val, {'xmlns' => SASL, 'mechanism' => mech})
        else
          x.send(msg,  {'xmlns' => SASL, 'mechanism' => mech})
        end
      end
    end

  end
end
