# frozen_string_literal: true

module Lepus
  class Message
    # Internal data class representing message metadata/properties.
    # Provides the same interface as Bunny::MessageProperties (duck typing).
    class Metadata
      KNOWN_ATTRIBUTES = %i[
        content_type content_encoding headers delivery_mode priority
        correlation_id reply_to expiration message_id timestamp
        type user_id app_id cluster_id
      ].freeze

      attr_reader *KNOWN_ATTRIBUTES

      def self.from_bunny(bunny_metadata)
        new(
          content_type: bunny_metadata.content_type,
          content_encoding: bunny_metadata.content_encoding,
          headers: bunny_metadata.headers,
          delivery_mode: bunny_metadata.delivery_mode,
          priority: bunny_metadata.priority,
          correlation_id: bunny_metadata.correlation_id,
          reply_to: bunny_metadata.reply_to,
          expiration: bunny_metadata.expiration,
          message_id: bunny_metadata.message_id,
          timestamp: bunny_metadata.timestamp,
          type: bunny_metadata.type,
          user_id: bunny_metadata.user_id,
          app_id: bunny_metadata.app_id,
          cluster_id: bunny_metadata.cluster_id
        )
      end

      def initialize(**attrs)
        @content_type = attrs[:content_type]
        @content_encoding = attrs[:content_encoding]
        @headers = attrs[:headers]
        @delivery_mode = attrs[:delivery_mode]
        @priority = attrs[:priority]
        @correlation_id = attrs[:correlation_id]
        @reply_to = attrs[:reply_to]
        @expiration = attrs[:expiration]
        @message_id = attrs[:message_id]
        @timestamp = attrs[:timestamp]
        @type = attrs[:type]
        @user_id = attrs[:user_id]
        @app_id = attrs[:app_id]
        @cluster_id = attrs[:cluster_id]
        @extra_attributes = attrs.reject { |k, _| KNOWN_ATTRIBUTES.include?(k) }
      end

      def to_h
        {
          content_type: content_type,
          content_encoding: content_encoding,
          headers: headers,
          delivery_mode: delivery_mode,
          priority: priority,
          correlation_id: correlation_id,
          reply_to: reply_to,
          expiration: expiration,
          message_id: message_id,
          timestamp: timestamp,
          type: type,
          user_id: user_id,
          app_id: app_id,
          cluster_id: cluster_id
        }.merge(@extra_attributes)
      end

      # Hash-style access to properties (compatible with Bunny::MessageProperties)
      # @param key [Symbol, String] The property name
      # @return [Object, nil] The property value
      def [](key)
        to_h[key.to_sym]
      end

      # Support dynamic attribute access for compatibility
      def method_missing(method_name, *args)
        return super if method_name.to_s.end_with?("=")
        return super if args.any?

        self[method_name]
      end

      def respond_to_missing?(method_name, include_private = false)
        !method_name.to_s.end_with?("=") || super
      end

      def eql?(other)
        return false unless other.is_a?(self.class)

        to_h == other.to_h
      end
      alias_method :==, :eql?
    end
  end
end
