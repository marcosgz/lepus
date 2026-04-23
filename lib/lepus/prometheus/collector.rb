# frozen_string_literal: true

# This file is intended to be loaded by the prometheus_exporter server:
#
#   prometheus_exporter -a lepus/prometheus/collector
#
# It intentionally avoids requiring the rest of the Lepus gem so it can
# run standalone inside the exporter process. When Lepus is loaded in the
# same process, latency buckets fall back to Lepus.config.prometheus_buckets.

require "prometheus_exporter"
require "prometheus_exporter/server"

module Lepus
  module Prometheus
    class Collector < ::PrometheusExporter::Server::TypeCollector
      DEFAULT_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10].freeze

      def initialize
        @metrics = {}
      end

      def type
        "lepus"
      end

      def metrics
        @metrics.values
      end

      def collect(obj)
        case obj["metric"]
        when "delivery" then collect_delivery(obj)
        when "publish" then collect_publish(obj)
        when "process" then collect_process(obj)
        when "process_info" then collect_process_info(obj)
        when "queue" then collect_queue(obj)
        when "queue_poll" then collect_queue_poll(obj)
        when "queue_poll_error" then collect_queue_poll_error(obj)
        end
      end

      private

      def collect_delivery(obj)
        labels = {
          consumer: obj["consumer"],
          queue: obj["queue"],
          result: obj["result"],
          error: obj["error"].to_s
        }
        counter(
          "lepus_messages_processed_total",
          "Total messages delivered to Lepus consumers, labeled by result and error class."
        ).observe(1, labels)

        duration = obj["duration"].to_f
        histogram(
          "lepus_delivery_duration_seconds",
          "Time spent processing a single Lepus message.",
          buckets
        ).observe(duration, consumer: obj["consumer"], queue: obj["queue"])
      end

      def collect_publish(obj)
        counter(
          "lepus_messages_published_total",
          "Total messages published through Lepus producers."
        ).observe(1, exchange: obj["exchange"], routing_key: obj["routing_key"])

        duration = obj["duration"].to_f
        histogram(
          "lepus_publish_duration_seconds",
          "Time spent publishing a single Lepus message.",
          buckets
        ).observe(duration, exchange: obj["exchange"], routing_key: obj["routing_key"])
      end

      def collect_process(obj)
        labels = {kind: obj["kind"], name: obj["name"]}
        gauge(
          "lepus_process_rss_memory_bytes",
          "Resident-set memory of a Lepus process."
        ).observe(obj["rss_memory"].to_f, labels)
      end

      def collect_process_info(obj)
        labels = {
          kind: obj["kind"],
          name: obj["name"],
          pid: obj["pid"].to_s,
          hostname: obj["hostname"].to_s
        }
        gauge(
          "lepus_process_info",
          "Info gauge for a Lepus process (always 1); use for joining pid/hostname labels."
        ).observe(1, labels)
      end

      def collect_queue(obj)
        labels = {name: obj["name"]}
        gauge("lepus_queue_messages", "Total messages in a RabbitMQ queue.")
          .observe(obj["messages"].to_f, labels)
        gauge("lepus_queue_messages_ready", "Messages ready for delivery in a RabbitMQ queue.")
          .observe(obj["messages_ready"].to_f, labels)
        gauge("lepus_queue_messages_unacknowledged", "Unacknowledged messages in a RabbitMQ queue.")
          .observe(obj["messages_unacknowledged"].to_f, labels)
        gauge("lepus_queue_consumers", "Number of consumers attached to a RabbitMQ queue.")
          .observe(obj["consumers"].to_f, labels)
        gauge("lepus_queue_memory_bytes", "Memory used by a RabbitMQ queue.")
          .observe(obj["memory"].to_f, labels)
      end

      def collect_queue_poll(obj)
        gauge(
          "lepus_queue_poll_last_success_timestamp_seconds",
          "Unix timestamp of the last successful RabbitMQ management API poll."
        ).observe(obj["timestamp"].to_f, {})
      end

      def collect_queue_poll_error(obj)
        counter(
          "lepus_queue_poll_errors_total",
          "Total errors encountered while polling the RabbitMQ management API, labeled by error class."
        ).observe(1, error: obj["error"].to_s)
      end

      def counter(name, help)
        @metrics[name] ||= ::PrometheusExporter::Metric::Counter.new(name, help)
      end

      def gauge(name, help)
        @metrics[name] ||= ::PrometheusExporter::Metric::Gauge.new(name, help)
      end

      def histogram(name, help, buckets)
        @metrics[name] ||= ::PrometheusExporter::Metric::Histogram.new(name, help, buckets: buckets)
      end

      def buckets
        if defined?(::Lepus) && ::Lepus.respond_to?(:config) && ::Lepus.config.respond_to?(:prometheus_buckets)
          ::Lepus.config.prometheus_buckets
        else
          DEFAULT_BUCKETS
        end
      end
    end
  end
end
