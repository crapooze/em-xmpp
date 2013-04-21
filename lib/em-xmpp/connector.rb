
require 'eventmachine'
require 'em-xmpp/context'
require 'em-xmpp/namespaces'
require 'em-xmpp/resolver'
require 'em-xmpp/xml_parser'
require 'em-xmpp/xml_builder'

module EM::Xmpp
  module Connector
    include Namespaces
    include XmlParser
    include XmlBuilder

    def self.included(obj)
      obj.extend ClassMethods
    end

    module ClassMethods
      def start(jid, pass=nil, mod=nil, cfg={}, server=nil, port=5222, &blk)
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
    end

    extend ClassMethods

    def send_raw(data)
      puts ">> out\n#{data}\n" if $DEBUG
      send_data data
    end

    def send_xml(*args)
      send_raw build_xml(*args)
    end

    def unbind
      puts "**** unbound ****" if $DEBUG
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

    ### XMPP World

    def stream_start(node)
    end

    def stanza_start(node)
      raise NotImplementedError
    end

    def stanza_end(node)
      raise NotImplementedError
    end

    public

    ### TLS World

    def ask_for_tls
     send_xml('starttls', :xmlns => TLS)
    end

    def start_using_tls_and_reset_stream
      start_tls(:verify_peer => false)
      restart_xml_stream
    end

    def ssl_verify_peer(pem)
      raise NotImplementedError
    end
  end
end
