
require 'em-xmpp/namespaces'
require 'em-xmpp/connector'
require 'em-xmpp/handler'
require 'em-xmpp/jid'
require 'em-xmpp/entity'
require 'em-xmpp/cert_store'
require 'eventmachine'
require 'fiber'

module EM::Xmpp
  class Connection < EM::Connection
    include Namespaces
    include Connector

    attr_reader :jid, :pass, :user_data

    def initialize(jid, pass, mod=nil, cfg={})
      @jid        = jid
      @pass       = pass.dup.freeze
      self.extend mod if mod
      certdir     = cfg[:certificates]
      @user_data  = cfg[:data]
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
      Fiber.new { @handler.handle(node) }.resume
    end

    def unhandled_stanza(node)
      raise RuntimeError, "did not handle node:\n#{node}"
    end

    def jid_received(jid)
      @jid = entity jid
    end

    def entity(jid)
      Entity.new(self, jid)
    end

    def negotiation_finished
      @pass    = nil
      @handler = Routine.new self
      send_stanza presence_stanza()
      framework_ready if respond_to? :framework_ready
      ready
    end

    def negotiation_failed(node)
      raise RuntimeError, "could not negotiate a stream:\n#{node}"
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

    def presence_stanza(*args)
      OutgoingStanza.new('presence', default_presence_params, *args)
    end

    def message_stanza(*args)
      OutgoingStanza.new('message',default_message_params,*args)
    end

    def iq_stanza(*args)
      OutgoingStanza.new('iq', default_iq_params, *args)
    end

    def send_stanza(stanza)
      send_raw stanza.xml
      if block_given?
        upon(:anything) do |ctx|
          if ctx.bit!(:stanza).id == stanza.params['id']
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
