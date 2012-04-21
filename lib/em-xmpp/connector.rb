
require 'nokogiri'
require 'eventmachine'
require 'em-xmpp/context'
require 'em-xmpp/namespaces'
require 'em-xmpp/resolver'

module EM::Xmpp
  module Connector
    include Namespaces

    #XML SAX document which delegates its method to a recipient object
    class ForwardingDocument < Nokogiri::XML::SAX::Document
      attr_accessor :recipient
      %w{xmldecl start_document end_document start_element_namespace end_element characters
      comment warning error cdata_block}.each do |meth|
        meth2 = "xml_#{meth}"
        define_method(meth) do |*args| 
          recipient.send(meth2, *args)  if recipient
        end
      end
    end

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

    def send_xml(&blk)
      data = build_xml(&blk)
      send_raw data
    end

    def restart_xml_stream
      @xml_parser.document.recipient = nil
      post_init
    end

    def post_init
      doc = ForwardingDocument.new
      doc.recipient = self
      @xml_parser   = Nokogiri::XML::SAX::PushParser.new doc
      @stack        = []
      @stanza       = nil
      @streamdoc    = nil

      open_xml_stream
    end

    def receive_data(dat)
      puts "<< in\n#{dat}\n" if $DEBUG
      @xml_parser << dat
    end

    def unbind
      puts "**** unbound ****" if $DEBUG
    end

    def build_xml(&blk)
      n = Nokogiri::XML::Builder.new(&blk)
      n.doc.root.to_xml 
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

    ### XML world

    def xml_xmldecl(version,encoding,standalone)
    end

    def xml_start_document
      #XXX set namespaces and stream prefix
      #    namespace may depend on the type of connection ('jabber:client' or
      #    'jabber:server')
      #   currently we do not set any stream's namespace, hence when builidng stanza,
      #   we must explicitely avoid writing the namespace of iq/presence/message XML nodes
      @streamdoc      = Nokogiri::XML::Document.new
    end

    def xml_end_document
      @streamdoc = @stanza = @stack = @xml_parser = nil
    end

    def xml_start_element_namespace(name, attrs=[],prefix=nil,uri=nil,ns=[])
      node = Nokogiri::XML::Node.new(name, @streamdoc)
      attrs.each do |attr|
        #attr is a Struct with members localname/prefix/uri/value
        node[attr.localname] = attr.value
      end
      #XXX - if prefix is there maybe we do not want to set uri as default
      node.default_namespace = uri if uri

      ns.each do |pfx,href|
        node.add_namespace_definition pfx, href
      end

      puts "starting: #{name}, stack:#{@stack.size}" if $DEBUG
      case @stack.size
      when 0 #the streaming tag starts
        stream_support(node)
      when 1 #a stanza starts
        set_current_stanza!(node)
        stanza_start node
      else 
        @stack.last.add_child node
      end

      @stack << node 
    end

    def xml_end_element(name)
      node = @stack.pop
      puts "ending: #{name}, stack:#{@stack.size}" if $DEBUG

      case @stack.size
      when 0 #i.e., the stream support ends
        xml_stream_closing 
      when 1 #i.e., we've finished a stanza
        raise RuntimeError, "should end on a stanza" unless node == @stanza
        stanza_end node
      else
        #the stanza keeps growing
      end
    end

    def xml_characters(txt)
      @stack.last << Nokogiri::XML::Text.new(txt, @streamdoc)
    end

    def xml_error(err)
      #raise RuntimeError, err
    end

    def xml_stream_closing
      close_xml_stream
      close_connection
    end

    def xml_comment(comm)
      raise NotImplementedError
    end

    def xml_warning(warn)
      raise NotImplementedError
    end

    def xml_cdata_block(data)
      raise NotImplementedError
    end

    ### XMPP World

    def stream_support(node)
      @stanza         = Nokogiri::XML::Node.new('dummy', @streamdoc)
      node << @stanza

      @streamdoc.root = node
    end

    def set_current_stanza!(node)
      @stanza.remove

      @stanza = node
      @streamdoc.root << @stanza
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
      send_xml do |x|
        x.starttls(:xmlns => TLS)
      end
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
