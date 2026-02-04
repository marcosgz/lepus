# frozen_string_literal: true

module Lepus
  class Message
    # Internal data class representing delivery information.
    # Provides the same interface as Bunny::DeliveryInfo (duck typing).
    class DeliveryInfo
      KNOWN_ATTRIBUTES = %i[delivery_tag redelivered exchange routing_key consumer_tag].freeze

      attr_reader *KNOWN_ATTRIBUTES

      def self.from_bunny(bunny_delivery_info)
        new(
          delivery_tag: bunny_delivery_info.delivery_tag,
          redelivered: bunny_delivery_info.redelivered,
          exchange: bunny_delivery_info.exchange,
          routing_key: bunny_delivery_info.routing_key,
          consumer_tag: bunny_delivery_info.consumer_tag
        )
      end

      def initialize(**attrs)
        @delivery_tag = attrs[:delivery_tag]
        @redelivered = attrs.fetch(:redelivered, false)
        @exchange = attrs[:exchange]
        @routing_key = attrs[:routing_key]
        @consumer_tag = attrs[:consumer_tag]
        @extra_attributes = attrs.reject { |k, _| KNOWN_ATTRIBUTES.include?(k) }
      end

      def to_h
        {
          delivery_tag: delivery_tag,
          redelivered: redelivered,
          exchange: exchange,
          routing_key: routing_key,
          consumer_tag: consumer_tag
        }.merge(@extra_attributes)
      end

      # Hash-style access to properties (compatible with Bunny::DeliveryInfo)
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

        delivery_tag == other.delivery_tag &&
          redelivered == other.redelivered &&
          exchange == other.exchange &&
          routing_key == other.routing_key &&
          consumer_tag == other.consumer_tag
      end
      alias_method :==, :eql?
    end
  end
end
