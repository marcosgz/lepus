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

        def matches?(block)
          @messages_before = count_all_messages
          block.call
          @messages_after = count_all_messages
          @published_count = @messages_after - @messages_before

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
          recent_messages.any? { |msg| @expected_payload.matches?(msg[:payload]) }
        end

        def count_all_messages
          Lepus::Testing::Exchange.all.values.sum(&:size)
        end

        def get_recent_messages(count)
          all_messages = []
          Lepus::Testing::Exchange.all.each_value do |exchange|
            all_messages.concat(exchange.messages)
          end
          # Sort by timestamp and get the most recent messages
          all_messages.sort_by { |msg| msg[:timestamp] }.last(count)
        end
      end

      # Main matcher method
      def publish_lepus_message(expected_count = nil)
        PublishLepusMessage.new(expected_count)
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
