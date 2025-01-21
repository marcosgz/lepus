# frozen_string_literal: true

module Lepus
  class Producer
    DEFAULT_EXCHANGE_OPTIONS = {
      type: :topic,
      durable: true,
      auto_delete: false
    }.freeze

    DEFAULT_PUBLISH_OPTIONS = {
      expiration: 7 * (60 * 60 * 24)
    }.freeze

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

      bunny.with_channel do |channel|
        exchange = channel.exchange(@exchange_name, @exchange_options)
        exchange.publish(
          payload,
          DEFAULT_PUBLISH_OPTIONS.merge(options)
        )
      end
    end

    def bunny
      Thread.current[:lepus_bunny] ||= Lepus.config.create_connection(suffix: "producer")
    end
  end
end
