# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Supervisor::Config do
  let(:config) { described_class.new }

  describe "#initialize" do
    it "sets the pidfile" do
      expect(config.pidfile).to eq("tmp/pids/lepus.pid")
    end

    it "sets the require_file" do
      expect(config.require_file).to be_nil

      config = described_class.new(require_file: "config/environment")
      expect(config.require_file).to eq("config/environment")
    end

    it "sets the consumers" do
      config = described_class.new(consumers: ["MyConsumer"])
      expect(config.consumers).to eq(["MyConsumer"])
    end
  end

  describe "#consumers" do
    after { reset_config! }

    it "returns all consumer classes that inherit from Lepus::Consumer" do
      my_consumer = Class.new(Lepus::Consumer)
      abstract_consumer = Class.new(Lepus::Consumer) { self.abstract_class = true }
      stub_const("MyConsumer", my_consumer)
      stub_const("AbstractConsumer", abstract_consumer)

      expect(config.consumers).to include("MyConsumer")
      expect(config.consumers).not_to include("AbstractConsumer")
    end
  end
end
