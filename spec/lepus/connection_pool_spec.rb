# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::ConnectionPool do
  let(:mock_connection) do
    instance_double(
      Bunny::Session,
      connected?: true,
      close: nil
    )
  end
  let(:pool_size) { 3 }
  let(:timeout) { 1.0 }
  let(:pool) { described_class.new(size: pool_size, timeout: timeout) }

  before do
    allow(Lepus).to receive(:config).and_return(
      instance_double(Lepus::Configuration, create_connection: mock_connection)
    )
  end

  describe "#initialize" do
    it "creates a connection pool with the specified size" do
      expect(pool.pool_size).to eq(pool_size)
      expect(pool.timeout).to eq(timeout)
    end

    it "uses default values when not specified" do
      default_pool = described_class.new
      expect(default_pool.pool_size).to eq(Lepus::ConnectionPool::DEFAULT_SIZE)
      expect(default_pool.timeout).to eq(Lepus::ConnectionPool::DEFAULT_TIMEOUT)
    end
  end

  describe "#with_connection" do
    it "yields a connection from the pool" do
      pool.with_connection do |connection|
        expect(connection).to respond_to(:connected?)
        expect(connection).to be_connected
      end
    end

    it "releases the connection back to the pool after use" do
      connections = []

      pool.with_connection do |conn1|
        connections << conn1
      end

      pool.with_connection do |conn2|
        connections << conn2
      end

      # Should reuse connections from the pool
      expect(connections.uniq.length).to be <= pool_size
    end

    it "raises ConnectionPoolTimeoutError when pool is exhausted" do
      # Create a small pool and try to exhaust it
      small_pool = described_class.new(size: 1, timeout: 0.1)

      # Hold one connection
      small_pool.with_connection do |conn|
        expect {
          small_pool.with_connection { |conn2| }
        }.to raise_error(Lepus::ConnectionPoolTimeoutError)
      end
    end

    it "handles exceptions and still releases the connection" do
      expect {
        pool.with_connection do |connection|
          raise "Test error"
        end
      }.to raise_error("Test error")

      # Connection should still be available
      expect(pool.available_count).to eq(1)
    end
  end

  describe "#checkout" do
    it "returns a connection from the pool" do
      connection = pool.checkout
      expect(connection).to respond_to(:connected?)
      expect(connection).to be_connected
      pool.checkin(connection)
    end

    it "reuses available connections" do
      conn1 = pool.checkout
      pool.checkin(conn1)

      conn2 = pool.checkout
      expect(conn2).to eq(conn1)
      pool.checkin(conn2)
    end

    it "creates new connections when pool is empty" do
      connection = pool.checkout
      expect(connection).to respond_to(:connected?)
      pool.checkin(connection)
    end

    it "raises error when pool is shut down" do
      pool.shutdown
      expect { pool.checkout }.to raise_error(Lepus::ConnectionPoolError)
    end
  end

  describe "#checkin" do
    it "returns connection to available pool" do
      connection = pool.checkout
      pool.checkin(connection)
      expect(pool.available_count).to eq(1)
    end

    it "closes connection if pool is shut down" do
      connection = pool.checkout
      pool.shutdown
      pool.checkin(connection)
      expect(pool.available_count).to eq(0)
    end

    it "closes connection if it's not connected" do
      connection = pool.checkout
      allow(connection).to receive(:connected?).and_return(false)
      pool.checkin(connection)
      expect(pool.available_count).to eq(0)
    end
  end

  describe "#shutdown" do
    it "shuts down the pool and closes all connections" do
      connections = []

      # Create some connections
      pool_size.times do
        connections << pool.checkout
      end

      pool.shutdown

      expect(pool.available?).to be false
      expect(pool.size).to eq(0)
    end

    it "prevents new checkouts after shutdown" do
      pool.shutdown
      expect { pool.checkout }.to raise_error(Lepus::ConnectionPoolError)
    end
  end

  describe "#available?" do
    it "returns true when pool is available" do
      expect(pool.available?).to be true
    end

    it "returns false when pool is shut down" do
      pool.shutdown
      expect(pool.available?).to be false
    end
  end

  describe "pool statistics" do
    it "tracks pool size correctly" do
      expect(pool.size).to eq(0)

      connection = pool.checkout
      expect(pool.size).to eq(1)

      pool.checkin(connection)
      expect(pool.size).to eq(1)
    end

    it "tracks available and in-use connections" do
      expect(pool.available_count).to eq(0)
      expect(pool.in_use_count).to eq(0)

      connection = pool.checkout
      expect(pool.available_count).to eq(0)
      expect(pool.in_use_count).to eq(1)

      pool.checkin(connection)
      expect(pool.available_count).to eq(1)
      expect(pool.in_use_count).to eq(0)
    end
  end

  describe "concurrent access" do
    it "handles multiple threads accessing the pool" do
      threads = []
      connections = Concurrent::Array.new

      5.times do
        threads << Thread.new do
          pool.with_connection do |connection|
            connections << connection
            sleep(0.1) # Simulate work
          end
        end
      end

      threads.each(&:join)

      # Should not exceed pool size
      expect(connections.uniq.length).to be <= pool_size
    end
  end
end
