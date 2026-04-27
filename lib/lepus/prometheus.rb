# frozen_string_literal: true

require "prometheus_exporter"
require "prometheus_exporter/client"

require_relative "prometheus/instrumentation"

module Lepus
  # Optional integration with the prometheus_exporter gem.
  # Require "lepus/prometheus" in your Lepus process to start shipping
  # metrics to a running prometheus_exporter server via the default client.
  #
  # On the prometheus_exporter server side, load the companion collector:
  #   prometheus_exporter -a lepus/prometheus/collector
  module Prometheus
    DEFAULT_QUEUE_POLL_INTERVAL = 30

    class << self
      attr_writer :client

      def client
        @client ||= ::PrometheusExporter::Client.default
      end

      # Emit an opaque metric payload to the exporter server.
      # Silently swallows transport errors so instrumentation cannot
      # break the caller; non-transport bugs surface as debug logs.
      def emit(metric, **data)
        client.send_json(type: "lepus", metric: metric.to_s, **data)
      rescue => e
        Lepus.logger.debug { "[Lepus::Prometheus] emit(#{metric}) failed: #{e.class}: #{e.message}" }
        nil
      end

      # Start polling the RabbitMQ management API for queue-level gauges.
      # Safe to call once per process. Requires "lepus/web/management_api".
      def watch_queues(interval: DEFAULT_QUEUE_POLL_INTERVAL, api: nil)
        require "lepus/web/management_api"
        api ||= Lepus::Web::ManagementAPI.new
        Instrumentation::QueuePoller.start(interval: interval, api: api)
      end

      def stop_watching_queues
        Instrumentation::QueuePoller.stop
      end
    end
  end
end
