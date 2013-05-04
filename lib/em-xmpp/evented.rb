
require 'em-xmpp/namespaces'
require 'em-xmpp/entity'
require 'em-xmpp/handler'
require 'em-xmpp/xml_builder'
require 'em-xmpp/xml_parser'
require 'em-xmpp/cert_store'
require 'fiber'

module EM::Xmpp
  module Evented
    include Namespaces
    include XmlBuilder
    include XmlParser
    def component?
      @component
    end

    def jid_received(jid)
      @jid = entity jid
    end

    def entity(jid)
      Entity.new(self, jid)
    end

    def default_presence_params
      {}
    end

    def default_message_params
      {'to' => @jid.domain, 'id' => "em-xmpp.#{rand(65535)}"}
    end

    def default_iq_params
      {'type' => 'get', 'id' => "em-xmpp.#{rand(65535)}"}
    end

    def presence_stanza(*args,&blk)
      OutgoingStanza.new('presence', default_presence_params, *args,&blk)
    end

    def message_stanza(*args,&blk)
      OutgoingStanza.new('message',default_message_params,*args,&blk)
    end

    def iq_stanza(*args,&blk)
      OutgoingStanza.new('iq', default_iq_params, *args,&blk)
    end

    def send_stanza(stanza)
      send_raw stanza.xml
      if block_given?
        upon(:anything) do |ctx|
          if ctx.bit(:stanza).id == stanza.params['id']
            yield ctx
            ctx.delete_xpath_handler!
          else
            ctx
          end
        end
      end
    end

    %w{upon on on_exception on_presence on_iq on_message on_decorator on_iq_decorator on_presence_decorator on_message_decorator}.each do |meth|
      define_method(meth) do |*args,&blk|
      @handler.send meth, *args, &blk
      end
    end


    # XML (stanzas) stream

    def ready
    end

    def stream_start(node)
    end

    def stanza_start(node)
    end

    def stanza_end(node)
      Fiber.new { @handler.handle(node) }.resume
    end

    def unhandled_stanza(node)
      raise RuntimeError, "did not handle node:\n#{node}"
    end

    def ssl_verify_peer(pem)
      @certstore.trusted?(pem).tap do |trusted|
        close_connection unless trusted
      end    
    end

    def receive_raw(dat)
      @xml_parser << dat
    end

    def prepare_parser!
      @xml_parser   = ForwardingParser.new self
      @stack        = []
      @stanza       = nil
      @streamdoc    = nil

      open_xml_stream
    end

    def restart_xml_stream
      #make sure we stop receiving methods from the old parser
      @xml_parser.document.recipient = nil 
      prepare_parser!
    end

    def send_xml(*args)
      send_raw build_xml(*args)
    end

    def set_negotiation_handler!
      @handler = StreamNegotiation.new self
    end

    def negotiation_finished
      @pass    = nil
      @handler = Routine.new self
      send_stanza presence_stanza() unless component?
      framework_ready if respond_to? :framework_ready
      ready
    end

    def negotiation_failed(node)
      raise RuntimeError, "could not negotiate a stream:\n#{node}"
    end

    private

    def open_xml_stream_tag
      domain  = @jid.domain
      version = '1.0'
      lang    = 'en'
      start_stream = <<-STREAM 
                    <stream:stream
                    to='#{domain}'
                    version='#{version}'
                    xml:lang='#{lang}'
                    xmlns='#{Client}'
                    xmlns:stream='#{Stream}'
                    >
      STREAM
    end

    def close_xml_stream_tag
      '</stream:stream>'
    end

    def open_xml_stream
      send_raw open_xml_stream_tag
    end

    def close_xml_stream
      send_raw close_xml_stream_tag
    end

    public

    ### TLS World

    def ask_for_tls
      send_xml('starttls', :xmlns => TLS)
    end

    def start_using_tls_and_reset_stream
      initiate_tls
      restart_xml_stream
    end

    def initiate_tls
      raise NotImplementedError
    end

  end
end
