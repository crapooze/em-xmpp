
require 'eventmachine'

require 'em-xmpp/namespaces'
require 'em-xmpp/evented'
require 'em-xmpp/jid'
require 'em-xmpp/component'
require 'em-xmpp/resolver'


module EM::Xmpp
  class Connection < EM::Connection
    include Namespaces
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
