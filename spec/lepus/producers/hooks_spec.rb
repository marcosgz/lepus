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

  let(:shared_exchange_producer_class) do
    Class.new(Lepus::Producer) do
      configure(exchange: "test_exchange")
    end
  end

  let(:abstract_producer_class) do
    Class.new(Lepus::Producer) do
      self.abstract_class = true
    end
  end

  before do
    described_class.reset!
    stub_const("TestProducerClass", test_producer_class)
    stub_const("AnotherProducerClass", another_producer_class)
    stub_const("SharedExchangeProducerClass", shared_exchange_producer_class)
    stub_const("AbstractProducerClass", abstract_producer_class)
  end

  after do
    described_class.reset!
  end

  describe "#enable!" do
    context "when no targets are specified" do
      it "enables all producers" do
        subject.enable!

        expect(subject.enabled?(test_producer_class)).to be true
        expect(subject.enabled?(another_producer_class)).to be true
        expect(subject.enabled?(shared_exchange_producer_class)).to be true
        expect(subject.disabled?(test_producer_class)).to be false
        expect(subject.disabled?(another_producer_class)).to be false
        expect(subject.disabled?(shared_exchange_producer_class)).to be false
      end
    end

    context "when specific producer classes are specified" do
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

    context "when exchange names are specified" do
      it "enables exchange by string name" do
        subject.enable!("test_exchange")

        expect(subject.exchange_enabled?("test_exchange")).to be true
        # Other exchanges should remain in default state (enabled)
        expect(subject.exchange_enabled?("another_exchange")).to be true
        expect(subject.exchange_enabled?("unknown_exchange")).to be true
      end

      it "enables exchange by symbol name" do
        subject.enable!(:test_exchange)

        expect(subject.exchange_enabled?("test_exchange")).to be true
      end

      it "enables multiple exchanges" do
        subject.enable!("test_exchange", "another_exchange")

        expect(subject.exchange_enabled?("test_exchange")).to be true
        expect(subject.exchange_enabled?("another_exchange")).to be true
      end

      it "enables unknown exchanges" do
        subject.enable!("unknown_exchange")

        expect(subject.exchange_enabled?("unknown_exchange")).to be true
      end
    end

    context "when mixing producer classes and exchange names" do
      it "enables both producers and exchanges" do
        subject.enable!(test_producer_class, "unknown_exchange")

        expect(subject.enabled?(test_producer_class)).to be true
        expect(subject.exchange_enabled?("unknown_exchange")).to be true
      end
    end
  end

  describe "#disable!" do
    context "when no targets are specified" do
      it "disables all producers" do
        subject.disable!

        expect(subject.disabled?).to be true
        expect(subject.enabled?).to be false
        expect(subject.disabled?(test_producer_class)).to be true
        expect(subject.disabled?(another_producer_class)).to be true
        expect(subject.disabled?(shared_exchange_producer_class)).to be true
      end
    end

    context "when specific producer classes are specified" do
      it "disables only the specified producers" do
        subject.disable!(test_producer_class)

        expect(subject.disabled?(test_producer_class)).to be true
        expect(subject.enabled?(test_producer_class)).to be false
        expect(subject.enabled?(another_producer_class)).to be true # Not disabled
      end

      it "disables multiple producers" do
        subject.disable!(test_producer_class, another_producer_class)

        expect(subject.disabled?(test_producer_class, another_producer_class)).to be true
      end
    end

    context "when exchange names are specified" do
      it "disables exchange by string name" do
        subject.disable!("test_exchange")

        expect(subject.exchange_enabled?("test_exchange")).to be false
        # Other exchanges should remain enabled
        expect(subject.exchange_enabled?("another_exchange")).to be true
        expect(subject.exchange_enabled?("unknown_exchange")).to be true
      end

      it "disables exchange by symbol name" do
        subject.disable!(:test_exchange)

        expect(subject.exchange_enabled?("test_exchange")).to be false
      end

      it "disables multiple exchanges" do
        subject.disable!("test_exchange", "another_exchange")

        expect(subject.exchange_enabled?("test_exchange")).to be false
        expect(subject.exchange_enabled?("another_exchange")).to be false
      end

      it "disables unknown exchanges" do
        subject.disable!("unknown_exchange")

        expect(subject.exchange_enabled?("unknown_exchange")).to be false
      end
    end

    context "when mixing producer classes and exchange names" do
      it "disables both producers and exchanges" do
        subject.disable!(test_producer_class, "unknown_exchange")

        expect(subject.disabled?(test_producer_class)).to be true
        expect(subject.exchange_enabled?("unknown_exchange")).to be false
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

  describe "#exchange_enabled?" do
    context "with exchanges that have known producers" do
      it "returns true when all producers using the exchange are enabled" do
        subject.enable!(test_producer_class, shared_exchange_producer_class)

        expect(subject.exchange_enabled?("test_exchange")).to be true
      end

      it "returns false when any producer using the exchange is disabled" do
        subject.disable!(test_producer_class)

        expect(subject.exchange_enabled?("test_exchange")).to be false
      end

      it "returns false when exchange is explicitly disabled" do
        subject.disable!("test_exchange")

        expect(subject.exchange_enabled?("test_exchange")).to be false
      end

      it "returns true when exchange is explicitly enabled even if producers are disabled" do
        subject.disable!(test_producer_class, shared_exchange_producer_class)
        subject.enable!("test_exchange")

        expect(subject.exchange_enabled?("test_exchange")).to be true
      end
    end

    context "with exchanges that have no known producers" do
      it "returns true by default for unknown exchanges" do
        expect(subject.exchange_enabled?("unknown_exchange")).to be true
      end

      it "returns false when unknown exchange is explicitly disabled" do
        subject.disable!("unknown_exchange")

        expect(subject.exchange_enabled?("unknown_exchange")).to be false
      end

      it "returns true when unknown exchange is explicitly enabled" do
        subject.enable!("unknown_exchange")

        expect(subject.exchange_enabled?("unknown_exchange")).to be true
      end
    end

    context "with mixed producer and exchange states" do
      it "respects exchange-level overrides" do
        # Disable all producers for test_exchange
        subject.disable!(test_producer_class, shared_exchange_producer_class)
        expect(subject.exchange_enabled?("test_exchange")).to be false

        # But enable the exchange itself
        subject.enable!("test_exchange")
        expect(subject.exchange_enabled?("test_exchange")).to be true

        # Disable the exchange again
        subject.disable!("test_exchange")
        expect(subject.exchange_enabled?("test_exchange")).to be false
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
        expect(subject.enabled?(another_producer_class)).to be true
      end
    end

    it "disables specific exchanges for the block execution" do
      subject.enable!

      subject.without_publishing("test_exchange") do
        expect(subject.exchange_enabled?("test_exchange")).to be false
        expect(subject.exchange_enabled?("another_exchange")).to be true
      end
    end

    it "disables mixed targets for the block execution" do
      subject.enable!

      subject.without_publishing(test_producer_class, "unknown_exchange") do
        expect(subject.disabled?(test_producer_class)).to be true
        expect(subject.exchange_enabled?("unknown_exchange")).to be false
        expect(subject.enabled?(another_producer_class)).to be true
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

    it "enables specific exchanges for the block execution" do
      subject.disable!

      subject.with_publishing("test_exchange") do
        expect(subject.exchange_enabled?("test_exchange")).to be true
        expect(subject.exchange_enabled?("another_exchange")).to be false
      end
    end

    it "enables mixed targets for the block execution" do
      subject.disable!

      subject.with_publishing(test_producer_class, "unknown_exchange") do
        expect(subject.enabled?(test_producer_class)).to be true
        expect(subject.exchange_enabled?("unknown_exchange")).to be true
        expect(subject.disabled?(another_producer_class)).to be true
      end
    end

    it "restores the previous state after block execution" do
      subject.disable!
      original_disabled_state = subject.disabled?

      subject.with_publishing do
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
    context "when invalid target is provided" do
      it "raises ArgumentError for non-class, non-string, non-symbol values" do
        expect { subject.enable!(123) }.to raise_error(ArgumentError, "Invalid producer or exchange name: 123")
        expect { subject.disable!(123) }.to raise_error(ArgumentError, "Invalid producer or exchange name: 123")
      end

      it "raises ArgumentError for non-producer classes" do
        non_producer_class = Class.new

        expect { subject.enable!(non_producer_class) }.to raise_error(ArgumentError, "Invalid producer class: #{non_producer_class.inspect}")
        expect { subject.disable!(non_producer_class) }.to raise_error(ArgumentError, "Invalid producer class: #{non_producer_class.inspect}")
      end

      it "accepts string and symbol as exchange names" do
        expect { subject.enable!("SomeExchange") }.not_to raise_error
        expect { subject.disable!("SomeExchange") }.not_to raise_error
        expect { subject.enable!(:SomeExchange) }.not_to raise_error
        expect { subject.disable!(:SomeExchange) }.not_to raise_error
      end

      it "accepts valid producer classes" do
        expect { subject.enable!(test_producer_class) }.not_to raise_error
        expect { subject.disable!(test_producer_class) }.not_to raise_error
      end
    end
  end

  describe "thread safety" do
    it "maintains separate state per thread" do
      thread1_enabled = nil
      thread2_enabled = nil
      thread1_exchange_enabled = nil
      thread2_exchange_enabled = nil

      thread1 = Thread.new do
        subject.enable!(test_producer_class)
        subject.enable!("test_exchange")
        thread1_enabled = subject.enabled?(test_producer_class)
        thread1_exchange_enabled = subject.exchange_enabled?("test_exchange")
      end

      thread2 = Thread.new do
        subject.disable!(test_producer_class)
        subject.disable!("test_exchange")
        thread2_enabled = subject.enabled?(test_producer_class)
        thread2_exchange_enabled = subject.exchange_enabled?("test_exchange")
      end

      thread1.join
      thread2.join

      expect(thread1_enabled).to be true
      expect(thread2_enabled).to be false
      expect(thread1_exchange_enabled).to be true
      expect(thread2_exchange_enabled).to be false
    end
  end

  describe "integration scenarios" do
    it "handles complex producer/exchange relationships" do
      # Start with all enabled
      subject.enable!

      # Disable a specific producer
      subject.disable!(test_producer_class)
      expect(subject.exchange_enabled?("test_exchange")).to be false # Because test_producer_class is disabled

      # But enable the exchange directly
      subject.enable!("test_exchange")
      expect(subject.exchange_enabled?("test_exchange")).to be true # Exchange override takes precedence

      # Disable the exchange
      subject.disable!("test_exchange")
      expect(subject.exchange_enabled?("test_exchange")).to be false

      # Re-enable the producer
      subject.enable!(test_producer_class)
      expect(subject.exchange_enabled?("test_exchange")).to be false # Exchange is still disabled
    end

    it "handles unknown exchanges independently" do
      # Unknown exchanges are enabled by default
      expect(subject.exchange_enabled?("unknown_exchange")).to be true

      # Can be disabled
      subject.disable!("unknown_exchange")
      expect(subject.exchange_enabled?("unknown_exchange")).to be false

      # Can be re-enabled
      subject.enable!("unknown_exchange")
      expect(subject.exchange_enabled?("unknown_exchange")).to be true
    end

    it "handles multiple producers sharing the same exchange" do
      # Both producers use "test_exchange"
      expect(test_producer_class.definition.exchange_name).to eq("test_exchange")
      expect(shared_exchange_producer_class.definition.exchange_name).to eq("test_exchange")

      # Disable one producer
      subject.disable!(test_producer_class)
      expect(subject.exchange_enabled?("test_exchange")).to be false

      # Enable the other producer
      subject.enable!(shared_exchange_producer_class)
      expect(subject.exchange_enabled?("test_exchange")).to be false # Still false because test_producer_class is disabled

      # Disable the second producer and enable the first
      subject.disable!(shared_exchange_producer_class)
      subject.enable!(test_producer_class)
      expect(subject.exchange_enabled?("test_exchange")).to be false # Still false because shared_exchange_producer_class is disabled

      # Enable both
      subject.enable!(test_producer_class, shared_exchange_producer_class)
      expect(subject.exchange_enabled?("test_exchange")).to be true
    end
  end
end
