
require 'em-xmpp/namespaces'
require 'em-xmpp/connector'
require 'em-xmpp/handler'
require 'em-xmpp/jid'
require 'em-xmpp/entity'
require 'em-xmpp/cert_store'
require 'em-xmpp/component'
require 'em-xmpp/xml_builder'
require 'eventmachine'
require 'fiber'
require 'socket'
require 'openssl'

module EM::Xmpp
  module Evented
    include XmlBuilder
    def component?
      @component
    end

    def jid_received(jid)
      @jid = entity jid
    end

    def entity(jid)
      Entity.new(self, jid)
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

    def ready
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
  end

  module NonEM
    class Connection
      include Namespaces
      include Connector
      include Evented

      attr_reader :jid, :pass, :user_data

      def initialize(jid, pass, mod=nil, cfg={})
        @jid        = jid
        @component  = jid.node.nil?
        self.extend Component if component?
        @pass       = pass.dup.freeze
        self.extend mod if mod
        certdir     = cfg[:certificates]
        @user_data  = cfg[:data]
        @certstore  = if certdir
                        CertStore.new(certdir)
                      else
                        nil
                      end
        @ssl        = nil
      end

      def self.start(jid, pass=nil, mod=nil, cfg={}, server=nil, port=5222, &blk)
        jid = JID.parse jid
        if server.nil?
          record = Resolver.resolve jid.domain
          if record
            server = record.target.to_s
            port   = record.port
          else
            server = jid.domain
          end
        end
        obj = self.new(jid,pass,mod,cfg)
        obj.start(server,port)
        obj
      end

      def start(server,port)
        @skt = TCPSocket.open(server,port)
      end

      ChunkSize = 1450

      def event_loop
        prepare_parser!
        set_negotiation_handler!
        catch :stop do
          loop do
            tick=5
            ok = IO.select([@skt], nil, nil, tick)
            if ok
              if @ssl
                dat = @ssl.sysread(ChunkSize)
                puts "<< in\n#{dat}\n" if $DEBUG
                receive_raw(dat)
              else
                dat = @skt.recv(ChunkSize)
                puts "<< in\n#{dat}\n" if $DEBUG
                receive_raw(dat)
              end
            end
          end
        end
      end

      def send_raw(dat)
        puts ">> out\n#{dat}\n" if $DEBUG
        if @ssl
          @ssl.syswrite dat
        else
          @skt << dat if @skt
        end
      end

      def initiate_tls
        @ssl = OpenSSL::SSL::SSLSocket.new(@skt).connect
      end
    end
  end

  class Connection < EM::Connection
    include Namespaces
    include Connector
    include Evented

    attr_reader :jid, :pass, :user_data

    def self.start(jid, pass=nil, mod=nil, cfg={}, server=nil, port=5222, &blk)
      jid = JID.parse jid
      if server.nil?
        record = Resolver.resolve jid.domain
        if record
          server = record.target.to_s
          port   = record.port
        else
          server = jid.domain
        end
      end

      EM.connect(server, port, self, jid, pass, mod, cfg, &blk)
    end


    def initialize(jid, pass, mod=nil, cfg={})
      @jid        = jid
      @component  = jid.node.nil?
      self.extend Component if component?
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
      prepare_parser!
      set_negotiation_handler!
    end

    def send_raw(data)
      puts ">> out\n#{data}\n" if $DEBUG
      send_data data
    end

    def receive_data(dat)
      puts "<< in\n#{dat}\n" if $DEBUG
      receive_raw(dat)
    end

    def unbind
      puts "**** unbound ****" if $DEBUG
    end

    def initiate_tls
      bool = !! @certstore
      start_tls(:verify_peer => bool)
    end
  end
end
