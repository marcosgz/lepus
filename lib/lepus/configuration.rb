# frozen_string_literal: true

module Lepus
  # The class representing the global {Lepus} configuration.
  class Configuration
    DEFAULT_RABBITMQ_URL = "amqp://guest:guest@localhost:5672"
    DEFAULT_RECOVERY_ATTEMPTS = 10
    DEFAULT_RECOVERY_INTERVAL = 5.0
    DEFAULT_RECOVER_FROM_CONNECTION_CLOSE = true
    DEFAULT_CONSUMERS_DIRECTORY = Pathname.new("app/consumers")

    # @return [String] the connection string for RabbitMQ.
    attr_accessor :rabbitmq_url

    # @return [String] the name for the RabbitMQ connection.
    attr_accessor :connection_name

    # @return [Boolean] if the recover_from_connection_close value is set for the RabbitMQ connection.
    attr_accessor :recover_from_connection_close

    # @return [Integer] max number of recovery attempts, nil means forever
    attr_accessor :recovery_attempts

    # @return [Integer] the interval in seconds between network recovery attempts.
    attr_accessor :recovery_interval

    # @return [Pathname] the directory where the consumers are stored.
    attr_reader :consumers_directory

    # @return [Class] the Rails executor used to wrap asynchronous operations, defaults to the app executor
    # @see https://guides.rubyonrails.org/threading_and_code_execution.html#executor
    attr_accessor :app_executor

    # @return [Proc] custom lambda/Proc to call when there's an error within a Lepus thread that takes the exception raised as argument
    attr_accessor :on_thread_error

    # @return [Integer] the interval in seconds between heartbeats. Default is 60 seconds.
    attr_accessor :process_heartbeat_interval

    # @return [Integer] the threshold in seconds to consider a process alive. Default is 5 minutes.
    attr_accessor :process_alive_threshold

    def initialize
      @connection_name = "Lepus (#{Lepus::VERSION})"
      @rabbitmq_url = ENV.fetch("RABBITMQ_URL", DEFAULT_RABBITMQ_URL) || DEFAULT_RABBITMQ_URL
      @recovery_attempts = DEFAULT_RECOVERY_ATTEMPTS
      @recovery_interval = DEFAULT_RECOVERY_INTERVAL
      @recover_from_connection_close = DEFAULT_RECOVER_FROM_CONNECTION_CLOSE
      @consumers_directory = DEFAULT_CONSUMERS_DIRECTORY
      @process_heartbeat_interval = 60
      @process_alive_threshold = 5 * 60
    end

    # @param suffix [String] the suffix to add to the connection name
    # @return [Bunny::Session] the connection to RabbitMQ
    def create_connection(suffix: nil)
      kwargs = connection_config
      if suffix && connection_name
        kwargs[:connection_name] = "#{connection_name} #{suffix}"
      end
      ::Bunny
        .new(rabbitmq_url, **kwargs)
        .tap { |conn| conn.start }
    end

    # @param value [Pathname] the directory where the consumers are stored.
    def consumers_directory=(value)
      @consumers_directory = value.is_a?(Pathname) ? value : Pathname.new(value)
    end

    # Configure the worker process that will run the consumers.
    # @param names [Array<Symbol>] the names of the workers to configure
    # @param options [Hash] the options to assign to the worker configuration
    def worker(*names, **options)
      names << Lepus::Consumers::WorkerFactory::DEFAULT_NAME if names.empty?

      names.map(&:to_s).uniq.each do |pid|
        inst = Lepus::Consumers::WorkerFactory[pid]
        inst.assign(options) if options.any?
        yield(inst) if block_given?
      end
    end

    # Configure the producer related settings.
    # @param options [Hash] the options to assign to the producer configuration
    def producer(**options)
      producer_config.assign(options) if options.any?
      yield(producer_config) if block_given?
      producer_config
    end

    # @return [Lepus::ProducerConfig] the producer configuration
    def producer_config
      @producer_config ||= Lepus::ProducerConfig.new
    end

    # @param value [Logger] the logger to set
    # @return [void]
    def logger=(value)
      Lepus.logger = value
    end

    protected

    def connection_config
      {
        connection_name: connection_name,
        recover_from_connection_close: recover_from_connection_close,
        recovery_attempts: recovery_attempts,
        network_recovery_interval: recovery_interval,
        recovery_attempts_exhausted: recovery_attempts_exhausted
      }.compact
    end

    # @return [Proc, NilClass] Proc that is passed to Bunny’s recovery_attempts_exhausted block.
    def recovery_attempts_exhausted
      return unless recovery_attempts

      proc do
        Thread.current.abort_on_exception = true
        raise Lepus::MaxRecoveryAttemptsExhaustedError
      end
    end
  end
end
