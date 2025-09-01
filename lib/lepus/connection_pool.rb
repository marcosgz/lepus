# frozen_string_literal: true

require "concurrent"

module Lepus
  # Connection pool for managing Bunny connections efficiently
  # Similar to the connection_pool gem but using concurrent-ruby primitives
  class ConnectionPool
    DEFAULT_SIZE = 5
    DEFAULT_TIMEOUT = 5.0

    attr_reader :pool_size, :timeout, :conn_suffix

    def initialize(size: DEFAULT_SIZE, timeout: DEFAULT_TIMEOUT, suffix: nil)
      @pool_size = size
      @timeout = timeout
      @conn_suffix = suffix
      @available = Concurrent::Array.new
      @in_use = Concurrent::Array.new
      @semaphore = Concurrent::Semaphore.new(pool_size)
      @mutex = Concurrent::ReadWriteLock.new
      @shutdown = Concurrent::AtomicBoolean.new(false)
    end

    def with_connection
      connection = checkout
      begin
        yield connection
      ensure
        checkin(connection)
      end
    rescue Concurrent::TimeoutError
      raise Lepus::ConnectionPoolTimeoutError, "Connection pool timeout after #{timeout} seconds"
    end

    def checkout
      raise Lepus::ConnectionPoolError, "Connection pool is shut down" if @shutdown.value

      # Try to acquire a permit with timeout
      start_time = Time.now
      acquired = false

      while Time.now - start_time < timeout
        if @semaphore.try_acquire
          acquired = true
          break
        end
        sleep(0.01) # Small sleep to avoid busy waiting
      end

      unless acquired
        raise Concurrent::TimeoutError, "Connection pool timeout"
      end

      @mutex.with_read_lock do
        # Try to reuse an existing connection
        connection = @available.shift
        if connection && connection.connected?
          @in_use << connection
          return connection
        end
      end

      # Create a new connection
      connection = Lepus.config.create_connection(suffix: @conn_suffix)
      @mutex.with_write_lock do
        @in_use << connection
      end
      connection
    rescue => e
      @semaphore.release
      raise e
    end

    def checkin(connection)
      return unless connection

      @mutex.with_write_lock do
        @in_use.delete(connection)
        if connection.connected? && !@shutdown.value
          @available << connection
        else
          connection.close rescue nil
        end
      end
      @semaphore.release
    end

    def shutdown
      @shutdown.make_true

      @mutex.with_write_lock do
        (@available + @in_use).each do |connection|
          connection.close rescue nil
        end
        @available.clear
        @in_use.clear
      end
    end

    def available?
      !@shutdown.value
    end

    def size
      @mutex.with_read_lock do
        @available.length + @in_use.length
      end
    end

    def available_count
      @mutex.with_read_lock do
        @available.length
      end
    end

    def in_use_count
      @mutex.with_read_lock do
        @in_use.length
      end
    end
  end

  # Error raised when connection pool times out
  class ConnectionPoolTimeoutError < StandardError; end

  # Error raised when connection pool encounters an error
  class ConnectionPoolError < StandardError; end
end
