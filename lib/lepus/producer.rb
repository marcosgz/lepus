# frozen_string_literal: true

module Lepus
  # The abstract base class for producers publishing messages to exchanges.
  # @abstract Subclass and override {#configure} to implement.
  class Producer
    class << self
      def abstract_class?
        return @abstract_class == true if defined?(@abstract_class)

        instance_variable_get(:@definition).nil?
      end

      def abstract_class=(value)
        @abstract_class = value
        remove_instance_variable(:@definition) if instance_variable_defined?(:@definition)
      end

      def inherited(subclass)
        super
        subclass.abstract_class = false
      end

      def definition
        return if abstract_class?
        return @definition if defined?(@definition)

        name = Primitive::String.new(to_s).underscore.split("/").last
        @definition = Producers::Definition.new(exchange: name)
      end

      # Configures the producer, setting exchange and other options to be used by
      # the publisher for sending messages.
      #
      # @param [Hash] opts The options to configure the producer with.
      # @option opts [String, Hash] :exchange The name of the exchange to publish to.
      # @option opts [Hash] :publish Default publish options (persistent, mandatory, immediate).
      # @yield [definition] Optional block to further configure the producer.
      # @yieldparam [Lepus::Producers::Definition] definition The definition object.
      # @return [Lepus::Producers::Definition] The configured producer definition.
      def configure(opts = {})
        raise ArgumentError, "Cannot configure an abstract class" if abstract_class?

        @definition = Producers::Definition.new(opts)
        yield(@definition) if block_given?
        @definition
      end

      def descendants # :nodoc:
        descendants = []
        ObjectSpace.each_object(singleton_class) do |k|
          descendants.unshift k unless k == self
        end
        descendants.uniq
      end

      # Creates a publisher instance configured with this producer's settings.
      # @return [Lepus::Publisher] A publisher instance ready to send messages.
      def publisher
        @publisher ||= Publisher.new(definition.exchange_name, **definition.exchange_options)
      end

      # Returns the middleware chain for this producer.
      # @return [Lepus::Producers::MiddlewareChain]
      def middleware_chain
        @middleware_chain ||= Producers::MiddlewareChain.new
      end

      # Registers a middleware to this producer's chain.
      #
      # @param middleware [Symbol, String, Class<Lepus::Middleware>] The middleware to register.
      # @param opts [Hash] Options passed to the middleware constructor.
      # @return [Lepus::Producers::MiddlewareChain]
      def use(middleware, opts = {})
        middleware_chain.use(middleware, opts)
      end

      # Publishes a message using this producer's configuration.
      # Executes the middleware chain (global + per-producer) before publishing.
      #
      # @param payload [String, Hash] The message payload to publish.
      # @param options [Hash] Additional publish options (routing_key, headers, etc.).
      # @return [void]
      def publish(payload, **options)
        if definition.nil?
          raise InvalidProducerConfigError, <<~ERROR
            The #{name} producer is not configured.
            Please call #{name}.configure before using #{self.class.name}.publish.
          ERROR
        end

        return unless Producers.enabled?(self)

        publish_opts = definition.publish_options.merge(options)
        message = build_message(payload, publish_opts)
        combined_chain = MiddlewareChain.combine(
          Lepus.config.producer_middleware_chain,
          middleware_chain
        )

        combined_chain.execute(message) do |msg|
          publisher.publish(msg.payload, **msg.to_publish_options)
        end
      end

      private

      def build_message(payload, options)
        opts = options.dup
        routing_key = opts.delete(:routing_key)
        headers = opts.delete(:headers)

        delivery_info = Message::DeliveryInfo.new(
          exchange: definition.exchange_name,
          routing_key: routing_key
        )

        metadata = Message::Metadata.new(
          headers: headers,
          content_type: opts.delete(:content_type),
          content_encoding: opts.delete(:content_encoding),
          correlation_id: opts.delete(:correlation_id),
          reply_to: opts.delete(:reply_to),
          expiration: opts.delete(:expiration),
          message_id: opts.delete(:message_id),
          timestamp: opts.delete(:timestamp),
          type: opts.delete(:type),
          app_id: opts.delete(:app_id),
          priority: opts.delete(:priority),
          delivery_mode: opts.delete(:delivery_mode)
        )

        # Remaining options (persistent, mandatory, etc.) are passed as publish_options
        Message.new(delivery_info, metadata, payload, publish_options: opts)
      end
    end

    # Instance methods for when you need to work with producer instances
    def initialize
      @definition = self.class.definition
    end

    attr_reader :definition

    def publisher
      @publisher ||= Publisher.new(definition.exchange_name, **definition.exchange_options)
    end

    def publish(message, **options)
      self.class.publish(message, **options)
    end
  end
end
