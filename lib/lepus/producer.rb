# frozen_string_literal: true

module Lepus
  class Producer
    DEFAULT_EXCHANGE_OPTIONS = {
      type: :topic,
      durable: true,
      auto_delete: false
    }.freeze

    # @param exchange_name [String] The name of the exchange to publish messages to.
    # @param connection [Bunny::Session] The Bunny connection to use.
    # @param options [Hash] Additional options for the exchange (type, durable, auto_delete).
    def initialize(exchange_name, connection:, **options)
      @connection = connection
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
