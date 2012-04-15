
require 'em-xmpp/namespaces'
require 'em-xmpp/connector'
require 'em-xmpp/handler'
require 'em-xmpp/jid'
require 'em-xmpp/cert_store'
require 'eventmachine'
require 'base64'
require 'digest/md5'

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
      send_raw presence_stanza()
      ready
    end

    def negotiation_failed(node)
      raise RuntimeError, "could not negotiate a stream:\n#{node}"
    end

    def request_subscription(to)
      send_raw(presence_stanza('to' => to, 'type'=> 'subscribe'))
    end

    def get_roster
      send_raw(iq_stanza('from' => @jid.full) do
        query('xmlns' => 'jabber:iq:roster')
      end)
    end

    def send_message(to, body='')
      send_raw(message_stanza('to' => to) do
        body(body)
      end)
    end

    #should add 'xml:lang'

    def default_presence_config
      {}
    end

    def default_message_config
      {'to' => @jid.domain, 'id' => "em-xmpp.#{rand(65535)}"}
    end

    def default_iq_config
      {'type' => 'get', 'id' => "em-xmpp.#{rand(65535)}"}
    end

    def presence_stanza(cfg={}, &blk)
      cfg = default_presence_config.merge(cfg)
      build_xml do
        presence(cfg, &blk)
      end
    end

    def message_stanza(cfg={}, &blk)
      cfg = default_message_config.merge(cfg)
      build_xml do
        message(cfg, &blk)
      end
    end

    def iq_stanza(cfg={}, &blk)
      cfg = default_iq_config.merge(cfg)
      build_xml do
        iq(cfg, &blk)
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
