# frozen_string_literal: true

require "json"

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

      # Tear down the dedicated registry connection. We close the channel and
      # the underlying `Bunny::Session` independently and swallow errors on
      # each — `channel.close` can hang or raise if the broker is mid-recovery
      # (we've seen CHANNEL_ERRORs during forked supervisor shutdown), but the
      # session still owns a reader thread that must be closed or the process
      # won't exit. We always attempt the session close even if the channel
      # close failed.
      def close_channel
        @mutex.synchronize do
          safe_close(@channel, "channel") if @channel&.open?
          safe_close(@connection, "connection") if @connection&.open?
        end
      ensure
        @connection = nil
        @channel = nil
        @exchange = nil
      end

      def safe_close(obj, label)
        obj.close
      rescue => e
        Lepus.logger.warn("[ProcessRegistry] Failed to close RabbitMQ #{label}: #{e.message}")
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
