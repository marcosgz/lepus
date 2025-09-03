# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Consumers::WorkerFactory do
  subject(:instance) { described_class.new(name) }

  describe ".[]" do
    before { described_class.send(:clear_all) }

    it "returns a new instance for a given name" do
      instance1 = described_class["process_1"]
      instance2 = described_class["process_2"]
      expect(instance1).to be_a(described_class)
      expect(instance2).to be_a(described_class)
      expect(instance1).not_to be(instance2)
    end

    it "returns the same instance for the same name" do
      instance1 = described_class["process_1"]
      instance2 = described_class["process_1"]
      expect(instance1).to be(instance2)
    end
  end

  describe ".default" do
    before { described_class.send(:clear_all) }

    it "returns the default instance" do
      default_instance = described_class.default
      expect(default_instance).to be_a(described_class)
      expect(default_instance.name).to eq("default")
      expect(described_class["default"]).to be(default_instance)
    end
  end

  describe ".exists?" do
    before { described_class.send(:clear_all) }

    it "returns false if no instance exists for the given name" do
      expect(described_class.exists?("non_existent")).to be(false)
    end

    it "returns true if an instance exists for the given name" do
      described_class["existing_process"]
      expect(described_class.exists?("existing_process")).to be(true)
    end
  end

  describe ".immutate_with" do
    before { described_class.send(:clear_all) }

    let(:consumer_class) { Class.new(Lepus::Consumer) }
    let(:consumers) { [consumer_class] }

    it "creates an immutable copy of the process configuration with specified consumers" do
      original = described_class["custom_process"]
      original.pool_size = 5
      original.pool_timeout = 10

      frozen_instance = described_class.immutate_with("custom_process", consumers: consumers)

      expect(frozen_instance).to be_a(described_class)
      expect(frozen_instance.name).to eq("custom_process")
      expect(frozen_instance.pool_size).to eq(5)
      expect(frozen_instance.pool_timeout).to eq(10)
      expect(frozen_instance.consumers).to eq(consumers)

      expect { frozen_instance.pool_size = 20 }.to raise_error(FrozenError)
      expect { frozen_instance.consumers << Class.new }.to raise_error(FrozenError)
      expect { frozen_instance.before_fork {} }.to raise_error(FrozenError)
      expect { frozen_instance.after_fork {} }.to raise_error(FrozenError)

      src = described_class["custom_process"]
      expect(src).to be(original)
      expect(src).not_to be(frozen_instance)
    end

    context "when the given consumers array are not Lepus::Consumer classes" do
      it "raises an ArgumentError" do
        expect {
          described_class.immutate_with("invalid_process", consumers: [String])
        }.to raise_error(ArgumentError, /is not a subclass of Lepus::Consumer/)
      end
    end
  end

  describe "#initialize" do
    let(:name) { "my_process" }

    it "sets the name and default attributes" do
      expect(instance.name).to eq("my_process")
      expect(instance.pool_size).to eq(1)
      expect(instance.pool_timeout).to eq(5)
      expect(instance.consumers).to eq([])
    end
  end

  describe "#assign" do
    let(:name) { "assign_process" }

    it "assigns valid attributes from the options hash" do
      instance.assign(pool_size: 3, pool_timeout: 15)
      expect(instance.pool_size).to eq(3)
      expect(instance.pool_timeout).to eq(15)
    end

    it "raises ArgumentError for unknown attributes" do
      expect {
        instance.assign(unknown_attr: 123)
      }.to raise_error(ArgumentError, /Unknown attribute unknown_attr/)
    end
  end

  describe "#freeze_with" do
    let(:name) { "freeze_process" }
    let(:consumer_class_one) { Class.new(Lepus::Consumer) }
    let(:consumer_class_two) { Class.new(Lepus::Consumer) }
    let(:consumers) { [consumer_class_one, consumer_class_two, consumer_class_one] }

    it "sets the consumers and freezes the instance" do
      instance.freeze_with(consumers)
      expect(instance.consumers).to eq([consumer_class_one, consumer_class_two])
      expect(instance).to be_frozen
    end

    it "raises ArgumentError if any consumer is not a Lepus::Consumer subclass" do
      expect {
        instance.freeze_with([String])
      }.to raise_error(ArgumentError, /is not a subclass of Lepus::Consumer/)
    end
  end

  describe "#instantiate_process" do
    it "returns a new Lepus::Consumers::Worker instance configured with this definition" do
      definer = described_class["instantiate_process"]
      process = definer.instantiate_process
      expect(process).to be_a(Lepus::Consumers::Worker)
      expect(definer.instantiate_process).not_to be(process)
    end
  end

  describe "#before_fork and #after_fork" do
    let(:name) { "callback_process" }

    it "registers and runs before_fork and after_fork callbacks" do
      before_called = false
      after_called = false

      instance.before_fork { before_called = true }
      instance.after_fork { after_called = true }

      expect(before_called).to be(false)
      expect(after_called).to be(false)

      instance.run_process_callbacks(:before_fork)
      expect(before_called).to be(true)
      expect(after_called).to be(false)

      instance.run_process_callbacks(:after_fork)
      expect(after_called).to be(true)
    end

    it "does nothing if no callbacks are registered" do
      expect { instance.run_process_callbacks(:before_fork) }.not_to raise_error
      expect { instance.run_process_callbacks(:after_fork) }.not_to raise_error
    end
  end
end
