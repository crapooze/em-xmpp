require 'ox'
require 'nokogiri'

module Ox
  module Builder
    # args = attributes and/or children in any order, multiple appearance is possible
    # @overload build(name,attributes,children)
    #   @param [String] name name of the Element
    #   @param [Hash] attributes
    #   @param [String|Element|Array] children text, child element or array of elements
    def x(name, *args)
      n = Element.new(name)
      yielded = if block_given?
                  yield
                else 
                  []
                end
      unless yielded.is_a?(Array)
        yielded = [yielded]
      end
      values = args + yielded

      values.each do |val|
        case val
        when Hash
          val.each { |k,v| n[k.to_s] = v }
        when Array
          val.each { |c| n << c if c}
        else
          n << val if val
        end
      end

      n
    end
    def x_if(condition, *args)
      x(*args) if condition
    end
  end
end

module Nokogiri::AlternativeBuilder
  class Element
    attr_reader :name, :children, :attributes
    def initialize(name)
      @name = name
      @children = []
      @attributes = {}
    end
    def << n
      @children << n
    end
    def []= k,v
      @attributes[k] = v
    end
  end

  def x(name, *args)
    n = Element.new(name)
    yielded = if block_given?
                yield
              else 
                []
              end
    unless yielded.is_a?(Array)
      yielded = [yielded]
    end
    values = args + yielded

    values.each do |val|
      case val
      when Hash
        val.each { |k,v| n[k.to_s] = v }
      when Array
        val.each { |c| n << c if c}
      else
        n << val if val
      end
    end
    n
  end
  def x_if(condition, *args)
    x(*args) if condition
  end
end

module EM::Xmpp
  module NokogiriXmlBuilder
    include Nokogiri::AlternativeBuilder
    class OutgoingStanza
      include NokogiriXmlBuilder

      attr_reader :xml,:params

      def initialize(*args,&blk)
        @root = x(*args,&blk)
        @doc = build_doc_from_element_root @root
        @xml = @doc.root.to_xml
        @params = @root.attributes
      end

      private

      def build_doc_from_element_root(root)
        doc = Nokogiri::XML::Document.new
        root_node = build_tree doc, root
        doc.root = root_node
        doc
      end
    end

    def build_xml(*args)
      root = x(*args)
      doc = Nokogiri::XML::Document.new
      doc.root = build_tree(doc,  root)
      ret  = doc.root.to_xml
      ret
    end

    private

    def build_tree(doc, node_info)
      node = node_info
      if node_info.respond_to?(:name)
        node = node_for_info doc, node_info
        list = node_info.children.map{|child| build_tree doc, child}
        list.each{|l| node << l }
      end
      node
    end

    def node_for_info(doc, node_info)
      node = Nokogiri::XML::Node.new(node_info.name, doc)
      node_info.attributes.each_pair {|k,v| node[k] = v}
      node
    end
  end

  module OxXmlBuilder
    include Ox::Builder

    class OutgoingStanza
      include OxXmlBuilder
      attr_reader :xml,:params

      def initialize(*args,&blk)
        node = x(*args,&blk)
        @xml = Ox.dump(node)
        @params = node.attributes
      end
    end

    def build_xml(*args)
      Ox.dump(x(*args))
    end
  end

  #XmlBuilder = OxXmlBuilder
  XmlBuilder = NokogiriXmlBuilder
end
