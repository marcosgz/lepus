# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Message do
  let(:delivery_info) { instance_double(Bunny::DeliveryInfo, to_h: {exchange: "test_exchange", routing_key: "test_key"}) }
  let(:metadata) { instance_double(Bunny::DeliveryInfo, to_h: {content_type: "application/json", timestamp: 1234567890}) }
  let(:payload) { {key: "value"} }
  let(:message) { described_class.new(delivery_info, metadata, payload) }

  describe "#to_h" do
    subject(:msg) { message.to_h }

    context "when all attributes are present" do
      it "returns a hash representation of the message" do
        expect(msg).to eq({
          delivery: {exchange: "test_exchange", routing_key: "test_key"},
          metadata: {content_type: "application/json", timestamp: 1234567890},
          payload: {key: "value"}
        })
      end
    end

    context "when delivery_info is nil" do
      let(:delivery_info) { nil }

      it "returns nil for the delivery key" do
        expect(msg).to eq({
          delivery: nil,
          metadata: {content_type: "application/json", timestamp: 1234567890},
          payload: {key: "value"}
        })
      end
    end

    context "when metadata is nil" do
      let(:metadata) { nil }

      it "returns nil for the metadata key" do
        expect(msg).to eq({
          delivery: {exchange: "test_exchange", routing_key: "test_key"},
          metadata: nil,
          payload: {key: "value"}
        })
      end
    end

    context "when payload is nil" do
      let(:payload) { nil }

      it "returns nil for the payload key" do
        expect(msg).to eq({
          delivery: {exchange: "test_exchange", routing_key: "test_key"},
          metadata: {content_type: "application/json", timestamp: 1234567890},
          payload: nil
        })
      end
    end
  end
end
