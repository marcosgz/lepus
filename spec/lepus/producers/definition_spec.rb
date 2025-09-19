# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Producers::Definition do
  describe "#initialize" do
    context "with string exchange name" do
      it "creates definition with default exchange options" do
        definition = described_class.new(exchange: "my_exchange")

        expect(definition.exchange_name).to eq("my_exchange")
        expect(definition.exchange_options).to include(
          type: :topic,
          durable: true,
          auto_delete: false
        )
      end
    end

    context "with hash exchange configuration" do
      it "creates definition with custom exchange options" do
        definition = described_class.new(
          exchange: {
            name: "custom_exchange",
            type: :direct,
            durable: false,
            auto_delete: true
          }
        )

        expect(definition.exchange_name).to eq("custom_exchange")
        expect(definition.exchange_options).to include(
          type: :direct,
          durable: false,
          auto_delete: true
        )
      end
    end

    context "with publish options" do
      it "creates definition with custom publish options" do
        definition = described_class.new(
          exchange: "test_exchange",
          publish: {
            persistent: false,
            mandatory: true,
            immediate: true
          }
        )

        expect(definition.publish_options).to include(
          persistent: false,
          mandatory: true,
          immediate: true
        )
      end
    end

    context "with no exchange name" do
      it "raises an error when accessing exchange_name" do
        definition = described_class.new
        expect { definition.exchange_name }.to raise_error(Lepus::InvalidProducerConfigError, "Exchange name is required")
      end
    end

    context "with empty options" do
      it "uses default values" do
        definition = described_class.new(exchange: "default_exchange")

        expect(definition.exchange_options).to include(
          type: :topic,
          durable: true,
          auto_delete: false
        )
        expect(definition.publish_options).to include(
          persistent: true
        )
      end
    end
  end

  describe "#exchange_args" do
    it "returns exchange name and options without name key" do
      definition = described_class.new(
        exchange: {
          name: "test_exchange",
          type: :fanout,
          durable: false
        }
      )

      name, options = definition.exchange_args
      expect(name).to eq("test_exchange")
      expect(options).to eq(type: :fanout, durable: false, auto_delete: false)
    end
  end

  describe "declaration_config normalization" do
    context "with string value" do
      it "converts string to hash with name key" do
        definition = described_class.new(exchange: "string_exchange")
        expect(definition.exchange_name).to eq("string_exchange")
      end
    end

    context "with hash value" do
      it "uses hash as is" do
        definition = described_class.new(exchange: {name: "hash_exchange", type: :direct})
        expect(definition.exchange_name).to eq("hash_exchange")
        expect(definition.exchange_options).to include(type: :direct)
      end
    end

    context "with nil value" do
      it "uses empty hash" do
        definition = described_class.new(exchange: nil)
        expect { definition.exchange_name }.to raise_error(Lepus::InvalidProducerConfigError)
      end
    end

    context "with true value" do
      it "uses empty hash" do
        definition = described_class.new(exchange: true)
        expect { definition.exchange_name }.to raise_error(Lepus::InvalidProducerConfigError)
      end
    end
  end
end
