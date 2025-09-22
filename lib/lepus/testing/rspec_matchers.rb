# frozen_string_literal: true

module Lepus
  module Testing
    module RSpecMatchers
      # RSpec matcher for testing message publishing
      class PublishLepusMessage
        def initialize(expected_count = nil)
          @expected_count = expected_count
          @expected_exchange = nil
          @expected_routing_key = nil
          @expected_payload = nil
        end

        # Support block expectations
        def supports_block_expectations?
          true
        end

        # Supports both block expectations and value expectations with a producer class
        def matches?(actual = nil, &block)
          if block || actual.is_a?(Proc)
            @producer_class = nil
            @scoped_messages = nil

            @messages_before = count_all_messages
            (block || actual).call
            @messages_after = count_all_messages
            @published_count = @messages_after - @messages_before
          elsif actual.is_a?(Class) && actual < Lepus::Producer
            @producer_class = actual
            @scoped_messages = Lepus::Testing.producer_messages(@producer_class)
            @messages_before = 0
            @messages_after = @scoped_messages.size
            @published_count = @messages_after
          else
            return false
          end

          matches_count? && matches_exchange? && matches_routing_key? && matches_payload?
        end

        def failure_message
          message = "expected to publish #{expected_description}"
          message += ", but published #{@published_count} message(s)"

          if @expected_exchange
            matching_exchange = get_recent_messages(@published_count).count { |msg| msg[:exchange] == @expected_exchange }
            message += " to exchange '#{@expected_exchange}' (#{matching_exchange} matched)"
          end

          if @expected_routing_key
            matching_routing = get_recent_messages(@published_count).count { |msg| msg[:routing_key] == @expected_routing_key }
            message += " with routing key '#{@expected_routing_key}' (#{matching_routing} matched)"
          end

          if @expected_payload
            matching_payload = get_recent_messages(@published_count).count { |msg| @expected_payload.matches?(msg[:payload]) }
            message += " with payload matching #{@expected_payload} (#{matching_payload} matched)"
          end

          message
        end

        def failure_message_when_negated
          "expected not to publish #{expected_description}, but did"
        end

        def description
          expected_description
        end

        # Chainable methods for specifying expectations
        def to_exchange(exchange_name)
          @expected_exchange = exchange_name.to_s
          self
        end

        def with_routing_key(routing_key)
          @expected_routing_key = routing_key.to_s
          self
        end

        def with(payload_matcher)
          @expected_payload = payload_matcher
          self
        end

        private

        def expected_description
          desc = @expected_count ? "#{@expected_count} message(s)" : "a message"
          desc += " to exchange '#{@expected_exchange}'" if @expected_exchange
          desc += " with routing key '#{@expected_routing_key}'" if @expected_routing_key
          desc += " with payload matching #{@expected_payload}" if @expected_payload
          desc
        end

        def matches_count?
          return @published_count > 0 unless @expected_count
          @published_count == @expected_count
        end

        def matches_exchange?
          return true unless @expected_exchange
          return false if @published_count == 0

          # Get the last published messages and check if any match the expected exchange
          recent_messages = get_recent_messages(@published_count)
          recent_messages.any? { |msg| msg[:exchange] == @expected_exchange }
        end

        def matches_routing_key?
          return true unless @expected_routing_key
          return false if @published_count == 0

          recent_messages = get_recent_messages(@published_count)
          recent_messages.any? { |msg| msg[:routing_key] == @expected_routing_key }
        end

        def matches_payload?
          return true unless @expected_payload
          return false if @published_count == 0

          recent_messages = get_recent_messages(@published_count)

          payload_matcher =
            if @expected_payload.respond_to?(:matches?)
              @expected_payload
            elsif defined?(RSpec::Matchers)
              RSpec::Matchers::BuiltIn::Eq.new(@expected_payload)
            else
              Struct.new(:expected) do
                def matches?(actual)
                  actual == expected
                end
              end.new(@expected_payload)
            end

          recent_messages.any? { |msg| payload_matcher.matches?(msg[:payload]) }
        end

        def count_all_messages
          Lepus::Testing::Exchange.all.values.sum(&:size)
        end

        def get_recent_messages(count)
          count ||= 0
          messages =
            if @scoped_messages
              @scoped_messages
            else
              all_messages = []
              Lepus::Testing::Exchange.all.each_value do |exchange|
                all_messages.concat(exchange.messages)
              end
              all_messages
            end

          # Sort by timestamp and get the most recent messages
          messages.sort_by { |msg| msg[:timestamp] }.last(count)
        end
      end

      # RSpec matcher for testing consumer message processing
      class ProcessLepusMessage
        def initialize(expected_result = :ack)
          @expected_result = expected_result
          @consumer_class = nil
          @message_or_payload = nil
          @delivery_info = nil
          @metadata = nil
        end

        def matches?(consumer_class_or_message)
          if consumer_class_or_message.is_a?(Class) && consumer_class_or_message < Lepus::Consumer
            # Called with consumer class, expect message to be provided via with_message
            @consumer_class = consumer_class_or_message
            return false unless @message_or_payload
          else
            # Called with message, expect consumer to be provided via with_consumer
            @message_or_payload = consumer_class_or_message
            return false unless @consumer_class
          end

          result = Lepus::Testing.consumer_perform(
            @consumer_class,
            @message_or_payload
          )

          @actual_result = result
          result == @expected_result
        end

        def failure_message
          "expected #{@consumer_class} to #{@expected_result} message, but got #{@actual_result}"
        end

        def failure_message_when_negated
          "expected #{@consumer_class} not to #{@expected_result} message, but it did"
        end

        def description
          "#{@expected_result} message with #{@consumer_class}"
        end

        # Chainable methods
        def with_message(message_or_payload)
          @message_or_payload = message_or_payload
          self
        end

        def with_delivery_info(delivery_info)
          @delivery_info = delivery_info
          self
        end

        def with_metadata(metadata)
          @metadata = metadata
          self
        end
      end

      # Main matcher methods
      def lepus_publish_message(expected_count = nil)
        PublishLepusMessage.new(expected_count)
      end

      def lepus_acknowledge_message(message_or_payload = nil)
        matcher = ProcessLepusMessage.new(:ack)
        message_or_payload ? matcher.with_message(message_or_payload) : matcher
      end
      alias_method :lepus_ack_message, :lepus_acknowledge_message

      def lepus_reject_message(message_or_payload = nil)
        matcher = ProcessLepusMessage.new(:reject)
        message_or_payload ? matcher.with_message(message_or_payload) : matcher
      end

      def lepus_requeue_message(message_or_payload = nil)
        matcher = ProcessLepusMessage.new(:requeue)
        message_or_payload ? matcher.with_message(message_or_payload) : matcher
      end

      def lepus_nack_message(message_or_payload = nil)
        matcher = ProcessLepusMessage.new(:nack)
        message_or_payload ? matcher.with_message(message_or_payload) : matcher
      end
    end
  end
end

# Include the matchers in RSpec if available
if defined?(RSpec)
  RSpec.configure do |config|
    config.include Lepus::Testing::RSpecMatchers
  end
end
