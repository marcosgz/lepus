# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::ProducerConfig do
  let(:config) { described_class.new }

  describe "#initialize" do
    it "has default pool_size" do
      expect(config.pool_size).to eq(1)
    end

    it "has default pool_timeout" do
      expect(config.pool_timeout).to eq(5.0)
    end

    it "can be configured using assign method" do
      config = described_class.new
      config.assign(pool_size: 3, pool_timeout: 10.0)
      expect(config.pool_size).to eq(3)
      expect(config.pool_timeout).to eq(10.0)
    end
  end

  describe "#pool_size=" do
    it "allows setting pool_size" do
      config.pool_size = 5
      expect(config.pool_size).to eq(5)
    end
  end

  describe "#pool_timeout=" do
    it "allows setting pool_timeout" do
      config.pool_timeout = 15.0
      expect(config.pool_timeout).to eq(15.0)
    end
  end

  describe "#with_connection" do
    it "delegates to the connection pool" do
      expect(config).to respond_to(:with_connection)
    end

    it "uses the configured pool_size" do
      config.pool_size = 3
      connection_pool = config.send(:connection_pool)
      expect(connection_pool.pool_size).to eq(3)
    end

    it "uses the configured pool_timeout" do
      config.pool_timeout = 10.0
      connection_pool = config.send(:connection_pool)
      expect(connection_pool.timeout).to eq(10.0)
    end

    it "uses 'producer' as the connection suffix" do
      connection_pool = config.send(:connection_pool)
      expect(connection_pool.conn_suffix).to eq("producer")
    end

    it "returns the same connection pool instance on subsequent calls" do
      connection_pool1 = config.send(:connection_pool)
      connection_pool2 = config.send(:connection_pool)
      expect(connection_pool1).to be(connection_pool2)
    end
  end

  describe "#assign" do
    it "assigns multiple attributes from a hash" do
      config.assign(pool_size: 4, pool_timeout: 8.0)
      expect(config.pool_size).to eq(4)
      expect(config.pool_timeout).to eq(8.0)
    end

    it "raises ArgumentError for unknown attributes" do
      expect {
        config.assign(unknown_attribute: "value")
      }.to raise_error(ArgumentError, "Unknown attribute unknown_attribute")
    end

    it "ignores empty hash" do
      expect { config.assign({}) }.not_to raise_error
    end
  end
end
