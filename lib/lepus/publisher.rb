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
      persistent: true
    }.freeze

    # @param exchange_name [String] The name of the exchange to publish messages to.
    # @param connection [Symbol, String] The named connection to publish through.
    # @param options [Hash] Additional options for the exchange (type, durable, auto_delete).
    # @return [void]
    def initialize(exchange_name, connection: Lepus::Configuration::DEFAULT_CONNECTION, **options)
      @exchange_name = exchange_name
      @connection = (connection || Lepus::Configuration::DEFAULT_CONNECTION).to_sym
      @exchange_options = DEFAULT_EXCHANGE_OPTIONS.merge(options)
    end

    # @return [Symbol] the named connection this publisher uses
    attr_reader :connection

    # @param message [String, Hash] The message to publish.
    # @param options [Hash] Publish options. Accepts +delay:+ in milliseconds (or anything responding
    #   to +in_milliseconds+) to deliver the message later. On the default exchange the +routing_key+
    #   is the queue that receives the delayed message.
    # @return [void]
    def publish(message, **options)
      return unless Producers.exchange_enabled?(exchange_name)

      Lepus.config.producer_config.with_connection(connection) do |connection|
        connection.with_channel do |channel|
          channel_publish(channel, message, **options)
        end
      end
    end

    # @param [Bunny::Channel] channel The channel to publish the message to.
    # @param [String, Hash] message The message to publish.
    # @param [Hash] options Additional options for the publish.
    # @return [void]
    def channel_publish(channel, message, delay: nil, **options)
      raise ArgumentError, "channel is required" unless channel
      return unless Producers.exchange_enabled?(exchange_name)

      delay = Delay.normalize(delay) if delay
      payload, opts = prepare_message(message, **options)
      exchange = channel.exchange(exchange_name, exchange_options)
      Lepus.instrument(:publish, exchange: exchange_name, routing_key: opts[:routing_key], delay: delay) do
        if delay
          delayed_publish(channel, payload, delay, opts)
        else
          exchange.publish(payload, opts)
        end
      end
    end

    private

    attr_reader :exchange_name, :exchange_options

    def delayed_publish(channel, payload, delay, opts)
      opts = opts.dup
      routing_key = opts.delete(:routing_key)

      if exchange_name == Delay::DEFAULT_EXCHANGE
        raise ArgumentError, "routing_key (the target queue) is required to delay through the default exchange" unless routing_key

        delay_queue = Delay.declare_for_queue!(channel, routing_key, delay)
        channel.basic_publish(payload, Delay::DEFAULT_EXCHANGE, delay_queue, opts)
      else
        delayed_exchange = Delay.declare_for_exchange!(channel, exchange_name, delay)
        opts[:headers] = (opts[:headers] || {}).merge(Delay::HEADER => delay)
        channel.basic_publish(payload, delayed_exchange, routing_key, opts)
      end
    end

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
