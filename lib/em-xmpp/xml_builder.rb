require 'ox'

module EM::Xmpp
	module XmlBuilder
		def x(name, *args)
			n = Ox::Element.new(name)

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

    def build_xml(*args)
			Ox.dump(x(*args))
    end
	end
end
