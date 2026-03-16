# frozen_string_literal: true

require "concurrent"

module Lepus
  module Consumers
    # Per-worker registry of consumer stats.
    # Uses Concurrent::Map for thread-safe lazy initialization.
    class StatsRegistry
      def initialize
        @stats = Concurrent::Map.new
      end

      def for(consumer_class)
        @stats.compute_if_absent(consumer_class.name) do
          Stats.new(consumer_class)
        end
      end

      def all
        @stats.values.map(&:to_h)
      end

      def connection_count
        @stats.size
      end
    end
  end
end
