
require 'em-xmpp/namespaces'
require 'em-xmpp/connector'
require 'em-xmpp/handler'
require 'em-xmpp/jid'
require 'em-xmpp/cert_store'
require 'eventmachine'

module EM::Xmpp
  class Connection < EM::Connection
    include Namespaces
    include Connector

    attr_reader :jid, :pass

    def initialize(jid, pass, mod=nil, cfg={})
      @jid        = jid
      @pass       = pass.dup.freeze
      self.extend mod if mod
      certdir     = cfg[:certificates]
      @certstore  = if certdir
                      CertStore.new(certdir)
                    else
                      nil
                    end
    end

    def post_init
      super
      @handler = StreamNegotiation.new self
    end

    def stanza_start(node)
    end

    def stanza_end(node)
      @handler.handle(node)
    end

    def unhandled_stanza(node)
      raise RuntimeError, "did not handle node:\n#{node}"
    end

    def jid_received(jid)
      @jid = JID.parse jid
    end

    def negotiation_finished
      @pass    = nil
      @handler = Routine.new self
      send_stanza presence_stanza()
      ready
    end

    def negotiation_failed(node)
      raise RuntimeError, "could not negotiate a stream:\n#{node}"
    end

    OutgoingStanza = Struct.new(:xml, :params)

    def default_presence_params
      {}
    end

    def default_message_params
      {'to' => @jid.domain, 'id' => "em-xmpp.#{rand(65535)}"}
    end

    def default_iq_params
      {'type' => 'get', 'id' => "em-xmpp.#{rand(65535)}"}
    end

    def presence_stanza(params={}, &blk)
      params = default_presence_params.merge(params)
      xml = build_xml do |x|
        x.presence(params, &blk)
      end
      OutgoingStanza.new xml, params
    end

    def message_stanza(params={}, &blk)
      params = default_message_params.merge(params)
      xml = build_xml do |x|
        x.message(params, &blk)
      end
      OutgoingStanza.new xml, params
    end

    def iq_stanza(params={}, &blk)
      params = default_iq_params.merge(params)
      xml = build_xml do |x|
        x.iq(params, &blk)
      end
      OutgoingStanza.new xml, params
    end

    def send_stanza(stanza)
      send_raw stanza.xml
      if block_given?
        on(:anything) do |ctx|
          if ctx.id == stanza.params['id']
            yield ctx
            ctx.delete_xpath_handler!
          else
            ctx
          end
        end
      end
    end

    %w{on on_exception on_presence on_iq on_message}.each do |meth|
      define_method(meth) do |*args,&blk|
        @handler.send meth, *args, &blk
      end
    end

    def ready
    end

    def start_using_tls_and_reset_stream
      bool = !! @certstore
      start_tls(:verify_peer => bool)
      restart_xml_stream
    end

    def ssl_verify_peer(pem)
      @certstore.trusted?(pem).tap do |trusted|
        close_connection unless trusted
      end    
    end

  end
end
