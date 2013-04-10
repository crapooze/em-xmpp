require 'nokogiri'
require 'ox'

#workarounds
module Ox
	class Element
		def xpath(path,ns)
			pat = /\/\/.+:/
			l1=path.sub(pat,'')

      queue=[self]
      r=[]
      until queue.empty?
        p = queue.shift
        r << p if p.value == l1
        queue.concat(p.nodes) unless p.children.empty? or !r.empty?
      end

			if r.size == 1 and l1 == 'jid'
				r=r.first
			end

			r
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
	end
end

module EM::Xmpp
	module XmlParser
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
 
      open_xml_stream
    end
		
    def receive_data(dat)
      puts "<< in\n#{dat}\n" if $DEBUG
      @xml_parser << dat
    end

		private

    ### XML world

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
      node = Ox::Element.new(name)
      attrs.each do |attr|
        #attr is a Struct with members localname/prefix/uri/value
        node[attr.localname] = attr.value
      end

      case @stack.size
      when 0 #the streaming tag starts
        stream_support(node)
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
      @stanza = Ox::Element.new('dummy')
      node << @stanza

      @streamdoc_root = node
    end

    def set_current_stanza!(node)
      @stanza = node
      @streamdoc_root.nodes[0] = @stanza
    end

 	end
end