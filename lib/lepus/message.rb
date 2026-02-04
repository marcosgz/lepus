# frozen_string_literal: true

module Lepus
  class Message
    attr_reader :delivery_info, :metadata, :payload
    attr_accessor :consumer_class

    # Coerce raw Bunny objects into a Message with internal data classes.
    # This decouples the Message from Bunny-specific objects.
    # If the objects are already internal classes, they are used as-is.
    #
    # @param bunny_delivery_info [Bunny::DeliveryInfo, DeliveryInfo] The delivery info from Bunny or internal class
    # @param bunny_metadata [Bunny::MessageProperties, Metadata] The metadata from Bunny or internal class
    # @param payload [String] The raw message payload
    # @return [Message]
    def self.coerce(bunny_delivery_info, bunny_metadata, payload)
      delivery_info = if bunny_delivery_info.is_a?(DeliveryInfo)
        bunny_delivery_info
      else
        DeliveryInfo.from_bunny(bunny_delivery_info)
      end

      metadata = if bunny_metadata.is_a?(Metadata)
        bunny_metadata
      else
        Metadata.from_bunny(bunny_metadata)
      end

      channel = bunny_delivery_info.respond_to?(:channel) ? bunny_delivery_info.channel : nil

      new(delivery_info, metadata, payload, channel: channel)
    end

    def initialize(delivery_info, metadata, payload, channel: nil)
      @delivery_info = delivery_info
      @metadata = metadata
      @payload = payload
      @channel = channel
    end

    # Returns the channel associated with this message.
    # Falls back to checking out a new channel from the producer connection pool if none is set.
    # Note: The fallback channel is not memoized; each call will checkout a new channel.
    #
    # @return [Bunny::Channel, nil] The channel or nil if unavailable
    def channel
      return @channel if @channel

      checkout_channel
    end

    def mutate(payload: nil, metadata: nil, delivery_info: nil, consumer_class: nil, channel: nil)
      self.class.new(
        delivery_info || @delivery_info,
        metadata || @metadata,
        payload || @payload,
        channel: channel || @channel
      ).tap do |message|
        message.consumer_class = consumer_class || @consumer_class
      end
    end

    def to_h
      {
        delivery: delivery_info&.to_h,
        metadata: metadata&.to_h,
        payload: payload
      }
    end

    def eql?(other)
      other.is_a?(self.class) &&
        delivery_info == other.delivery_info &&
        metadata == other.metadata &&
        payload == other.payload
    end
    alias_method :==, :eql?

    private

    def checkout_channel
      Lepus.config.producer_config.with_connection do |connection|
        connection.create_channel
      end
    rescue
      nil
    end
  end
end
