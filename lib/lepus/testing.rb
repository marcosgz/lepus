# frozen_string_literal: true

require_relative "testing/exchange"
require_relative "testing/rspec_matchers"
require_relative "testing/message_builder"

module Lepus
  module Testing
    # Enable fake publishing mode for testing
    # When enabled, messages are stored in fake exchanges instead of being sent to RabbitMQ
    def self.fake_publisher!
      @fake_publisher_enabled = true
    end

    # Disable fake publishing mode
    def self.disable!
      @fake_publisher_enabled = false
    end

    # Check if fake publishing is enabled
    def self.fake_publisher_enabled?
      @fake_publisher_enabled == true
    end

    # Clear all messages from all fake exchanges
    def self.clear_all_messages!
      Exchange.clear_all_messages!
    end

    # Get all fake exchanges
    def self.exchanges
      Exchange.all
    end

    # Get a specific fake exchange by name
    def self.exchange(name)
      Exchange[name]
    end

    # Get messages for a specific producer class
    def self.producer_messages(producer_class)
      return [] unless producer_class.respond_to?(:definition)

      begin
        exchange_name = producer_class.definition.exchange_name
        Exchange[exchange_name].messages
      rescue
        # If there's an error getting the exchange name, return empty array
        []
      end
    end

    # Test a consumer with a message
    # @param consumer_class [Class] The consumer class to test
    # @param message_or_payload [Lepus::Message, Hash, String] The message to process
    # @return [Symbol] The result of the consumer's perform method (:ack, :reject, :requeue, :nack)
    def self.consumer_perform(consumer_class, message_or_payload)
      message = build_message(message_or_payload)
      consumer = consumer_class.new
      consumer.process_delivery(message.delivery_info, message.metadata, message.payload)
    end

    # Create a message builder for custom scenarios
    # @return [MessageBuilder] A new message builder instance
    def self.message_builder
      MessageBuilder.new
    end

    private

    # Build a message from various input types
    def self.build_message(message_or_payload)
      case message_or_payload
      when Lepus::Message
        message_or_payload
      when Hash
        if message_or_payload.key?(:payload)
          # Hash with payload and other options
          payload = message_or_payload.delete(:payload)
          MessageBuilder.new
            .with_payload(payload)
            .tap { |builder| apply_options(builder, message_or_payload) }
            .build
        else
          # Hash as payload - create message with Hash payload
          MessageBuilder.new
            .with_payload(message_or_payload)
            .with_content_type("application/json")
            .build
        end
      when String
        MessageBuilder.new
          .with_payload(message_or_payload)
          .with_content_type("text/plain")
          .build
      else
        raise ArgumentError, "Invalid message type: #{message_or_payload.class}"
      end
    end

    # Apply options to a message builder
    def self.apply_options(builder, options)
      options.each do |key, value|
        method_name = "with_#{key}"
        if builder.respond_to?(method_name)
          builder.send(method_name, value)
        end
      end
    end

    # Override Publisher methods when testing module is loaded
    def self.setup_publisher_overrides!
      return if @overrides_setup

      # Add messages method to Producer class
      Lepus::Producer.class_eval do
        # Get messages published by this producer (only available in testing mode)
        # @return [Array<Hash>] Array of published messages
        def self.messages
          Lepus::Testing.producer_messages(self)
        end
      end

      # Override Publisher#publish
      Lepus::Publisher.class_eval do
        alias_method :original_publish, :publish

        def publish(message, **options)
          return unless Lepus::Producers.exchange_enabled?(exchange_name)

          if Lepus::Testing.fake_publisher_enabled?
            return fake_publish(message, **options)
          end

          original_publish(message, **options)
        end

        # Override Publisher#channel_publish
        alias_method :original_channel_publish, :channel_publish

        def channel_publish(channel, message, **options)
          raise ArgumentError, "channel is required" unless channel
          return unless Lepus::Producers.exchange_enabled?(exchange_name)

          if Lepus::Testing.fake_publisher_enabled?
            return fake_publish(message, **options)
          end

          original_channel_publish(channel, message, **options)
        end

        # Add fake_publish method
        private

        def fake_publish(message, **options)
          opts = Lepus::Publisher::DEFAULT_PUBLISH_OPTIONS.merge(options)

          fake_message = {
            exchange: exchange_name,
            payload: message, # Store the original message, not the JSON string
            routing_key: opts[:routing_key],
            headers: opts[:headers],
            persistent: opts[:persistent],
            mandatory: opts[:mandatory],
            immediate: opts[:immediate],
            content_type: message.is_a?(String) ? "text/plain" : "application/json",
            timestamp: Time.now
          }

          Lepus::Testing::Exchange[exchange_name].add_message(fake_message)
        end
      end

      @overrides_setup = true
    end
  end
end

# Automatically setup overrides when the testing module is required
Lepus::Testing.setup_publisher_overrides!
