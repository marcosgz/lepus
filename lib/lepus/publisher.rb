# frozen_string_literal: true

require "multi_json"

module Lepus
  class Publisher
    DEFAULT_EXCHANGE_OPTIONS = {
      type: :topic,
      durable: true,
      auto_delete: false
    }.freeze

    # @param exchange_name [String] The name of the exchange to publish messages to.
    # @param options [Hash] Additional options for the exchange (type, durable, auto_delete).
    def initialize(exchange_name, **options)
      @exchange_name = exchange_name
      @exchange_options = DEFAULT_EXCHANGE_OPTIONS.merge(options)
    end

    def publish(message, **options)
      payload = if message.is_a?(String)
        options[:content_type] ||= "text/plain"
        message
      else
        options[:content_type] ||= "application/json"
        MultiJson.dump(message)
      end

      Lepus.config.producer_config.with_connection do |connection|
        connection.with_channel do |channel|
          exchange = channel.exchange(@exchange_name, @exchange_options)
          exchange.publish(
            payload,
            options
          )
        end
      end
    end
  end
end
