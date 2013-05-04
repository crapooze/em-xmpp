require 'ox'
module Ox
  module Builder
		# args = attributes and/or children in any order, multiple appearance is possible
		# @overload build(name,attributes,children)
		#   @param [String] name name of the Element
		#   @param [Hash] attributes
		#   @param [String|Element|Array] children text, child element or array of elements
		def x(name, *args)
			n = Element.new(name)
      *yielded = if block_given?
                  yield
                else 
                  []
                end
      values = *args + yielded

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

module EM::Xmpp
	module XmlBuilder
    include Ox::Builder
    
    class OutgoingStanza
      include Ox::Builder
      
      attr_accessor :xml,:params

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
end
