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

  describe "#consumer_process" do
    before { Lepus::Consumers::ProcessFactory.send(:clear_all) }

    it "initializes a new ProcessFactory a new process config with default values" do
      expect {
        configuration.consumer_process
      }.to change { Lepus::Consumers::ProcessFactory.exists?("default") }.from(false).to(true)
    end

    it "allows setting options on the process config" do
      expect {
        configuration.consumer_process(pool_size: 5, pool_timeout: 10)
      }.to change { Lepus::Consumers::ProcessFactory.exists?("default") }.from(false).to(true)

      conf = Lepus::Consumers::ProcessFactory.default
      expect(conf.pool_size).to eq(5)
      expect(conf.pool_timeout).to eq(10)
    end

    it "allows setting process by given name" do
      expect {
        configuration.consumer_process(:custom, pool_size: 4)
      }.to change { Lepus::Consumers::ProcessFactory.exists?("custom") }.from(false).to(true)
      conf = Lepus::Consumers::ProcessFactory["custom"]
      expect(conf.pool_size).to eq(4)
      expect(conf.name).to eq("custom")
    end

    it "ignores when process with given name already exists" do
      configuration.consumer_process(:custom, pool_size: 4)
      expect {
        configuration.consumer_process(:custom, pool_size: 10)
      }.to change { Lepus::Consumers::ProcessFactory["custom"].pool_size }.from(4).to(10)
    end

    it "allows setting to multiple process ids at once" do
      expect {
        configuration.consumer_process(:high, :low, pool_size: 3)
      }.to change { Lepus::Consumers::ProcessFactory.exists?("high") }.from(false).to(true)
        .and change { Lepus::Consumers::ProcessFactory.exists?("low") }.from(false).to(true)

      expect(Lepus::Consumers::ProcessFactory["high"].pool_size).to eq(3)
      expect(Lepus::Consumers::ProcessFactory["low"].pool_size).to eq(3)
    end

    it "yields the process config to a block" do
      yielded = nil
      configuration.consumer_process(:custom) do |config|
        yielded = config
        config.pool_size = 7
      end
      conf = Lepus::Consumers::ProcessFactory["custom"]
      expect(yielded).to be(conf)
      expect(yielded.pool_size).to eq(7)
    end
  end
end
