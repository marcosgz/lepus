# frozen_string_literal: true

require "rack"
require "multi_json"
require "pathname"

module Lepus
  module Web
    # Web-specific configuration extensions.
    # Only activated when lepus/web is explicitly required.
    module ConfigExtensions
      attr_accessor :web_show_all_exchanges

      def initialize(*)
        super
        @web_show_all_exchanges = false
      end
    end

    # Web-specific consumer extensions.
    # Tracks whether the last delivery resulted in an error (exception),
    # allowing stats to distinguish explicit rejections from error rejections.
    module ConsumerExtensions
      def process_delivery(delivery_info, metadata, payload)
        @_last_delivery_errored = false
        super
      end

      def last_delivery_errored?
        @_last_delivery_errored == true
      end

      private

      def on_delivery_error
        @_last_delivery_errored = true
        super
      end
    end

    # Web-specific handler extensions.
    # Adds per-consumer stats recording on message delivery outcomes.
    module HandlerExtensions
      attr_accessor :stats

      def process_delivery(delivery_info, metadata, payload)
        super.tap { |result| record_stats(result) }
      end

      private

      def record_stats(result)
        return unless stats

        case result
        when :ack
          stats.record_processed
        when :reject, :nack, :requeue
          if consumer.last_delivery_errored?
            stats.record_errored
          else
            stats.record_rejected
          end
        end
      rescue # rubocop:disable Lint/SuppressedException
        # Never let stats recording interfere with message processing
      end
    end

    # Web-specific worker extensions.
    # Creates per-worker stats registry, collects metrics, and
    # overrides heartbeat to include metrics data in heartbeat messages.
    module WorkerExtensions
      private

      def setup_consumers!
        @stats_registry = Lepus::Consumers::StatsRegistry.new
        super
      end

      def build_handler(consumer_class, channel, queue, tag)
        super.tap do |handler|
          handler.stats = @stats_registry.for(consumer_class)
        end
      end

      def heartbeat
        process.heartbeat(metrics: metrics_data)
      rescue Process::NotFoundError
        self.process = nil
        interrupt
      end

      def metrics_data
        {
          rss_memory: safe_rss_memory,
          connections: connection_pool_size,
          consumers: @stats_registry&.all || []
        }
      end

      def safe_rss_memory
        Processes::MEMORY_GRABBER.call(pid) * 1024 # Convert kB to bytes
      rescue
        0
      end

      def connection_pool_size
        @connection_pool&.size || 0
      end
    end

    # Extend core classes with web-specific behavior when loaded
    Lepus::Configuration.prepend(ConfigExtensions)
    Lepus::Consumer.prepend(ConsumerExtensions)
    Lepus::Consumers::Handler.prepend(HandlerExtensions)
    Lepus::Consumers::Worker.prepend(WorkerExtensions)

    class << self
      attr_accessor :aggregator
      attr_accessor :management_api
    end

    def self.assets_path
      @assets_path ||= Pathname.new(File.expand_path("../../", __dir__)).join("web")
    end

    def self.start_aggregator
      return if aggregator&.running?

      self.aggregator = Aggregator.new
      aggregator.start
    end

    def self.stop_aggregator
      aggregator&.stop
      self.aggregator = nil
    end

    def self.start_management_api
      self.management_api = Lepus.config.build_management_api
    end

    def self.stop_management_api
      self.management_api = nil
    end

    # Start all web services (aggregator and management API)
    def self.start
      start_aggregator
      start_management_api
    end

    # Stop all web services
    def self.stop
      stop_aggregator
      stop_management_api
    end

    def self.render_index(env)
      base = base_path(env)
      html = File.read(assets_path.join("index.html"))
      html.gsub("__BASE_PATH__", base)
    end

    def self.base_path(env)
      script_name = env["SCRIPT_NAME"].to_s
      script_name = script_name.chomp("/")
      "#{script_name}/"
    end

    def self.mime_for(path)
      case File.extname(path)
      when ".html" then "text/html"
      when ".css" then "text/css"
      when ".js" then "application/javascript"
      when ".png" then "image/png"
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".svg" then "image/svg+xml"
      when ".woff", ".woff2" then "font/woff"
      when ".ttf" then "font/ttf"
      when ".eot" then "application/vnd.ms-fontobject"
      else "application/octet-stream"
      end
    end

    # Make the Web module directly mountable as a Rack application
    def self.call(env)
      App.build.call(env)
    end
  end
end

# Require web sub-files (not managed by Zeitwerk)
require_relative "web/respond_with"
require_relative "web/management_api"
require_relative "web/aggregator"
require_relative "web/api"
require_relative "web/app"
