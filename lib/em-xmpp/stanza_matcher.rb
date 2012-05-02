
module EM::Xmpp
  class StanzaMatcher
    attr_reader :matcher
    attr_reader :callback

    def initialize(obj,args,cb)
      @matcher = case obj
                 when :anything
                   proc { true }
                 when String
                   proc { |xml| xml.xpath(obj, args).any? }
                 else
                   obj
                 end

      @callback = cb
    end

    alias :blk :callback

    def match?(xml)
      matcher.call xml
    end
  end
end
