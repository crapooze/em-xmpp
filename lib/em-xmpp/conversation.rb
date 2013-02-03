
require 'fiber'
module EM::Xmpp
  class Conversation

    class CallbackSet
      def initialize
        @callbacks = {}
      end
      def on(key,&blk)
        @callbacks[key] = blk
      end
      def cb(key)
        @callbacks[key]
      end
    end

    Continue = Struct.new(:type, :ctx) do
      def timeout?
        type == :timeout
      end
      def interrupted?
        not timeout?
      end
    end
    Timeout  = Continue.new(:timeout, nil)

    def self.start(ctx,state)
      fib = Fiber.new do
        conv = Fiber.yield
        yield conv
      end
      fib.resume #first resume starts the fiber
      obj = self.new(ctx,state,fib)
      fib.resume obj #second resume injects the conversation to call block
      obj
    end

    # A list of callbacks
    attr_reader :callbacks

    # A user-provided state
    attr_reader :state

    def initialize(ctx,state,fiber=Fiber.current)
      @connection = ctx.connection
      @fiber      = fiber
      @state      = state
      @callbacks  = CallbackSet.new
    end

    def prepare_callbacks(*keys)
      yield callbacks
      expect_callbacks *keys
    end

    private
    def expect_callbacks(*keys)
      missing = keys.reject {|k| callbacks.cb(k) }.map(&:to_s)
      raise RuntimeError, "missing callbacks #{missing.join(' ')}" unless missing.empty?
    end
    public

    def callback(key,&blk)
      cb = callbacks.cb(key)
      raise RuntimeError, "no such callback #{key}" unless cb
      cb.call state, &blk
    end

    def start_timeout(seconds=:forever)
      timer = nil
      unless seconds == :forever
        timer = EM::Timer.new(seconds) do
          wake_up Timeout if @fiber
        end
      end
      timer
    end

    def delay(seconds=:forever)
      timer = start_timeout seconds
      ret = Fiber.yield
      timer.cancel if timer
      ret
    end

    def resume(ctx)
      wake_up Continue.new(:resumed, ctx)
    end

    def wake_up(obj)
      @fiber.resume obj
    end

    def send_stanza(stanza,seconds=:forever)
      @connection.send_stanza(stanza) do |response|
        resume response
      end
      timer = start_timeout seconds if seconds
      ret = Fiber.yield unless seconds == :no_response
      timer.cancel if timer
      ret
    end
  end
end
