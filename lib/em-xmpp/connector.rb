
require 'eventmachine'
require 'em-xmpp/context'
require 'em-xmpp/namespaces'
require 'em-xmpp/resolver'
require 'em-xmpp/xml_parser'

module EM::Xmpp
  module Connector
    include Namespaces
    include XmlParser

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
      @xml_parser.document.recipient = nil #make sure we stop receiving methods from the old parser
      prepare_parser!
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
      initiate_tls
      restart_xml_stream
    end

    def initiate_tls
      raise NotImplementedError
    end

    def ssl_verify_peer(pem)
      raise NotImplementedError
    end
  end
end
