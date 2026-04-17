# frozen_string_literal: true

module Lepus
  module Prometheus
    # Hooks that run inside each Lepus process and forward metrics to the
    # prometheus_exporter server via Lepus::Prometheus.emit.
    module Instrumentation
      # Tracks per-delivery outcomes and latency.
      module HandlerExtensions
        def process_delivery(delivery_info, metadata, payload)
          start = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          result = super
          elapsed = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start
          begin
            Lepus::Prometheus.emit(
              :delivery,
              consumer: @consumer_class.name,
              queue: queue_name_for_metric,
              result: result.to_s,
              duration: elapsed
            )
          rescue
            nil
          end
          result
        end

        private

        def queue_name_for_metric
          q = queue
          q.respond_to?(:name) ? q.name : q.to_s
        rescue
          ""
        end
      end

      # Emits process-level gauges on each heartbeat tick.
      module WorkerExtensions
        def heartbeat
          super
        ensure
          Lepus::Prometheus.emit(
            :process,
            kind: kind.to_s,
            name: name,
            pid: pid,
            rss_memory: safe_rss_memory_bytes
          )
        end

        private

        def safe_rss_memory_bytes
          Lepus::Processes::MEMORY_GRABBER.call(pid) * 1024
        rescue
          0
        end
      end

      # Periodic poller that turns RabbitMQ queue stats into gauge events.
      # Runs in a single thread inside whichever process enabled it.
      class QueuePoller
        @thread = nil
        @mutex = Mutex.new

        class << self
          def start(interval:, api:)
            @mutex.synchronize do
              stop_locked
              @thread = Thread.new { run_loop(interval, api) }
            end
          end

          def stop
            @mutex.synchronize { stop_locked }
          end

          def running?
            @mutex.synchronize { !@thread.nil? && @thread.alive? }
          end

          private

          def stop_locked
            @thread&.kill
            @thread = nil
          end

          def run_loop(interval, api)
            loop do
              poll_once(api)
              sleep interval
            end
          end

          def poll_once(api)
            api.queues.each do |q|
              Lepus::Prometheus.emit(
                :queue,
                name: q[:name],
                messages: q[:messages].to_i,
                messages_ready: q[:messages_ready].to_i,
                messages_unacknowledged: q[:messages_unacknowledged].to_i,
                consumers: q[:consumers].to_i,
                memory: q[:memory].to_i
              )
            end
          rescue => e
            Lepus.logger.warn("[Lepus::Prometheus] queue poll failed: #{e.message}")
          end
        end
      end

      class << self
        def install!
          return if @installed

          Lepus::Consumers::Handler.prepend(HandlerExtensions)
          Lepus::Consumers::Worker.prepend(WorkerExtensions)
          subscribe_publish_events
          @installed = true
        end

        private

        def subscribe_publish_events
          return unless defined?(ActiveSupport::Notifications)

          ActiveSupport::Notifications.subscribe(/\Apublish\.lepus\z/) do |*args|
            event = ActiveSupport::Notifications::Event.new(*args)
            Lepus::Prometheus.emit(
              :publish,
              exchange: event.payload[:exchange].to_s,
              routing_key: event.payload[:routing_key].to_s,
              duration: event.duration / 1000.0
            )
          end
        end
      end
    end
  end
end

Lepus::Prometheus::Instrumentation.install!
