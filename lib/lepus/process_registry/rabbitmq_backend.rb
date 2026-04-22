# frozen_string_literal: true

require "json"
require "timeout"

module Lepus
  class ProcessRegistry
    # RabbitMQ-based backend for process registry.
    # Publishes heartbeats to a fanout exchange for web dashboard aggregation.
    # Also writes locally via FileBackend for local queries when aggregator is unavailable.
    class RabbitmqBackend
      include Backend

      HEARTBEAT_EXCHANGE = "lepus.heartbeat"

      attr_reader :fallback

      def initialize(fallback: nil)
        @fallback = fallback || FileBackend.new
        @connection = nil
        @channel = nil
        @exchange = nil
        @mutex = Mutex.new
      end

      def start
        @fallback.start
        setup_channel_and_exchange
      end

      def stop
        @fallback.stop
        close_channel
      end

      def add(process, metrics: {})
        @fallback.add(process)
        publish_heartbeat(process, metrics: metrics)
      end

      def delete(process)
        @fallback.delete(process)
        publish_deregister(process)
      end

      def find(id)
        @fallback.find(id)
      end

      def exists?(id)
        @fallback.exists?(id)
      end

      def all
        @fallback.all
      end

      def count
        @fallback.count
      end

      def clear
        @fallback.clear
      end

      def path
        @fallback.path
      end

      private

      def setup_channel_and_exchange
        return unless rabbitmq_available?

        @mutex.synchronize do
          return if @channel&.open?

          @connection = Lepus.config.create_connection(suffix: "(registry)")
          @channel = @connection.create_channel
          @exchange = @channel.fanout(
            HEARTBEAT_EXCHANGE,
            durable: false,
            auto_delete: false
          )
        end
      rescue => e
        Lepus.logger.warn("[ProcessRegistry] Failed to setup RabbitMQ channel: #{e.message}")
        @connection = nil
        @channel = nil
        @exchange = nil
      end

      # Tear down the dedicated registry connection on supervisor shutdown.
      # Bunny's graceful close waits up to 15s per channel for a broker
      # `close-ok` continuation; during forked supervisor shutdown the broker
      # sometimes never replies and SIGTERM handling blows past its 10s budget,
      # timing out the integration specs. We bound the graceful attempt at 2s
      # and fall back to closing the socket directly so the process can exit.
      CLOSE_TIMEOUT = 2

      def close_channel
        @mutex.synchronize do
          force_close_connection if @connection
        end
      ensure
        @connection = nil
        @channel = nil
        @exchange = nil
      end

      def force_close_connection
        Timeout.timeout(CLOSE_TIMEOUT) { @connection.close(false) } if @connection.open?
      rescue => e
        Lepus.logger.warn("[ProcessRegistry] Failed to close RabbitMQ connection: #{e.message}")
        begin
          @connection.instance_variable_get(:@transport)&.close
        rescue
          nil
        end
      end

      def publish_heartbeat(process, metrics: {})
        return unless @exchange

        message = MessageBuilder.new(process, metrics: metrics)
        @exchange.publish(
          message.to_json,
          content_type: "application/json"
        )
      rescue => e
        Lepus.logger.warn("[ProcessRegistry] Failed to publish heartbeat: #{e.message}")
      end

      def publish_deregister(process)
        return unless @exchange

        message = MessageBuilder.new(process).build_deregister
        @exchange.publish(
          JSON.generate(message),
          content_type: "application/json"
        )
      rescue => e
        Lepus.logger.warn("[ProcessRegistry] Failed to publish deregister: #{e.message}")
      end

      def rabbitmq_available?
        Lepus.config.rabbitmq_url.present?
      rescue
        true
      end
    end
  end
end
