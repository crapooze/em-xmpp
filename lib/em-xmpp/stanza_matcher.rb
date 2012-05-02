
module EM::Xmpp
  class StanzaMatcher
    attr_reader :matcher

    def initialize(obj=nil,args={},&blk)
      obj ||= blk
      @matcher = case obj
                 when :anything
                   proc { true }
                 when String
                   proc { |xml| xml.xpath(obj, args).any? }
                 else
                   obj
                 end
    end

    def match?(xml)
      matcher.call xml
    end
  end
end
