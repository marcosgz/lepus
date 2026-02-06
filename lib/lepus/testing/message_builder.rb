# frozen_string_literal: true

module Lepus
  module Testing
    # Builder class for creating test messages with realistic Bunny objects
    class MessageBuilder
      def initialize
        @delivery_info_attrs = {
          delivery_tag: 1,
          redelivered: false,
          exchange: "test_exchange",
          routing_key: "test.routing.key",
          consumer_tag: "test_consumer_tag"
        }
        @metadata_attrs = {
          content_type: "application/json",
          content_encoding: "utf-8",
          headers: {},
          delivery_mode: 2,
          priority: 0,
          correlation_id: nil,
          reply_to: nil,
          expiration: nil,
          message_id: SecureRandom.uuid,
          timestamp: Time.now.to_i,
          type: nil,
          user_id: nil,
          app_id: nil,
          cluster_id: nil
        }
        @payload = nil
        @channel = nil
      end

      # Set the message payload
      def with_payload(payload)
        if payload.is_a?(Hash) || payload.is_a?(Array)
          payload = MultiJson.dump(payload)
          @metadata_attrs[:content_type] ||= "application/json"
        end

        @payload = payload
        self
      end

      # Set delivery tag
      def with_delivery_tag(tag)
        @delivery_info_attrs[:delivery_tag] = tag
        self
      end

      # Set routing key
      def with_routing_key(routing_key)
        @delivery_info_attrs[:routing_key] = routing_key
        self
      end

      # Set exchange name
      def with_exchange(exchange)
        @delivery_info_attrs[:exchange] = exchange
        self
      end

      # Set consumer tag
      def with_consumer_tag(consumer_tag)
        @delivery_info_attrs[:consumer_tag] = consumer_tag
        self
      end

      # Set redelivered flag
      def with_redelivered(redelivered = true)
        @delivery_info_attrs[:redelivered] = redelivered
        self
      end

      # Set content type
      def with_content_type(content_type)
        @metadata_attrs[:content_type] = content_type
        self
      end

      # Set headers
      def with_headers(headers)
        @metadata_attrs[:headers] = headers
        self
      end

      # Set correlation ID
      def with_correlation_id(correlation_id)
        @metadata_attrs[:correlation_id] = correlation_id
        self
      end

      # Set reply to queue
      def with_reply_to(reply_to)
        @metadata_attrs[:reply_to] = reply_to
        self
      end

      # Set message expiration
      def with_expiration(expiration)
        @metadata_attrs[:expiration] = expiration
        self
      end

      # Set message ID
      def with_message_id(message_id)
        @metadata_attrs[:message_id] = message_id
        self
      end

      # Set timestamp
      def with_timestamp(timestamp)
        @metadata_attrs[:timestamp] = timestamp
        self
      end

      # Set message type
      def with_type(type)
        @metadata_attrs[:type] = type
        self
      end

      # Set user ID
      def with_user_id(user_id)
        @metadata_attrs[:user_id] = user_id
        self
      end

      # Set app ID
      def with_app_id(app_id)
        @metadata_attrs[:app_id] = app_id
        self
      end

      # Set delivery mode (1 = non-persistent, 2 = persistent)
      def with_delivery_mode(mode)
        @metadata_attrs[:delivery_mode] = mode
        self
      end

      # Set priority
      def with_priority(priority)
        @metadata_attrs[:priority] = priority
        self
      end

      # Set custom delivery info attributes
      def with_delivery_info_attrs(attrs)
        @delivery_info_attrs.merge!(attrs)
        self
      end

      # Set custom metadata attributes
      def with_metadata_attrs(attrs)
        @metadata_attrs.merge!(attrs)
        self
      end

      # Set the channel (for middlewares that need it)
      def with_channel(channel)
        @channel = channel
        self
      end

      # Build the Lepus::Message using internal data classes
      def build
        raise ArgumentError, "Payload is required" if @payload.nil?

        delivery_info = Lepus::Message::DeliveryInfo.new(**@delivery_info_attrs)
        metadata = Lepus::Message::Metadata.new(**@metadata_attrs)

        Lepus::Message.new(delivery_info, metadata, @payload, channel: @channel)
      end
    end
  end
end
