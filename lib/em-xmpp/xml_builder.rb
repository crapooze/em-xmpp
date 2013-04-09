require 'ox'
module Ox
  class Element
		# args = attributes and/or children in any order, multiple appearance is possible
		# @overload build(name,attributes,children)
		#   @param [String] name name of the Element
		#   @param [Hash] attributes
		#   @param [String|Element|Array] children text, child element or array of elements
		def self.build(name, *args)
			n = new(name)

			for arg in args
				case arg
				when Hash
					arg.each { |k,v| n[k.to_s] = v }
				when Array
					arg.each { |c| n << c }
				when NilClass
				else
					n << arg
				end
			end

			n
		end
	end
end

module EM::Xmpp
	module XmlBuilder
    class OutgoingStanza
      attr_accessor :xml,:params

      def initialize(*args)
        node = Ox::Element.build(*args)
        @xml = Ox.dump(node)
        @params = node.attributes
      end
    end

		def x(*args)
			Ox::Element.build(*args)
		end

    def x_if(condition, *args)
      Ox::Element.build(*args) if condition
    end

    def build_xml(*args)
			Ox.dump(Ox::Element.build(*args))
    end
	end
end
