# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Producers::Hooks do
  subject(:hooks) { Lepus::Producers }

  let(:test_producer_class) do
    Class.new(Lepus::Producer) do
      configure(exchange: "test_exchange")
    end
  end

  let(:another_producer_class) do
    Class.new(Lepus::Producer) do
      configure(exchange: "another_exchange")
    end
  end

  let(:abstract_producer_class) do
    Class.new(Lepus::Producer) do
      self.abstract_class = true
    end
  end

  before do
    Lepus::Producers::Hooks.reset!
    stub_const("TestProducerClass", test_producer_class)
    stub_const("AnotherProducerClass", another_producer_class)
    stub_const("AbstractProducerClass", abstract_producer_class)
  end

  after do
    Lepus::Producers::Hooks.reset!
  end

  describe "#enable!" do
    context "when no producers are specified" do
      it "enables all producers" do
        subject.enable!

        expect(subject.enabled?(test_producer_class)).to be true
        expect(subject.enabled?(another_producer_class)).to be true
        expect(subject.disabled?(test_producer_class)).to be false
        expect(subject.disabled?(another_producer_class)).to be false
      end
    end

    context "when specific producers are specified" do
      it "enables only the specified producers" do
        subject.enable!(test_producer_class)

        expect(subject.enabled?(test_producer_class)).to be true
        expect(subject.disabled?(test_producer_class)).to be false
      end

      it "enables multiple producers" do
        subject.enable!(test_producer_class, another_producer_class)

        expect(subject.enabled?(test_producer_class, another_producer_class)).to be true
      end
    end
  end

  describe "#disable!" do
    context "when no producers are specified" do
      it "disables all producers" do
        subject.disable!

        expect(subject.disabled?).to be true
        expect(subject.enabled?).to be false
      end
    end

    context "when specific producers are specified" do
      it "disables only the specified producers" do
        subject.disable!(test_producer_class)

        expect(subject.disabled?(test_producer_class)).to be true
        expect(subject.enabled?(test_producer_class)).to be false
      end

      it "disables multiple producers" do
        subject.disable!(test_producer_class, another_producer_class)

        expect(subject.disabled?(test_producer_class, another_producer_class)).to be true
      end
    end
  end

  describe "#enabled?" do
    context "when no producers are specified" do
      it "returns true when all producers are enabled" do
        subject.enable!
        expect(subject.enabled?).to be true
      end

      it "returns false when any producer is disabled" do
        subject.disable!(test_producer_class)
        expect(subject.enabled?).to be false
      end
    end

    context "when specific producers are specified" do
      it "returns true when all specified producers are enabled" do
        subject.enable!(test_producer_class, another_producer_class)
        expect(subject.enabled?(test_producer_class, another_producer_class)).to be true
      end

      it "returns false when any specified producer is disabled" do
        subject.enable!(test_producer_class)
        subject.disable!(another_producer_class)
        expect(subject.enabled?(test_producer_class, another_producer_class)).to be false
      end
    end
  end

  describe "#disabled?" do
    context "when no producers are specified" do
      it "returns true when all producers are disabled" do
        subject.disable!
        expect(subject.disabled?).to be true
      end

      it "returns false when any producer is enabled" do
        subject.enable!(test_producer_class)
        expect(subject.disabled?).to be false
      end
    end

    context "when specific producers are specified" do
      it "returns true when all specified producers are disabled" do
        subject.disable!(test_producer_class, another_producer_class)
        expect(subject.disabled?(test_producer_class, another_producer_class)).to be true
      end

      it "returns false when any specified producer is enabled" do
        subject.disable!(test_producer_class)
        subject.enable!(another_producer_class)
        expect(subject.disabled?(test_producer_class, another_producer_class)).to be false
      end
    end
  end

  describe "#without_publishing" do
    it "disables publishing for the block execution" do
      subject.enable!

      subject.without_publishing do
        expect(subject.disabled?).to be true
      end
    end

    it "disables specific producers for the block execution" do
      subject.enable!

      subject.without_publishing(test_producer_class) do
        expect(subject.disabled?(test_producer_class)).to be true
      end
    end

    it "restores the previous state after block execution" do
      subject.enable!
      original_enabled_state = subject.enabled?

      subject.without_publishing do
        expect(subject.disabled?).to be true
      end

      expect(subject.enabled?).to eq(original_enabled_state)
    end

    it "restores the previous state even if an exception is raised" do
      subject.enable!
      original_enabled_state = subject.enabled?

      expect do
        subject.without_publishing do
          raise StandardError, "Test error"
        end
      end.to raise_error(StandardError, "Test error")

      expect(subject.enabled?).to eq(original_enabled_state)
    end

    it "yields the block" do
      block_called = false

      subject.without_publishing do
        block_called = true
      end

      expect(block_called).to be true
    end
  end

  describe "#with_publishing" do
    it "enables publishing for the block execution" do
      subject.disable!

      subject.with_publishing do
        expect(subject.enabled?).to be true
      end
    end

    it "enables specific producers for the block execution" do
      subject.disable!

      subject.with_publishing(test_producer_class) do
        expect(subject.enabled?(test_producer_class)).to be true
        expect(subject.disabled?(another_producer_class)).to be true
      end
    end

    it "restores the previous state after block execution" do
      subject.disable!
      original_disabled_state = subject.disabled?

      subject.with_publishing do
        # State is changed during block
        expect(subject.enabled?).to be true
      end

      expect(subject.disabled?).to eq(original_disabled_state)
    end

    it "restores the previous state even if an exception is raised" do
      subject.disable!
      original_disabled_state = subject.disabled?

      expect do
        subject.with_publishing do
          raise StandardError, "Test error"
        end
      end.to raise_error(StandardError, "Test error")

      expect(subject.disabled?).to eq(original_disabled_state)
    end

    it "yields the block" do
      block_called = false

      subject.with_publishing do
        block_called = true
      end

      expect(block_called).to be true
    end
  end

  describe "error handling" do
    context "when invalid producer is provided" do
      it "raises ArgumentError for non-class, non-string, non-symbol values" do
        expect { subject.enable!(123) }.to raise_error(ArgumentError, "Invalid producer name: 123")
        expect { subject.disable!(123) }.to raise_error(ArgumentError, "Invalid producer name: 123")
      end

      it "raises ArgumentError for non-producer classes" do
        non_producer_class = Class.new

        expect { subject.enable!(non_producer_class) }.to raise_error(ArgumentError, "Invalid producer class: #{non_producer_class.inspect}")
        expect { subject.disable!(non_producer_class) }.to raise_error(ArgumentError, "Invalid producer class: #{non_producer_class.inspect}")
      end

      it "raises NameError for non-existent constant names" do
        expect { subject.enable!("NonExistentProducer") }.to raise_error(NameError)
        expect { subject.disable!("NonExistentProducer") }.to raise_error(NameError)
      end
    end
  end

  describe "thread safety" do
    it "maintains separate state per thread" do
      thread1_enabled = nil
      thread2_enabled = nil

      thread1 = Thread.new do
        subject.enable!(test_producer_class)
        thread1_enabled = subject.enabled?(test_producer_class)
      end

      thread2 = Thread.new do
        subject.disable!(test_producer_class)
        thread2_enabled = subject.enabled?(test_producer_class)
      end

      thread1.join
      thread2.join

      expect(thread1_enabled).to be true
      expect(thread2_enabled).to be false
    end
  end
end
