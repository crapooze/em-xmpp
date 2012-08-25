
module EM::Xmpp
  class StanzaHandler
    attr_reader :matcher, :callback 
    def initialize(matcher, cb=nil, &blk)
      raise ArgumentError unless matcher.respond_to? :match?
      @matcher  = matcher
      @callback = cb || blk
    end

    def match?(obj)
      matcher.match? obj
    end

    def call(ctx)
      callback.call(ctx)
    end
  end
end

