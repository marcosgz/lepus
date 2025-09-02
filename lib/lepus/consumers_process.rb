# frozen_string_literal: true

require "forwardable"

module Lepus
  class ConsumersProcess < Processes::Base
    include Processes::Runnable

    extend Forwardable
    def_delegators :definer, :name, :consumers

    attr_reader :definer

    def initialize(definer, **options)
      @definer = definer

      super(**options)
    end

    def metadata
      super.merge(name: name, consumers: consumers.map(&:to_s))
    end

    def kind
      "consumer-#{name}"
    end

    # def before_fork
    #   return unless @consumer_class.respond_to?(:before_fork, true)

    #   @consumer_class.send(:before_fork)
    # end

    # def after_fork
    #   return unless @consumer_class.respond_to?(:after_fork, true)

    #   @consumer_class.send(:after_fork)
    # end

    private

    SLEEP_INTERVAL = 5

    def run
      wrap_in_app_executor do
        setup_consumers!
      end

      loop do
        break if shutting_down?

        wrap_in_app_executor do
          interruptible_sleep(SLEEP_INTERVAL)
        end
      end
    ensure
      Lepus.instrument(:shutdown_process, process: self) do
        run_process_callbacks(:shutdown) { shutdown }
      end
    end

    def shutdown
      @subscriptions.to_a.each(&:cancel)
      @connection_pool&.shutdown

      super
    end

    def set_procline
      procline "#{consumers.size} consumers"
    end

    def setup_consumers!
      @subscriptions = consumers.flat_map do |consumer_class|
        consumer_config = consumer_class.config

        Array.new(consumer_config.process_threads) do |n|
          connection_pool.with_connection do |bunny|
            channel = bunny.create_channel(*consumer_config.channel_args)
            channel.basic_qos(consumer_config.prefetch_count) if consumer_config.prefetch_count
            channel.on_uncaught_exception do |error|
              handle_thread_error(error)
            end

            exchange = channel.exchange(*consumer_config.exchange_args)

            if (args = consumer_config.retry_queue_args)
              _retry_queue = channel.queue(*args)
            end
            if (args = consumer_config.error_queue_args)
              _error_queue = channel.queue(*args)
            end

            main_queue = channel.queue(*consumer_config.consumer_queue_args)
            consumer_config.binds_args.each do |opts|
              main_queue.bind(exchange, **opts)
            end

            consumer_handler = Lepus::Consumers::Handler.new(
              consumer_class,
              channel,
              main_queue,
              "#{consumer_class.name}-#{n + 1}"
            )

            consumer_handler.on_delivery do |delivery_info, metadata, payload|
              consumer_handler.process_delivery(delivery_info, metadata, payload)
            end
            main_queue.subscribe_with(consumer_handler)
          end
        end
      end
    rescue Bunny::TCPConnectionFailed, Bunny::PossibleAuthenticationFailureError, Bunny::PreconditionFailed
      raise Lepus::ShutdownError
    rescue Lepus::InvalidConsumerConfigError
      raise Lepus::ShutdownError
    end

    def connection_pool
      return @connection_pool if defined?(@connection_pool)

      @connection_pool = Lepus::ConnectionPool.new(
        size: definer.pool_size,
        timeout: definer.pool_timeout,
        suffix: definer.name
      )
    end
  end
end
