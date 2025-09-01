require "bunny"

module Lepus
  # Parse the list of options for the consumer.
  class ProcessConfig
    DEFAULT = :default

    # @return [Symbol] the unique identifier for this process configuration. Default is `:default`.
    attr_reader :id

    # @return [Integer] the size of the connection pool for this process. Default is 1.
    attr_accessor :pool_size

    # @return [Integer] the timeout in seconds to wait for a connection from the pool. Default is 5 seconds.
    attr_accessor :pool_timeout

    # @return [Integer] the threshold in seconds to consider a process alive. Default is 5 minutes.
    attr_accessor :alive_threshold

    def initialize(id = DEFAULT)
      @id = id.to_sym
      @pool_size = 1
      @pool_timeout = 5
      @alive_threshold = 5 * 60
    end

    def assign(options = {})
      options.each do |key, value|
        public_send(:"#{key}=", value) if respond_to?(:"#{key}=")
      end
    end

    def connection_pool
      return @connection_pool if defined?(@connection_pool)

      @connection_pool = Lepus::ConnectionPool.new(
        size: pool_size,
        timeout: pool_timeout,
        suffix: id.to_s
      )
    end
  end
end
