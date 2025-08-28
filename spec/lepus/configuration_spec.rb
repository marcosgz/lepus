# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Configuration do
  let(:configuration) { described_class.new }

  it "has a default rabbitmq url" do
    stub_const("ENV", ENV.to_hash.merge("RABBITMQ_URL" => nil))
    expect(configuration.rabbitmq_url).to eq(
      "amqp://guest:guest@localhost:5672"
    )
  end

  it "allows setting the rabbitmq url" do
    configuration.rabbitmq_url = "test"

    expect(configuration.rabbitmq_url).to eq("test")
  end

  it "allows setting the connection name" do
    configuration.connection_name = "conn"

    expect(configuration.connection_name).to eq("conn")
  end

  it "allows setting the recover_from_connection_close" do
    configuration.recover_from_connection_close = false

    expect(configuration.recover_from_connection_close).to be(false)
  end

  it "allows setting the recovery_attempts" do
    configuration.recovery_attempts = 2

    expect(configuration.recovery_attempts).to eq(2)
  end

  it "has a default recovery_attempt" do
    expect(configuration.recovery_attempts).to eq(10)
  end

  context "when recovery attempts are set" do
    before { configuration.recovery_attempts = 2 }

    it "sets recovery_attempts_exhausted to a raising proc" do
      proc = configuration.send(:recovery_attempts_exhausted)

      expect { proc.call }.to raise_error(
        Lepus::MaxRecoveryAttemptsExhaustedError
      )
    end
  end

  context "when recovery attempts are set to nil" do
    before { configuration.recovery_attempts = nil }

    it "sets also recovery_attempts_exhausted to nil" do
      expect(configuration.recovery_attempts).to be_nil
    end
  end

  describe "#consumers_directory" do
    it "defaults to the app/consumers" do
      expect(configuration.consumers_directory).to eq(Pathname.new("app/consumers"))
    end

    it "wraps the string path to an instance of Pathname" do
      configuration.consumers_directory = "lib/consumers"
      expect(configuration.consumers_directory).to eq(Pathname.new("lib/consumers"))
    end
  end

  describe "connection pool configuration" do
    it "has a default connection_pool_size" do
      expect(configuration.connection_pool_size).to eq(Lepus::ConnectionPool::DEFAULT_SIZE)
    end

    it "allows setting the connection_pool_size" do
      configuration.connection_pool_size = 10

      expect(configuration.connection_pool_size).to eq(10)
    end

    it "has a default connection_pool_timeout" do
      expect(configuration.connection_pool_timeout).to eq(Lepus::ConnectionPool::DEFAULT_TIMEOUT)
    end

    it "allows setting the connection_pool_timeout" do
      configuration.connection_pool_timeout = 10.0

      expect(configuration.connection_pool_timeout).to eq(10.0)
    end

    it "accepts integer values for connection_pool_size" do
      configuration.connection_pool_size = 5

      expect(configuration.connection_pool_size).to be_a(Integer)
      expect(configuration.connection_pool_size).to eq(5)
    end

    it "accepts float values for connection_pool_timeout" do
      configuration.connection_pool_timeout = 3.5

      expect(configuration.connection_pool_timeout).to be_a(Float)
      expect(configuration.connection_pool_timeout).to eq(3.5)
    end
  end
end
