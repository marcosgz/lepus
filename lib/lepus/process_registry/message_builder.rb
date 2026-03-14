# frozen_string_literal: true

require "json"

module Lepus
  class ProcessRegistry
    # Builds heartbeat messages for RabbitMQ publishing.
    class MessageBuilder
      VERSION = "1.0"

      def initialize(process, metrics: {})
        @process = process
        @metrics = metrics
      end

      def build_heartbeat
        {
          type: "heartbeat",
          version: VERSION,
          process: process_data,
          metrics: metrics_data
        }
      end

      def build_deregister
        {
          type: "deregister",
          version: VERSION,
          process_id: @process.id,
          timestamp: Time.now.iso8601(6)
        }
      end

      def to_json
        JSON.generate(build_heartbeat)
      end

      private

      def process_data
        {
          id: @process.id,
          name: @process.name,
          pid: @process.pid,
          hostname: @process.hostname,
          kind: @process.kind,
          supervisor_id: @process.supervisor_id,
          application: Lepus.config.application_name,
          last_heartbeat_at: format_time(@process.last_heartbeat_at)
        }
      end

      def metrics_data
        {
          rss_memory: @metrics[:rss_memory] || safe_rss_memory,
          connections: @metrics[:connections] || 0,
          consumers: @metrics[:consumers] || []
        }
      end

      def safe_rss_memory
        @process.rss_memory * 1024 # Convert kB to bytes (MEMORY_GRABBER returns kB)
      rescue
        0
      end

      def format_time(time)
        time&.iso8601(6)
      end
    end
  end
end
