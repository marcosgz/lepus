# frozen_string_literal: true

module Lepus
  # The abstract base class for consumers processing messages from queues.
  # @abstract Subclass and override {#work} to implement.
  class Consumer
    class << self
      def abstract_class?
        return @abstract_class == true if defined?(@abstract_class)

        instance_variable_get(:@config).nil?
      end

      def abstract_class=(value)
        @config = nil
        @abstract_class = value
      end

      def inherited(subclass)
        super
        subclass.abstract_class = false
      end

      def config
        return if @abstract_class == true
        return @config if defined?(@config)

        name = Primitive::String.new(to_s).underscore.split("/").last
        @config = Consumers::Config.new(queue: name, exchange: name)
      end

      # Returns the middleware chain for this consumer.
      # Inherits middlewares registered on superclasses so abstract base consumers
      # can declare shared middlewares with `use` and have them apply to subclasses.
      # @return [Lepus::Consumers::MiddlewareChain]
      def middleware_chain
        @middleware_chain ||= begin
          chain = Consumers::MiddlewareChain.new
          if superclass.respond_to?(:middleware_chain)
            superclass.middleware_chain.middlewares.each { |m| chain.middlewares << m }
          end
          chain
        end
      end

      # Registers a middleware to this consumer's chain.
      #
      # @param middleware [Symbol, String, Class<Lepus::Middleware>] The middleware to register.
      # @param opts [Hash] Options passed to the middleware constructor.
      # @return [Lepus::Consumers::MiddlewareChain]
      def use(middleware, opts = {})
        middleware_chain.use(middleware, opts)
      end

      # Configures the consumer, setting queue, exchange and other options to be used by
      # the add_consumer method.
      #
      # @param [Hash] opts The options to configure the consumer with.
      # @option opts [String, Hash] :queue The name of the queue to consume from.
      # @option opts [String, Hash] :exchange The name of the exchange the queue should be bound to.
      # @option opts [Array] :routing_key The routing keys used for the queue binding.
      # @option opts [Boolean, Hash] :retry_queue (false) Whether a retry queue should be provided.
      # @option opts [Boolean, Hash] :error_queue (false) Whether an error queue should be provided.
      def configure(opts = {})
        raise ArgumentError, "Cannot configure an abstract class" if abstract_class?

        @config = Consumers::Config.new(opts)
        yield(@config) if block_given?
        @config
      end

      def descendants # :nodoc:
        descendants = []
        ObjectSpace.each_object(singleton_class) do |k|
          descendants.unshift k unless k == self
        end
        descendants.uniq
      end
    end

    # The method that is called when a message from the queue is received.
    # Keep in mind that the parameters received can be altered by middlewares!
    #
    # @param [Leupus::Message] message The message to process.
    #
    # @return [:ack, :reject, :requeue] A symbol denoting what should be done with the message.
    def perform(message)
      raise NotImplementedError
    end

    # Wraps #perform to add middlewares. This is being called by Lepus when a message is received for the consumer.
    #
    # @param [Bunny::DeliveryInfo] delivery_info The delivery info of the received message.
    # @param [Bunny::MessageProperties] metadata The metadata of the received message.
    # @param [String] payload The payload of the received message.
    # @raise [InvalidConsumerReturnError] if you return something other than +:ack+, +:reject+ or +:requeue+ from {#perform}.
    def process_delivery(delivery_info, metadata, payload)
      message = Message.coerce(delivery_info, metadata, payload)
      message.consumer_class = self.class

      combined_chain = MiddlewareChain.combine(
        Lepus.config.consumer_middleware_chain,
        self.class.middleware_chain
      )

      combined_chain.execute(message) do |msg|
        perform(msg).tap do |result|
          verify_result(result)
        end
      end
    rescue Lepus::InvalidConsumerReturnError
      raise
    rescue Exception # rubocop:disable Lint/RescueException
      on_delivery_error
      # In testing mode, re-raise exceptions if consumer_raise_errors? is enabled
      if defined?(Lepus::Testing) && Lepus::Testing.consumer_raise_errors?
        raise
      end

      reject!
    end

    # Returns whether the last delivery resulted in an error.
    # Always false in core; overridden by Lepus::Web when loaded.
    def last_delivery_errored?
      false
    end

    protected

    def logger
      Lepus.logger
    end

    # Helper method to ack a message.
    #
    # @return [:ack]
    def ack!
      :ack
    end
    alias_method :ack, :ack!

    # Helper method to reject a message.
    #
    # @return [:reject]
    #
    def reject!
      :reject
    end
    alias_method :reject, :reject!

    # Helper method to requeue a message.
    #
    # @return [:requeue]
    def requeue!
      :requeue
    end
    alias_method :requeue, :requeue!

    # Helper method to nack a message.
    #
    # @return [:nack]
    def nack!
      :nack
    end
    alias_method :nack, :nack!

    private

    # Publishes a message using the consumer's own exchange configuration.
    # When exchange_name is different from the consumer's exchange, uses default options.
    #
    # @param [String, Hash] message The message to publish
    # @param [String, nil] exchange_name Override the exchange name (optional)
    # @param [Hash] options Additional publish options
    # @return [void]
    def publish_message(message, exchange_name: nil, channel: nil, **options)
      target_exchange = exchange_name || self.class.config.exchange_name
      return unless Lepus::Producers.exchange_enabled?(target_exchange)

      opts = (target_exchange == self.class.config.exchange_name) ? self.class.config.exchange_options : {}
      opts.merge!(options)

      channel ||= instance_variable_get(:@_handler_channel) # The Lepus::Consumers::Handler sets this variable
      if channel
        Lepus::Publisher.new(target_exchange, **opts).channel_publish(channel, message, **opts)
      else
        Lepus::Publisher.new(target_exchange, **opts).publish(message, **opts)
      end
    end

    # Hook called when a delivery raises an exception.
    # No-op in core; overridden by Lepus::Web to track error state.
    def on_delivery_error
    end

    def verify_result(result)
      return if %i[ack reject requeue nack].include?(result)

      raise InvalidConsumerReturnError, result
    end
  end
end
