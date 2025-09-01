# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::ProcessConfig do
  subject(:instance) { described_class.new(:custom).tap { |cnf| cnf.assign(options) } }

  let(:options) { {} }

  describe "#initialize" do
    context "when no options are provided" do
      it "sets the default id to :default" do
        expect(described_class.new.id).to eq(:default)
      end

      it "sets the default pool_size to 1" do
        expect(instance.pool_size).to eq(1)
      end

      it "sets the default pool_timeout to 5" do
        expect(instance.pool_timeout).to eq(5)
      end

      it "sets the default alive_threshold to 300 seconds (5 minutes)" do
        expect(instance.alive_threshold).to eq(300)
      end
    end

    context "when options are provided" do
      let(:options) do
        {
          pool_size: 10,
          pool_timeout: 15,
          alive_threshold: 600
        }
      end

      it "sets the pool_size to the provided value" do
        expect(instance.pool_size).to eq(10)
      end

      it "sets the pool_timeout to the provided value" do
        expect(instance.pool_timeout).to eq(15)
      end

      it "sets the alive_threshold to the provided value" do
        expect(instance.alive_threshold).to eq(600)
      end
    end
  end

  describe "#connection_pool" do
    it "builds a ConnectionPool using the default pool config" do
      expect(conn_pool = instance.connection_pool).to be_an_instance_of(Lepus::ConnectionPool)
      expect(conn_pool.pool_size).to eq(1)
      expect(conn_pool.timeout).to eq(5.0)
    end

    it "memoizes connection_pool" do
      conn_pool = instance.connection_pool
      expect(instance.connection_pool).to be(conn_pool)
    end

    context "when process options are given" do
      let(:options) { {pool_size: 3, pool_timeout: 10} }

      it "builds a ConnectionPool using the given pool config" do
        expect(conn_pool = instance.connection_pool).to be_an_instance_of(Lepus::ConnectionPool)
        expect(conn_pool.pool_size).to eq(3)
        expect(conn_pool.timeout).to eq(10)
      end
    end
  end

  describe "#freeze" do
    it "freezes the instance" do
      expect(instance.frozen?).to be(false)
      instance.freeze
      expect(instance.frozen?).to be(true)
    end

    it "prevents further modifications to attributes" do
      instance.freeze
      expect { instance.pool_size = 5 }.to raise_error(FrozenError)
      expect { instance.pool_timeout = 20 }.to raise_error(FrozenError)
      expect { instance.alive_threshold = 1000 }.to raise_error(FrozenError)
    end
  end

  describe "#dup" do
    it "creates a shallow copy of the instance" do
      copy = instance.dup
      expect(copy).to be_a(described_class)
      expect(copy).not_to be(instance)
      expect(copy.pool_size).to eq(instance.pool_size)
      expect(copy.pool_timeout).to eq(instance.pool_timeout)
      expect(copy.alive_threshold).to eq(instance.alive_threshold)
    end

    it "allows modifications to the duplicated instance" do
      instance.freeze
      copy = instance.dup
      copy.pool_size = 5
      copy.pool_timeout = 20
      copy.alive_threshold = 1000

      expect(copy.pool_size).to eq(5)
      expect(copy.pool_timeout).to eq(20)
      expect(copy.alive_threshold).to eq(1000)

      # Original instance remains unchanged
      expect(instance.pool_size).to eq(1)
      expect(instance.pool_timeout).to eq(5)
      expect(instance.alive_threshold).to eq(300)
    end
  end
end
