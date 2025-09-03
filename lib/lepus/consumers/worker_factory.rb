# frozen_string_literal: true

module Lepus
  module Consumers
    # This is a configuration object for defining process-level settings
    # It holds settings such as connection pool size, timeouts, and alive thresholds and
    # more importantly, the list of consumers that should be run in this process.
    #
    # Note that this class only holds configuration data related the process and does not handle
    # the actual process management or consumer execution. Consumer has its own configuration for
    # AMPQ settings, queue names, etc.
    class WorkerFactory
      DEFAULT_NAME = "default"

      class << self
        def [](name)
          @instances ||= Concurrent::Map.new
          @instances[name.to_s] ||= new(name)
        end

        def default
          self[DEFAULT_NAME]
        end

        def exists?(name)
          return false unless @instances

          @instances.key?(name.to_s)
        end

        # Create an immutable copy of the process configuration with the specified consumers.
        # @param name [String, Symbol] the name of the process configuration to use.
        # @param consumers [Array<Lepus::Consumer>] the list of consumer classes to be run in this process.
        # @return [Lepus::Consumers::WorkerFactory] the immutable process configuration.
        def immutate_with(name, consumers: [])
          definer = self[name].dup
          definer.freeze_with(consumers)
          definer
        end

        private

        # This method is primarily for testing purposes to reset the instances map.
        def clear_all
          @instances = Concurrent::Map.new
        end
      end

      # @return [String] the unique name for this process configuration. Default is "default".
      attr_reader :name

      # @return [Array<Lepus::Consumer>] the list of consumer classes to be run in this process.
      attr_reader :consumers

      # @return [Integer] the size of the connection pool for this process. Default is 1.
      attr_accessor :pool_size

      # @return [Integer] the timeout in seconds to wait for a connection from the pool. Default is 5 seconds.
      attr_accessor :pool_timeout

      # You probably want to use .[] or .default to get an instance instead of calling new directly.
      def initialize(name)
        @name = name.to_s
        @pool_size = 1
        @pool_timeout = 5
        @consumers = []
        @callbacks = { before_fork: [], after_fork: [] }
      end

      # Assign multiple attributes at once from a hash of options.
      # @raise [ArgumentError] if an unknown attribute is provided.
      # @return [void]
      def assign(options = {})
        options.each do |key, value|
          raise ArgumentError, "Unknown attribute #{key}" unless respond_to?(:"#{key}=")

          public_send(:"#{key}=", value)
        end
      end

      # Freeze this configuration instance and set the consumers that will run in this process.
      # @param consumers [Array<Lepus::Consumer>] the list of consumer classes to be run in this process.
      # @return [void]
      def freeze_with(consumers)
        @consumers = Array(consumers).map do |consumer|
          unless consumer <= Lepus::Consumer
            raise ArgumentError, "#{consumer} is not a subclass of Lepus::Consumer"
          end

          consumer
        end.uniq.freeze
        @callbacks = @callbacks.transform_values(&:freeze)

        freeze
      end

      # Instantiate a new Lepus::Consumers::Worker based on this configuration.
      # @return [Lepus::Consumers::Worker] a new instance of Lepus::Consumers::Worker configured with this definition.
      def instantiate_process
        Lepus::Consumers::Worker.new(self)
      end

      def before_fork(&block)
        callbacks[:before_fork] << block if block_given?
      end

      def after_fork(&block)
        callbacks[:after_fork] << block if block_given?
      end

      def run_process_callbacks(type)
        return unless callbacks[type]

        callbacks[type].each { |callback| callback.call }
      end

      private

      attr_reader :callbacks
    end
  end
end
