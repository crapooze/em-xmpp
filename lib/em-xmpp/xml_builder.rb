require 'ox'

module EM::Xmpp
	module XmlBuilder
		def x(name, *args)
			n = Ox::Element.new(name)

			unless args.empty?
				params, children = args.first, args.last

				params.each { |k,v| n[k] = v } if params.instance_of?(Hash)
				children.each { |c| n << c } if children.instance_of?(Array)
				n << children if children.instance_of?(n.class) or children.instance_of?(String)
			end

			n
		end

    def build_xml(*args)
			Ox.dump(x(*args))
    end
	end
end