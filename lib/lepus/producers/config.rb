# frozen_string_literal: true

module Lepus
  module Producers
    # Configuration class for producer settings
    class Config
      DEFAULT_POOL_SIZE = 1
      DEFAULT_POOL_TIMEOUT = 5.0

      attr_accessor :pool_size, :pool_timeout

      def initialize
        @pool_size = DEFAULT_POOL_SIZE
        @pool_timeout = DEFAULT_POOL_TIMEOUT
        @connection_pools = {}
        @connection_pools_mutex = Mutex.new
      end

      # Checks out a connection from the pool of the given named connection.
      # @param name [Symbol, String] the connection name, :default uses Lepus.config.rabbitmq_url
      # @yieldparam connection [Bunny::Session]
      # @raise [Lepus::InvalidConnectionError] when the connection name is not registered
      def with_connection(name = Lepus::Configuration::DEFAULT_CONNECTION, &block)
        connection_pool(name).with_connection(&block)
      end

      # Assign multiple attributes at once from a hash of options.
      # @param options [Hash] hash of options to assign
      # @return [void]
      def assign(options = {})
        options.each do |key, value|
          raise ArgumentError, "Unknown attribute #{key}" unless respond_to?(:"#{key}=")

          public_send(:"#{key}=", value)
        end
      end

      private

      # @param name [Symbol, String] the connection name
      # @return [Lepus::ConnectionPool] a connection pool instance configured for producers
      def connection_pool(name = Lepus::Configuration::DEFAULT_CONNECTION)
        name = (name || Lepus::Configuration::DEFAULT_CONNECTION).to_sym
        unless name == Lepus::Configuration::DEFAULT_CONNECTION || Lepus.config.connection?(name)
          raise Lepus::InvalidConnectionError, "Unknown connection #{name.inspect}"
        end

        @connection_pools_mutex.synchronize do
          @connection_pools[name] ||= Lepus::ConnectionPool.new(
            size: pool_size,
            timeout: pool_timeout,
            suffix: "producer",
            connection: name
          )
        end
      end
    end
  end
end
