# frozen_string_literal: true

module Lepus
  # Manages middleware registration and execution for producers.
  # Middlewares can modify the message (payload, headers, routing_key, etc.)
  # before it is published to RabbitMQ.
  class MiddlewareChain
    attr_reader :middlewares

    def initialize
      @middlewares = []
    end

    # Registers a middleware to the chain.
    #
    # @param middleware [Symbol, String, Class<Lepus::Middleware>] The middleware to register.
    #   Can be a symbol/string (auto-loaded from producers/middlewares/) or a class.
    # @param opts [Hash] Options passed to the middleware constructor.
    # @return [self]
    def use(middleware, opts = {})
      instance = resolve_middleware(middleware, opts)
      @middlewares << instance
      self
    end

    # Executes the middleware chain with the given message.
    # The final action (publishing) is called after all middlewares have processed the message.
    #
    # @param message [Lepus::Message] The message to process.
    # @yield [message] Block called as the final action with the processed message.
    # @return [Object] The result of the final action.
    def execute(message, &final_action)
      chain = @middlewares.reduce(final_action) do |next_middleware, middleware|
        ->(msg) { middleware.call(msg, next_middleware) }
      end
      chain.call(message)
    end

    # Creates a combined chain from multiple chains.
    # Used to merge global and per-producer middleware chains.
    #
    # @param chains [Array<MiddlewareChain>] The chains to combine.
    # @return [MiddlewareChain] A new chain containing all middlewares.
    def self.combine(*chains)
      combined = new
      chains.each do |chain|
        chain.middlewares.each { |m| combined.middlewares << m }
      end
      combined
    end

    # Returns true if the chain has no middlewares.
    #
    # @return [Boolean]
    def empty?
      @middlewares.empty?
    end

    # Returns the number of middlewares in the chain.
    #
    # @return [Integer]
    def size
      @middlewares.size
    end

    private

    def resolve_middleware(middleware, opts)
      case middleware
      when Symbol, String
        load_middleware(middleware, opts)
      when Class
        middleware.new(**opts)
      else
        raise ArgumentError, "Middleware must be a Symbol, String, or Class, got #{middleware.class}"
      end
    end

    def load_middleware(name, opts)
      raise NotImplementedError, "Subclass must implement #load_middleware"
    end
  end
end
