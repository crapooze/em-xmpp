
require 'em-xmpp'
require 'em-xmpp/namespaces'
require 'em-xmpp/evented'
require 'em-xmpp/jid'
require 'em-xmpp/component'
require 'em-xmpp/resolver'

require 'socket'
require 'openssl'

module EM::Xmpp
  module NonEM
    class Connection
      include Namespaces
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

end
