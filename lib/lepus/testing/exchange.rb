# frozen_string_literal: true

module Lepus
  module Testing
    # Represents a fake exchange that stores published messages for testing
    class Exchange
      attr_reader :name, :messages

      def initialize(name)
        @name = name
        @messages = []
      end

      # Add a message to this exchange
      # @param message [Hash] The message data including payload, routing_key, headers, etc.
      def add_message(message)
        @messages << message
      end

      # Clear all messages from this exchange
      def clear_messages
        @messages.clear
      end

      # Get the number of messages in this exchange
      def size
        @messages.size
      end

      # Check if this exchange has any messages
      def empty?
        @messages.empty?
      end

      # Find messages matching specific criteria
      # @param criteria [Hash] Criteria to match against message data
      # @return [Array<Hash>] Matching messages
      def find_messages(criteria = {})
        return @messages if criteria.empty?

        @messages.select do |message|
          criteria.all? do |key, value|
            case key
            when :routing_key
              message[:routing_key] == value
            when :payload
              message[:payload] == value
            when :headers
              message[:headers]&.any? { |k, v| value.any? { |vk, vv| k == vk && v == vv } }
            else
              message[key] == value
            end
          end
        end
      end

      # Class methods for managing all exchanges
      class << self
        # Get or create an exchange by name
        # @param name [String] The exchange name
        # @return [Lepus::Testing::Exchange] The exchange instance
        def [](name)
          exchanges[name.to_s] ||= new(name.to_s)
        end

        # Get all exchanges
        # @return [Hash<String, Lepus::Testing::Exchange>] All exchanges
        def all
          exchanges
        end

        # Clear all messages from all exchanges
        def clear_all_messages!
          exchanges.each_value(&:clear_messages)
        end

        # Clear all exchanges (remove them completely)
        def clear_all!
          exchanges.clear
        end

        # Get the total number of messages across all exchanges
        def total_messages
          exchanges.values.sum(&:size)
        end

        private

        def exchanges
          @exchanges ||= {}
        end
      end
    end
  end
end
