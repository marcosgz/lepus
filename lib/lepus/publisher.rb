# frozen_string_literal: true

require "multi_json"

module Lepus
  class Publisher
    DEFAULT_EXCHANGE_OPTIONS = {
      type: :topic,
      durable: true,
      auto_delete: false
    }.freeze

    DEFAULT_PUBLISH_OPTIONS = {
      persistent: true,
    }.freeze

    # @param exchange_name [String] The name of the exchange to publish messages to.
    # @param options [Hash] Additional options for the exchange (type, durable, auto_delete).
    # @return [void]
    def initialize(exchange_name, **options)
      @exchange_name = exchange_name
      @exchange_options = DEFAULT_EXCHANGE_OPTIONS.merge(options)
    end

    def publish(message, **options)
      return unless Producers.exchange_enabled?(exchange_name)

      Lepus.config.producer_config.with_connection do |connection|
        connection.with_channel do |channel|
          channel_publish(channel, message, **options)
        end
      end
    end

    # @param [Bunny::Channel] channel The channel to publish the message to.
    # @param [String, Hash] message The message to publish.
    # @param [Hash] options Additional options for the publish.
    # @return [void]
    def channel_publish(channel, message, **options)
      raise ArgumentError, "channel is required" unless channel
      return unless Producers.exchange_enabled?(exchange_name)

      payload, opts = prepare_message(message, **options)
      exchange = channel.exchange(exchange_name, exchange_options)
      exchange.publish(payload, opts)
    end

    private

    attr_reader :exchange_name, :exchange_options

    def prepare_message(message, **options)
      opts = DEFAULT_PUBLISH_OPTIONS.merge(options)
      payload = if message.is_a?(String)
        opts[:content_type] ||= "text/plain"
        message
      else
        opts[:content_type] ||= "application/json"
        MultiJson.dump(message)
      end

      [payload, opts]
    end
  end
end
