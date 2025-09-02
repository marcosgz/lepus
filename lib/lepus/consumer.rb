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

      # List of registered middlewares. Register new middlewares with {.use}.
      # @return [Array<Lepus::Middleware>]
      def middlewares
        @middlewares ||= []
      end

      # Registers a new middleware by instantiating +middleware+ and passing it +opts+.
      #
      # @param [Symbol, Class<Lepus::Middleware>] middleware The middleware class to instantiate and register.
      # @param [Hash] opts The options for instantiating the middleware.
      def use(middleware, opts = {})
        if middleware.is_a?(Symbol) || middleware.is_a?(String)
          begin
            require_relative "middlewares/#{middleware}"
            class_name = Primitive::String.new(middleware.to_s).classify
            class_name = "JSON" if class_name == "Json"
            middleware = Lepus::Middlewares.const_get(class_name)
          rescue LoadError, NameError
            raise ArgumentError, "Middleware #{middleware} not found"
          end
        end

        middlewares << middleware.new(**opts)
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
      message = Message.new(delivery_info, metadata, payload)
      self
        .class
        .middlewares
        .reverse
        .reduce(work_proc) do |next_middleware, middleware|
          nest_middleware(middleware, next_middleware)
        end
        .call(message)
    rescue Lepus::InvalidConsumerReturnError
      raise
    rescue Exception => ex # rubocop:disable Lint/RescueException
      # @TODO: add error handling
      logger.error(ex)

      reject!
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

    def work_proc
      ->(message) do
        perform(message).tap do |result|
          verify_result(result)
        end
      end
    end

    def nest_middleware(middleware, next_middleware)
      ->(message) do
        middleware.call(message, next_middleware)
      end
    end

    def verify_result(result)
      return if %i[ack reject requeue nack].include?(result)

      raise InvalidConsumerReturnError, result
    end

    def with_connection
      config.connection_pool.with_connection do |bunny|
        yield bunny
      end
    end
  end
end
