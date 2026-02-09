# frozen_string_literal: true

require "json"
require "concurrent"

module Lepus
  module Web
    # Aggregates process heartbeats from RabbitMQ into in-memory state.
    # Subscribes to the lepus.heartbeat fanout exchange and maintains
    # a thread-safe cache of all processes across connected Lepus apps.
    class Aggregator
      HEARTBEAT_EXCHANGE = ProcessRegistry::RabbitmqBackend::HEARTBEAT_EXCHANGE

      attr_reader :stale_threshold

      def initialize(stale_threshold: nil)
        @stale_threshold = stale_threshold || Lepus.config.process_alive_threshold
        @processes = Concurrent::Map.new
        @connection = nil
        @channel = nil
        @consumer = nil
        @running = Concurrent::AtomicBoolean.new(false)
        @pruning_task = nil
        @mutex = Mutex.new
      end

      def start
        return if @running.true?

        @mutex.synchronize do
          return if @running.true?

          @running.make_true
          setup_subscription
          start_pruning_task
        end
      rescue => e
        Lepus.logger.error("[Web::Aggregator] Failed to start: #{e.message}")
        @running.make_false
      end

      def stop
        @mutex.synchronize do
          @running.make_false
          @pruning_task&.shutdown
          @consumer&.cancel if @consumer
          @channel&.close if @channel&.open?
          @connection&.close if @connection&.open?
        end
      rescue => e
        Lepus.logger.warn("[Web::Aggregator] Error during shutdown: #{e.message}")
      ensure
        @pruning_task = nil
        @consumer = nil
        @channel = nil
        @connection = nil
      end

      def running?
        @running.true?
      end

      def all_processes
        prune_stale_entries
        @processes.values.map { |data| data[:process] }
      end

      def find(id)
        @processes[id]&.dig(:process)
      end

      def count
        @processes.size
      end

      def clear
        @processes.clear
      end

      private

      def setup_subscription
        @connection = Lepus.config.create_connection(suffix: "(web-aggregator)")
        @channel = @connection.create_channel

        exchange = @channel.fanout(
          HEARTBEAT_EXCHANGE,
          durable: false,
          auto_delete: false
        )

        queue = @channel.queue("", exclusive: true, auto_delete: true)
        queue.bind(exchange)

        @consumer = queue.subscribe do |_delivery_info, _metadata, payload|
          handle_message(payload)
        end
      end

      def handle_message(payload)
        data = JSON.parse(payload, symbolize_names: true)

        case data[:type]
        when "heartbeat"
          process_heartbeat(data)
        when "deregister"
          process_deregistration(data)
        end
      rescue => e
        Lepus.logger.warn("[Web::Aggregator] Failed to handle message: #{e.message}")
      end

      def process_heartbeat(data)
        process_data = data[:process]
        return unless process_data && process_data[:id]

        @processes[process_data[:id]] = {
          process: process_data.merge(metrics: data[:metrics] || {}),
          received_at: Time.now
        }
      end

      def process_deregistration(data)
        process_id = data[:process_id]
        @processes.delete(process_id) if process_id
      end

      def start_pruning_task
        @pruning_task = Concurrent::TimerTask.new(
          execution_interval: [@stale_threshold / 2, 30].min
        ) do
          prune_stale_entries
        end

        @pruning_task.execute
      end

      def prune_stale_entries
        threshold = Time.now - @stale_threshold
        @processes.each do |id, data|
          @processes.delete(id) if data[:received_at] < threshold
        end
      end
    end
  end
end
