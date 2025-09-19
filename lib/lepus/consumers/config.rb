require "bunny"

module Lepus
  module Consumers
    # Parse the list of options for the consumer.
    class Config
      DEFAULT_EXCHANGE_OPTIONS = {
        name: nil,
        type: :topic, # The type of the exchange (:direct, :fanout, :topic or :headers).
        durable: true
      }.freeze

      DEFAULT_CHANNEL_OPTIONS = {
        pool_size: 1,
        abort_on_exception: false,
        shutdown_timeout: 60
      }.freeze

      DEFAULT_QUEUE_OPTIONS = {
        name: nil,
        durable: true
      }.freeze

      DEFAULT_PREFETCH_COUNT = 1

      DEFAULT_WORKER_OPTIONS = {
        name: "default",
        threads: 1
      }.freeze

      DEFAULT_RETRY_QUEUE_OPTIONS = {
        name: nil,
        durable: true,
        delay: 5000,
        arguments: {}
      }

      DEFAULT_ERROR_QUEUE_OPTIONS = DEFAULT_QUEUE_OPTIONS

      attr_reader :options, :prefetch_count

      def initialize(options = {})
        opts = Lepus::Primitive::Hash.new(options).deep_symbolize_keys

        @worker_opts = DEFAULT_WORKER_OPTIONS.merge(
          declaration_config(opts.delete(:worker))
        )
        @exchange_opts = DEFAULT_EXCHANGE_OPTIONS.merge(
          declaration_config(opts.delete(:exchange))
        )
        @queue_opts = DEFAULT_QUEUE_OPTIONS.merge(
          declaration_config(opts.delete(:queue))
        )
        if (value = opts.delete(:retry_queue))
          @retry_queue_opts = DEFAULT_RETRY_QUEUE_OPTIONS.merge(
            declaration_config(value)
          )
        end
        if (value = opts.delete(:error_queue))
          @error_queue_opts = DEFAULT_ERROR_QUEUE_OPTIONS.merge(
            declaration_config(value)
          )
        end
        @channel_opts = DEFAULT_CHANNEL_OPTIONS.merge(opts.delete(:channel) || {})
        @bind_opts = opts.delete(:bind) || {}
        if (routing_key = opts.delete(:routing_key))
          @bind_opts[:routing_key] ||= routing_key
        end
        @prefetch_count = opts.key?(:prefetch) ? opts.delete(:prefetch) : DEFAULT_PREFETCH_COUNT
        @options = opts
      end

      def channel_args
        [
          nil,
          *@channel_opts.values_at(
            :pool_size,
            :abort_on_exception,
            :shutdown_timeout
          )
        ]
      end

      def exchange_args
        [exchange_name, @exchange_opts.reject { |k, v| k == :name }]
      end

      def consumer_queue_args
        opts = @queue_opts.reject { |k, v| k == :name }
        return [queue_name, opts] unless retry_queue_args

        opts[:arguments] ||= {}
        opts[:arguments]["x-dead-letter-exchange"] = ""
        opts[:arguments]["x-dead-letter-routing-key"] = retry_queue_name

        [queue_name, opts]
      end

      def retry_queue_args
        return unless @retry_queue_opts

        delay = @retry_queue_opts[:delay]
        args = (@retry_queue_opts[:arguments] || {}).merge(
          "x-dead-letter-exchange" => "",
          "x-dead-letter-routing-key" => queue_name,
          "x-message-ttl" => delay
        )
        extra_keys = %i[name delay]
        opts = @retry_queue_opts.reject { |k, v| extra_keys.include?(k) }
        [retry_queue_name, opts.merge(arguments: args)]
      end

      def error_queue_args
        return unless @error_queue_opts

        name = @error_queue_opts[:name]
        name ||= "#{queue_name}.error"
        [name, @error_queue_opts.reject { |k, v| k == :name }]
      end

      def binds_args
        arguments = @bind_opts.fetch(:arguments, {}).transform_keys(&:to_s)
        opts = {}
        opts[:arguments] = arguments unless arguments.empty?
        if (routing_keys = @bind_opts[:routing_key]).is_a?(Array)
          routing_keys.map { |key| opts.merge(routing_key: key) }
        elsif (routing_key = @bind_opts[:routing_key])
          [opts.merge(routing_key: routing_key)]
        else
          [opts]
        end
      end

      def worker_name
        @worker_opts.fetch(:name, DEFAULT_WORKER_OPTIONS[:name])
      end

      def worker_threads
        threads = @worker_opts.fetch(:threads, DEFAULT_WORKER_OPTIONS[:threads])
        if threads.to_i < 1
          raise InvalidConsumerConfigError, "Worker threads must be at least 1"
        end
        threads
      end

      protected

      def exchange_name
        @exchange_opts[:name] || raise(InvalidConsumerConfigError, "Exchange name is required")
      end

      def queue_name
        @queue_opts[:name] || raise(InvalidConsumerConfigError, "Queue name is required")
      end

      def retry_queue_name
        name = @retry_queue_opts[:name]
        name ||= "#{queue_name}.retry"
        name
      end

      # Normalizes a declaration config (for exchanges and queues) into a configuration Hash.
      #
      # If the given `value` is a String, convert it to a Hash with the key `:name` and the value.
      # If the given `value` is a Hash, leave it as is.
      def declaration_config(value)
        case value
        when Hash then value
        when String then {name: value}
        when Symbol then {name: value.to_s}
        when NilClass then {}
        when TrueClass then {}
        end
      end
    end
  end
end
