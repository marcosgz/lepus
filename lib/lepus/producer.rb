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
        @publisher ||= Publisher.new(*definition.exchange_args)
      end

      # Publishes a message using this producer's configuration.
      # @param message [String, Hash] The message to publish.
      # @param options [Hash] Additional publish options (routing_key, headers, etc.).
      # @return [void]
      def publish(message, **options)
        # Merge default publish options with provided options
        publish_opts = definition.publish_options.merge(options)
        publisher.publish(message, **publish_opts)
      end
    end

    # Instance methods for when you need to work with producer instances
    def initialize
      @definition = self.class.definition
    end

    def definition
      @definition
    end

    def publisher
      @publisher ||= Publisher.new(*definition.exchange_args)
    end

    def publish(message, **options)
      publish_opts = definition.publish_options.merge(options)
      publisher.publish(message, **publish_opts)
    end
  end
end
