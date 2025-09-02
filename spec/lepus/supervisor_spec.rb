# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Supervisor do
  subject(:supervisor) { described_class.new }

  after do
    Lepus::ProcessRegistry.instance.clear
  end

  describe "#initialize" do
    it "returns the default pidfile" do
      expect(supervisor.send(:pidfile_path)).to eq("tmp/pids/lepus.pid")
    end

    it "sets a custom pidfile" do
      supervisor = described_class.new(pidfile: "custom/pidfile.pid")
      expect(supervisor.send(:pidfile_path)).to eq("custom/pidfile.pid")
    end

    it "sets the require_file" do
      expect(supervisor.send(:require_file)).to be_nil

      supervisor = described_class.new(require_file: "config/environment")
      expect(supervisor.send(:require_file)).to eq("config/environment")
    end

    it "sets the consumer_class_names" do
      supervisor = described_class.new(consumers: ["MyConsumer"])
      expect(supervisor.send(:consumer_class_names)).to eq(["MyConsumer"])
    end
  end

  describe "#consumer_class_names" do
    after { reset_config! }

    it "returns all consumer classes that inherit from Lepus::Consumer" do
      my_consumer = Class.new(Lepus::Consumer)
      abstract_consumer = Class.new(Lepus::Consumer) { self.abstract_class = true }
      stub_const("MyConsumer", my_consumer)
      stub_const("AbstractConsumer", abstract_consumer)

      expect(supervisor.send(:consumer_class_names)).to include("MyConsumer")
      expect(supervisor.send(:consumer_class_names)).not_to include("AbstractConsumer")
    end
  end

  # rubocop:disable RSpec/AnyInstance
  describe "#check_bunny_connection" do
    subject(:conn_test) { supervisor.send(:check_bunny_connection) }

    let(:supervisor) { described_class.new(consumers: %w[TestConsumer]) }

    context "when the connection is successful" do
      before do
        allow_any_instance_of(Bunny::Session).to receive(:start).and_return(:ok)
      end

      it "does not raise an error" do
        expect { conn_test }.not_to raise_error
      end
    end

    context "when the connection is not successful" do
      before do
        allow_any_instance_of(Bunny::Session).to receive(:start).and_raise(Bunny::Exception)
      end

      it "raises an error" do
        expect { conn_test }.to raise_error(Bunny::Exception)
      end
    end
  end
  # rubocop:enable RSpec/AnyInstance
end
