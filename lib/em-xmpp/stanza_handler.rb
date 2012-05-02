
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
      if (not ctx.done?) and (match?(ctx.stanza))
        ctx['xpath.handler'] = self
        ctx = callback.call(ctx)
        raise RuntimeError, "xpath handlers should return a Context" unless ctx.is_a?(Context)

        self if ctx.reuse_handler?
      else
        self
      end
    end
  end
end

