
require 'em-xmpp/namespaces'
require 'em-xmpp/context'
require 'em-xmpp/stanza_matcher'
require 'em-xmpp/stanza_handler'
require 'em-xmpp/xml_builder'
require 'base64'
require 'sasl/base'
require 'sasl'

module EM::Xmpp
  class Handler
    include Namespaces
		include XmlBuilder

    def initialize(conn)
      @connection         = conn
      @handlers           = []
      @decorator_handlers = []
      @exception_handlers = []
    end

    # wraps the stanza in a context and calls handle_context
    def handle(stanza)
      handle_context Context.new(@connection, stanza)
    end

    def enable_default_stack_decorators!
      on_presence_decorator do |ctx| 
        presence = ctx.bit(:presence) 
        ctx.bit(:error) if presence.error?
        ctx
      end
      on_message_decorator  do |ctx| 
        msg = ctx.bit(:message) 
        ctx.bit(:error) if msg.error?
        ctx
      end
      on_iq_decorator       do |ctx| 
        iq = ctx.bit(:iq) 
        ctx.bit(:error) if iq.error?
        ctx
      end
      on_decorator('//xmlns:pubsub', 'xmlns' => PubSub) do |ctx|
        ctx.bit(:pubsub)
        ctx
      end
      on_decorator('//xmlns:event', 'xmlns' => PubSubEvent) do |ctx|
        ctx.bit(:pubsubevent)
        ctx
      end
      on_decorator('//xmlns:delay', 'xmlns' => Delay) do |ctx|
        ctx.bit(:delay)
        ctx
      end
      on_decorator('//xmlns:query', 'xmlns' => DiscoverInfos) do |ctx|
        ctx.bit(:discoinfos)
        ctx
      end
      on_decorator('//xmlns:query', 'xmlns' => DiscoverItems) do |ctx|
        ctx.bit(:discoitems)
        ctx
      end
      on_decorator('//xmlns:query', 'xmlns' => Roster) do |ctx|
        ctx.bit(:roster)
        ctx
      end
      on_decorator('//xmlns:command', 'xmlns' => Commands) do |ctx|
        ctx.bit(:command)
        ctx
      end
      on_decorator('//xmlns:data', 'xmlns' => BoB) do |ctx|
        ctx.bit(:bob)
        ctx
      end
      on_decorator('//xmlns:x', 'xmlns' => DataForms) do |ctx|
        ctx.bit(:dataforms)
        ctx
      end
      on_decorator('//xmlns:nick', 'xmlns' => Nick) do |ctx|
        ctx.bit(:nickname)
        ctx
      end
      on_decorator('//xmlns:x', 'xmlns' => MucUser) do |ctx|
        ctx.bit(:mucuser)
        ctx
      end
      on_decorator('//xmlns:si', 'xmlns' => StreamInitiation) do |ctx|
        ctx.bit(:streaminitiation)
        ctx
      end
      on_decorator('//xmlns:open | //xmlns:data | //xmlns:close', 'xmlns' => IBB) do |ctx|
        ctx.bit(:ibb)
        ctx
      end
      on_decorator('//xmlns:query', 'xmlns' => ByteStreams) do |ctx|
        ctx.bit(:bytestreams)
        ctx
      end
    end

    private

    def add_decorator_handler(handler)
      @decorator_handlers << handler
    end

    def add_handler(handler)
      @handlers << handler
    end

    def add_handler_before_the_other_handlers(handler)
      @handlers.unshift handler
    end

    def add_exception_handler(handler)
      @exception_handlers << handler
    end

    def remove_decorator_handler(handler)
      @decorator_handlers.delete handler
    end

    def remove_handler(handler)
      @handlers.delete handler
    end

    def remove_exception_handler(handler)
      @exception_handlers.delete handler
    end

    def handler_for(path,args,&blk)
      matcher = StanzaMatcher.new(path, args)
      handler = StanzaHandler.new(matcher, blk)
    end

    public

    def on_presence(&blk)
      on('//xmlns:presence', 'xmlns' => EM::Xmpp::Namespaces::Client, &blk)
    end

    def on_message(&blk)
      on('//xmlns:message', 'xmlns' => EM::Xmpp::Namespaces::Client, &blk)
    end

    def on_iq(&blk)
      on('//xmlns:iq', 'xmlns' => EM::Xmpp::Namespaces::Client, &blk)
    end

    def on_presence_decorator(&blk)
      on_decorator('//xmlns:presence', 'xmlns' => EM::Xmpp::Namespaces::Client, &blk)
    end

    def on_message_decorator(&blk)
      on_decorator('//xmlns:message', 'xmlns' => EM::Xmpp::Namespaces::Client, &blk)
    end

    def on_iq_decorator(&blk)
      on_decorator('//xmlns:iq', 'xmlns' => EM::Xmpp::Namespaces::Client, &blk)
    end

    def on_decorator(path, args={}, &blk)
      handler = handler_for path, args, &blk
      add_decorator_handler handler
      handler
    end

    def upon(path, args={}, &blk)
      handler = handler_for path, args, &blk
      add_handler_before_the_other_handlers handler
      handler
    end

    def on(path, args={}, &blk)
      handler = handler_for path, args, &blk
      add_handler handler
      handler
    end

    def on_exception(path, args={}, &blk)
      handler = handler_for path, args, &blk
      add_exception_handler handler
      handler
    end

    private

    # runs all decorator_handlers against the stanza context so that the context has all needed methods
    # runs all handlers against the stanza context
    # catches all exception (in which case, the context gets passed to all
    # exception_handlers)
    #
    # an xpath handler can:
    # - throw :halt to shortcircuit everything
    # - set the context to "done!" to avoid invoking handlers
    # - delete_xpath_handler from the history, this is useful in one-time
    # handlers such as request/responses
    def handle_context(ctx)
      catch :halt do
        run_xpath_handlers ctx, @decorator_handlers.dup, :remove_decorator_handler
        run_xpath_handlers ctx, @handlers.dup, :remove_handler
      end
    rescue => err
      ctx['error'] = err
      run_xpath_handlers ctx, @exception_handlers.dup, :remove_exception_handler
    end

    # runs all handlers, calls the remover method if a handler should be removed
    def run_xpath_handlers(ctx, handlers, remover)
      handlers.each do |h|
        if (not ctx.done?) and (h.match?(ctx.stanza))
          ctx['xpath.handler'] = h
          ctx = h.call(ctx)
          raise RuntimeError, "xpath handlers should return a Context" unless ctx.is_a?(Context)
          send remover, h unless ctx.reuse_handler?
        end
      end
    end
  end

  class XmppSASL < ::SASL::Preferences
    attr_accessor :handler, :authzid
    def initialize(handler)
      @handler = handler
      @authzid = handler.jid.bare.to_s
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
    def allow_plaintext?
      true
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
      on_exception(:anything) do |ctx|
        raise ctx['error']
      end

      if @connection.component?
        on('//xmlns:handshake', {}) do |ctx|
          @connection.negotiation_finished
          ctx.delete_xpath_handler!.done!
        end

      else
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

      end

      on(:anything) do |ctx|
        @connection.unhandled_stanza ctx.stanza
      end
    end

    private

    def extract_jid(stanza)
      jid = stanza.xpath('//bind:jid', {'bind' => Bind})
      jid.text if jid.any?
    end

    def bind_to_resource(wanted_res=nil)
      c.send_stanza(c.iq_stanza({'type' => 'set'},
					x('bind',{'xmlns' => Bind},
            x_if(wanted_res,'resource',wanted_res)
					)
				)
			)
    end

    def start_session
      session_request = c.iq_stanza({'type' => 'set', 'to' => jid.domain}, x('session','xmlns' => Session))

      c.send_stanza(session_request) do |ctx|
        if ctx.bit(:stanza).type == 'result'
          @connection.negotiation_finished
          ctx.delete_xpath_handler!.done!
        else
          @connection.negotiation_failed(ctx)
        end
      end
    end

    def start_sasl(methods)
      @sasl = ::SASL.new(methods, XmppSASL.new(self))
      msg,val = sasl.start
      mech = sasl.mechanism
      @sasl.preferences.authzid = nil if mech == "DIGEST-MD5"
      val       =  Base64.strict_encode64(val) if val 
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
      c.send_xml(msg,  val, 'xmlns' => SASL, 'mechanism' => mech)
    end

  end
end
