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

    it "returns an empty array if no consumers are configured" do
      Lepus.config.consumers_directory = Pathname.new("/tmp/lepus/consumers")
      expect(config.consumers).to eq([])
    end

    context "when consumers are configured" do
      before do
        Lepus.config.consumers_directory = Pathname.new("/tmp/lepus/consumers")
        allow(Dir).to receive(:[]).and_return([
          "/tmp/lepus/consumers/ignore.js",
          "/tmp/lepus/consumers/exclude",
          "/tmp/lepus/consumers/application_consumer.rb",
          "/tmp/lepus/consumers/foo_consumer.rb",
          "/tmp/lepus/consumers/namespaced/bar_consumer.rb"
        ])
        allow(File).to receive(:readlines).and_return([""])
        expect(File).to receive(:readlines).with("/tmp/lepus/consumers/application_consumer.rb").and_return([
          "class ApplicationConsumer < Lepus::Consumer",
          "  self.abstract_class = true",
          "end"
        ])
      end

      it "returns the list of consumers" do
        expect(config.consumers).to eq(["FooConsumer", "Namespaced::BarConsumer"])
      end
    end
  end
end
