require 'nokogiri'
require 'ox'

#workarounds
module Ox
  module XPathSubset
    class Query 
      attr_reader :type, :name, :ns
      def initialize(t,e,n)
        @type, @name, @ns = t, e, n
      end

      def match(elem, ns_mapping)
        wanted_ns = ns_mapping[ns]

        same_value = elem.value == name 
        same_ns    = elem.xmlns == wanted_ns

        matching = same_value & same_ns
      end

      def find(elem, ns_mapping)
        ret = []
        ret << elem if match(elem, ns_mapping)
        case type
        when 'normal'
          elem.nodes.reject{|n| n.is_a?(String)}.each do |n|
            ret << n if match(n, ns_mapping)
          end
        when 'relative', 'anywhere' #TODO: for anywhere, should go to the root first, is that even possible?
          elem.nodes.reject{|n| n.is_a?(String)}.each do |n|
            find(n, ns_mapping).each {|m| ret << m}
          end
        else
          raise NotImplementedError
        end

        ret
      end
    end
  end

	class Element
    attr_accessor :xmlns
    def parse_xpath(path)
      queries = path.split('|').map(&:strip).map do |str|
        kind = if str.start_with?("//")
                 'anywhere'
               elsif str.start_with?(".//")
                 'relative'
               else
                 'normal'
               end
        ns,name = str.split(':',2)
        if name
          ns = ns.tr('/.','')
        else
          name,ns = ns,nil unless name
        end
        XPathSubset::Query.new(kind, name, ns)
      end
    end

		def xpath(path,ns_mapping)
      queries = parse_xpath(path)
      elems = []
      queries.each do |q|
        q.find(self,ns_mapping).each do |n|
          elems << n
        end
      end
      elems.uniq
		end

		def children
			text ? [] : nodes
		end

		def content
			text
		end

		def any?
			text
		end

    def child
      nodes.first
    end
	end
end

module EM::Xmpp
	module XmlParser

    class ForwardingParser < ::Nokogiri::XML::SAX::PushParser
      def initialize(receiver)
        doc = ForwardingDocument.new
        doc.recipient = receiver
        super doc
      end
    end

    #XML SAX document which delegates its method to a recipient object
    class ForwardingDocument < ::Nokogiri::XML::SAX::Document
      attr_accessor :recipient
      %w{xmldecl start_document end_document start_element_namespace end_element characters
      comment warning error cdata_block}.each do |meth|
        meth2 = "xml_#{meth}"
        define_method(meth) do |*args|
          recipient.send(meth2, *args)  if recipient
        end
      end
    end

		private

    ### XML world
    module XmlInterface
      def xml_xmldecl(version,encoding,standalone)
        raise NotImplementedError
      end
      def xml_start_document
        raise NotImplementedError
      end
      def xml_end_document
        raise NotImplementedError
      end
      def xml_start_element_namespace(name, attrs=[],prefix=nil,uri=nil,ns=[])
        raise NotImplementedError
      end
      def xml_end_element(name)
        raise NotImplementedError
      end
      def xml_characters(txt)
        raise NotImplementedError
      end
      def xml_error(err)
        raise RuntimeError, err
      end
      def xml_stream_closing
        raise NotImplementedError
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
    end

    module Nokogiri
      include XmlInterface
      def xml_xmldecl(version,encoding,standalone)
      end

      def xml_start_document
        #XXX set namespaces and stream prefix
        # namespace may depend on the type of connection ('jabber:client' or
        # 'jabber:server')
        # currently we do not set any stream's namespace, hence when builidng stanza,
        # we must explicitely avoid writing the namespace of iq/presence/message XML nodes
        @streamdoc = ::Nokogiri::XML::Document.new
      end

      def xml_end_document
        @streamdoc = @stanza = @stack = @xml_parser = nil
      end

      def xml_start_element_namespace(name, attrs=[],prefix=nil,uri=nil,ns=[])
        node = ::Nokogiri::XML::Node.new(name, @streamdoc)
        attrs.each do |attr|
          #attr is a Struct with members localname/prefix/uri/value
          node[attr.localname] = attr.value
        end
        #XXX - if prefix is there maybe we do not want to set uri as default
        node.default_namespace = uri if uri

        ns.each do |pfx,href|
          node.add_namespace_definition pfx, href
        end

        # puts "starting: #{name}, stack:#{@stack.size}" if $DEBUG
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
        #puts "ending: #{name}, stack:#{@stack.size}" if $DEBUG

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
        @stack.last << ::Nokogiri::XML::Text.new(txt, @streamdoc)
      end

      def xml_stream_closing
        close_xml_stream
        close_connection
      end

      def stream_support(node)
        @stanza = ::Nokogiri::XML::Node.new('dummy', @streamdoc)
        node << @stanza

        @streamdoc.root = node
      end

      def set_current_stanza!(node)
        @stanza.remove

        @stanza = node
        @streamdoc.root << @stanza
      end
    end

    module Ox
      include XmlInterface
      def xml_xmldecl(version,encoding,standalone)
      end

      def xml_start_document
        #XXX set namespaces and stream prefix
        #    namespace may depend on the type of connection ('jabber:client' or
        #    'jabber:server')
        #   currently we do not set any stream's namespace, hence when builidng stanza,
        #   we must explicitely avoid writing the namespace of iq/presence/message XML nodes
      end

      def xml_end_document
        @stanza = @stack = @xml_parser = nil
      end

      def xml_start_element_namespace(name, attrs=[],prefix=nil,uri=nil,ns=[])
        node = ::Ox::Element.new(name)
        node.xmlns = uri
        attrs.each do |attr|
          #attr is a Struct with members localname/prefix/uri/value
          node[attr.localname] = attr.value
        end

        case @stack.size
        when 0 #the streaming tag starts
          stream_support(node)
          stream_start node
        when 1 #a stanza starts
          set_current_stanza!(node)
          stanza_start node
        else
          @stack.last << node
        end

        @stack << node
        @text = nil
      end

      def xml_end_element(name)
        node = @stack.pop
        if @text
          node << @text
          @text = nil
        end
        #puts "ending: #{name}, stack:#{@stack.size}" if $DEBUG

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
        if @text
          @text<<txt
        else
          @text=txt
        end
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
        @stanza = ::Ox::Element.new('dummy')
        node << @stanza

        @streamdoc_root = node
      end

      def set_current_stanza!(node)
        @stanza = node
        @streamdoc_root.nodes[0] = @stanza
      end
    end

 	end
end
