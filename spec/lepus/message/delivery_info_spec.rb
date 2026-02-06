# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Message::DeliveryInfo do
  describe ".from_bunny" do
    subject(:delivery_info) { described_class.from_bunny(bunny_delivery_info) }

    let(:bunny_delivery_info) do
      instance_double(
        Bunny::DeliveryInfo,
        delivery_tag: 42,
        redelivered: true,
        exchange: "my_exchange",
        routing_key: "my.routing.key",
        consumer_tag: "my_consumer_tag"
      )
    end

    it "extracts all attributes from Bunny object" do
      expect(delivery_info.delivery_tag).to eq(42)
      expect(delivery_info.redelivered).to be(true)
      expect(delivery_info.exchange).to eq("my_exchange")
      expect(delivery_info.routing_key).to eq("my.routing.key")
      expect(delivery_info.consumer_tag).to eq("my_consumer_tag")
    end
  end

  describe "#to_h" do
    subject(:delivery_info) do
      described_class.new(
        delivery_tag: 1,
        redelivered: false,
        exchange: "test",
        routing_key: "key",
        consumer_tag: "tag"
      )
    end

    it "returns a hash representation" do
      expect(delivery_info.to_h).to eq({
        delivery_tag: 1,
        redelivered: false,
        exchange: "test",
        routing_key: "key",
        consumer_tag: "tag"
      })
    end
  end

  describe "#[]" do
    subject(:delivery_info) do
      described_class.new(
        delivery_tag: 42,
        exchange: "my_exchange",
        routing_key: "my.key"
      )
    end

    it "allows hash-style access with symbol keys" do
      expect(delivery_info[:delivery_tag]).to eq(42)
      expect(delivery_info[:exchange]).to eq("my_exchange")
    end

    it "allows hash-style access with string keys" do
      expect(delivery_info["routing_key"]).to eq("my.key")
    end

    it "returns nil for unknown keys" do
      expect(delivery_info[:unknown_key]).to be_nil
    end

    context "with custom attributes" do
      subject(:delivery_info) do
        described_class.new(
          delivery_tag: 1,
          custom_attr: "custom_value"
        )
      end

      it "allows access to custom attributes" do
        expect(delivery_info[:custom_attr]).to eq("custom_value")
      end
    end
  end

  describe "custom attributes" do
    subject(:delivery_info) do
      described_class.new(
        delivery_tag: 99,
        custom_attr: "value",
        another_custom: 456
      )
    end

    it "supports method-style access to custom attributes" do
      expect(delivery_info.custom_attr).to eq("value")
      expect(delivery_info.another_custom).to eq(456)
    end

    it "includes custom attributes in to_h" do
      expect(delivery_info.to_h).to include(custom_attr: "value", another_custom: 456)
    end

    it "supports hash-style access to custom attributes" do
      expect(delivery_info[:custom_attr]).to eq("value")
      expect(delivery_info["another_custom"]).to eq(456)
    end
  end

  describe "#eql?" do
    let(:equal_delivery_info) { described_class.new(delivery_tag: 1, exchange: "test") }
    let(:same_delivery_info) { described_class.new(delivery_tag: 1, exchange: "test") }
    let(:different_delivery_info) { described_class.new(delivery_tag: 2, exchange: "test") }

    it "returns true for equal objects" do
      expect(equal_delivery_info).to eq(same_delivery_info)
    end

    it "returns false for different objects" do
      expect(equal_delivery_info).not_to eq(different_delivery_info)
    end
  end
end
