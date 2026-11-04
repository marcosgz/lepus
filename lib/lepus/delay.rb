# frozen_string_literal: true

module Lepus
  # Delayed delivery built on per-delay TTL queues that dead-letter back to their target,
  # so it works without the rabbitmq-delayed-message-exchange plugin.
  #
  # Exchange delays: messages are published to a headers exchange named "<exchange>.delayed"
  # with a {HEADER} header. Each delay value has its own "<exchange>.delayed.<ms>" queue bound by
  # that header; the queue dead-letters into the target exchange keeping the original routing key.
  #
  # Queue delays: messages are published through the default exchange to "<queue>.delay.<ms>",
  # which dead-letters straight into the target queue.
  module Delay
    HEADER = "lepus-delay"
    COUNT_HEADER = "x-lepus-delayed-count"
    DEFAULT_EXCHANGE = ""
    REDECLARE_INTERVAL = 60

    @declarations = {}
    @mutex = Mutex.new

    class << self
      # @param value [Integer, Float, #in_milliseconds] The delay in milliseconds.
      # @return [Integer] The delay in whole milliseconds.
      # @raise [ArgumentError] when the value is not a positive number of milliseconds.
      def normalize(value)
        ms = case value
        when Numeric then value
        else value.respond_to?(:in_milliseconds) ? value.in_milliseconds : value
        end
        raise ArgumentError, "Invalid delay #{value.inspect}, expected milliseconds" unless finite_number?(ms)

        ms = ms.round
        raise ArgumentError, "Delay must be greater than zero, got #{value.inspect}" unless ms > 0

        ms
      end

      def exchange_name_for(exchange)
        "#{exchange}.delayed"
      end

      def exchange_queue_name_for(exchange, ms)
        "#{exchange}.delayed.#{ms}"
      end

      def queue_delay_name_for(queue, ms)
        "#{queue}.delay.#{ms}"
      end

      def queue_args_for_exchange(exchange, ms)
        with_expires(ms,
          "x-message-ttl" => ms,
          "x-dead-letter-exchange" => exchange)
      end

      def queue_args_for_queue(queue, ms)
        with_expires(ms,
          "x-message-ttl" => ms,
          "x-dead-letter-exchange" => DEFAULT_EXCHANGE,
          "x-dead-letter-routing-key" => queue)
      end

      # Declares the delayed headers exchange and the queue for the given delay.
      # @return [String] The name of the delayed exchange to publish to.
      def declare_for_exchange!(channel, exchange, ms)
        delayed_exchange = exchange_name_for(exchange)
        queue = exchange_queue_name_for(exchange, ms)
        args = queue_args_for_exchange(exchange, ms)

        declare(channel, queue, args) do |ch|
          ch.exchange_declare(delayed_exchange, :headers, durable: true)
          ch.queue_declare(queue, durable: true, arguments: args)
          ch.queue_bind(queue, delayed_exchange, arguments: {"x-match" => "all", HEADER => ms})
        end
        delayed_exchange
      end

      # Declares the queue that delays deliveries to the given queue.
      # @return [String] The name of the delay queue to publish to.
      def declare_for_queue!(channel, queue, ms)
        delay_queue = queue_delay_name_for(queue, ms)
        args = queue_args_for_queue(queue, ms)

        declare(channel, delay_queue, args) do |ch|
          ch.queue_declare(delay_queue, durable: true, arguments: args)
        end
        delay_queue
      end

      def reset!
        mutex.synchronize { declarations.clear }
      end

      private

      def finite_number?(value)
        return false unless value.is_a?(Numeric) && value.real?

        !value.respond_to?(:finite?) || value.finite?
      end

      def with_expires(ms, args)
        padding = Lepus.config.delay_queue_expires
        return args unless padding

        args.merge("x-expires" => ms + padding)
      end

      # Declarations run on a short-lived channel so a failure does not close the caller's channel.
      # RabbitMQ only counts declarations and consumers as queue usage for x-expires, and a message
      # published at t must outlive t + delay while the queue only lives until the last declaration
      # + delay + padding, so declarations are refreshed before half of the padding elapses.
      # The refresh is also capped so a queue deleted behind our back is declared again soon.
      def declare(channel, queue, args)
        connection = channel.connection
        key = [connection, queue, args]
        return if declared?(key)

        begin
          connection.with_channel { |ch| yield ch }
        rescue Bunny::PreconditionFailed => e
          raise Lepus::Error, "Cannot declare delay queue #{queue.inspect} with #{args.inspect}: #{e.message}. " \
            "Delete the queue or keep its previous arguments."
        end

        mutex.synchronize { declarations[key] = monotonic_now + redeclare_interval }
      end

      def declared?(key)
        mutex.synchronize do
          next false unless declarations.key?(key)

          monotonic_now < declarations[key]
        end
      end

      def redeclare_interval
        padding = Lepus.config.delay_queue_expires
        return REDECLARE_INTERVAL unless padding

        [padding / 2000.0, REDECLARE_INTERVAL].min
      end

      def monotonic_now
        ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      end

      attr_reader :declarations, :mutex
    end
  end
end
