# frozen_string_literal: true

require "concurrent"

module Lepus
  module Consumers
    # Thread-safe per-consumer-class statistics tracker.
    # Uses atomic counters to track processed/rejected/errored/delayed message counts.
    class Stats
      attr_reader :consumer_class

      def initialize(consumer_class)
        @consumer_class = consumer_class
        @processed = Concurrent::AtomicFixnum.new(0)
        @rejected = Concurrent::AtomicFixnum.new(0)
        @errored = Concurrent::AtomicFixnum.new(0)
        @delayed = Concurrent::AtomicFixnum.new(0)
      end

      def record_processed
        @processed.increment
      end

      def record_rejected
        @rejected.increment
      end

      def record_errored
        @errored.increment
      end

      def record_delayed
        @delayed.increment
      end

      def processed
        @processed.value
      end

      def rejected
        @rejected.value
      end

      def errored
        @errored.value
      end

      def delayed
        @delayed.value
      end

      def to_h
        config = consumer_class.config
        {
          class_name: consumer_class.name,
          exchange: config.exchange_name,
          queue: config.queue_name,
          route: extract_route(config),
          retry_queue: (config.retry_queue_name if config.retry_queue_args),
          error_queue: (config.error_queue_name if config.error_queue_args),
          threads: config.worker_threads,
          processed: @processed.value,
          rejected: @rejected.value,
          errored: @errored.value,
          delayed: @delayed.value,
          delays: config.delay_values
        }
      end

      private

      def extract_route(config)
        binds = config.binds_args
        return nil if binds.empty?

        keys = binds.filter_map { |b| b[:routing_key] }
        return nil if keys.empty?

        (keys.length == 1) ? keys.first : keys
      end
    end
  end
end
