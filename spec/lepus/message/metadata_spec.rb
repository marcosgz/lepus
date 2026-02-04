# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Message::Metadata do
  describe ".from_bunny" do
    subject(:metadata) { described_class.from_bunny(bunny_metadata) }

    let(:bunny_metadata) do
      instance_double(
        Bunny::MessageProperties,
        content_type: "application/json",
        content_encoding: "utf-8",
        headers: {"x-custom" => "value"},
        delivery_mode: 2,
        priority: 5,
        correlation_id: "corr-123",
        reply_to: "reply_queue",
        expiration: "60000",
        message_id: "msg-456",
        timestamp: 1234567890,
        type: "event",
        user_id: "guest",
        app_id: "my_app",
        cluster_id: nil
      )
    end

    it "extracts all attributes from Bunny object" do
      expect(metadata.content_type).to eq("application/json")
      expect(metadata.content_encoding).to eq("utf-8")
      expect(metadata.headers).to eq({"x-custom" => "value"})
      expect(metadata.delivery_mode).to eq(2)
      expect(metadata.priority).to eq(5)
      expect(metadata.correlation_id).to eq("corr-123")
      expect(metadata.reply_to).to eq("reply_queue")
      expect(metadata.expiration).to eq("60000")
      expect(metadata.message_id).to eq("msg-456")
      expect(metadata.timestamp).to eq(1234567890)
      expect(metadata.type).to eq("event")
      expect(metadata.user_id).to eq("guest")
      expect(metadata.app_id).to eq("my_app")
      expect(metadata.cluster_id).to be_nil
    end
  end

  describe "#to_h" do
    subject(:metadata) do
      described_class.new(
        content_type: "text/plain",
        headers: {"key" => "value"}
      )
    end

    it "returns a hash representation with all keys" do
      hash = metadata.to_h
      expect(hash[:content_type]).to eq("text/plain")
      expect(hash[:headers]).to eq({"key" => "value"})
      expect(hash).to have_key(:content_encoding)
      expect(hash).to have_key(:delivery_mode)
    end
  end

  describe "#[]" do
    subject(:metadata) do
      described_class.new(
        content_type: "application/json",
        headers: {"x-custom" => "value"}
      )
    end

    it "allows hash-style access with symbol keys" do
      expect(metadata[:content_type]).to eq("application/json")
      expect(metadata[:headers]).to eq({"x-custom" => "value"})
    end

    it "allows hash-style access with string keys" do
      expect(metadata["content_type"]).to eq("application/json")
    end

    it "returns nil for unknown keys" do
      expect(metadata[:unknown_key]).to be_nil
    end

    context "with custom attributes" do
      subject(:metadata) do
        described_class.new(
          content_type: "application/json",
          custom_attr: "custom_value"
        )
      end

      it "allows access to custom attributes" do
        expect(metadata[:custom_attr]).to eq("custom_value")
      end
    end
  end

  describe "custom attributes" do
    subject(:metadata) do
      described_class.new(
        content_type: "text/plain",
        custom_attr: "value",
        another_custom: 123
      )
    end

    it "supports method-style access to custom attributes" do
      expect(metadata.custom_attr).to eq("value")
      expect(metadata.another_custom).to eq(123)
    end

    it "includes custom attributes in to_h" do
      expect(metadata.to_h).to include(custom_attr: "value", another_custom: 123)
    end

    it "supports hash-style access to custom attributes" do
      expect(metadata[:custom_attr]).to eq("value")
      expect(metadata["another_custom"]).to eq(123)
    end
  end

  describe "#eql?" do
    let(:equal_metadata) { described_class.new(content_type: "application/json", headers: {"a" => 1}) }
    let(:same_metadata) { described_class.new(content_type: "application/json", headers: {"a" => 1}) }
    let(:different_metadata) { described_class.new(content_type: "text/plain", headers: {"a" => 1}) }

    it "returns true for equal objects" do
      expect(equal_metadata).to eq(same_metadata)
    end

    it "returns false for different objects" do
      expect(equal_metadata).not_to eq(different_metadata)
    end
  end
end
