# frozen_string_literal: true

require "forwardable"

module Lepus
  module Producers
    # Configuration class for producer settings
    class Config
      extend Forwardable
      DEFAULT_POOL_SIZE = 1
      DEFAULT_POOL_TIMEOUT = 5.0

      attr_accessor :pool_size, :pool_timeout

      def_delegator :connection_pool, :with_connection

      def initialize
        @pool_size = DEFAULT_POOL_SIZE
        @pool_timeout = DEFAULT_POOL_TIMEOUT
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

      # @return [Lepus::ConnectionPool] a connection pool instance configured for producers
      def connection_pool
        @connection_pool ||= Lepus::ConnectionPool.new(
          size: pool_size,
          timeout: pool_timeout,
          suffix: "producer"
        )
      end
    end
  end
end
