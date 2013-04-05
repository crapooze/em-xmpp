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
					arg.each { |k,v| n[k] = v }
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
		def x(name, *args)
			Ox::Element.build(name, *args)
		end

    def build_xml(*args)
			Ox.dump(x(*args))
    end
	end
end
