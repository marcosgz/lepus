# frozen_string_literal: true

require "spec_helper"
require "lepus/producers/middlewares/json"

RSpec.describe Lepus::Producers::Middlewares::JSON do
  describe "#call" do
    let(:middleware) { described_class.new(**options) }
    let(:options) { {} }

    def build_message(payload, content_type: nil)
      delivery_info = Lepus::Message::DeliveryInfo.new(
        exchange: "test_exchange",
        routing_key: "test.key"
      )
      metadata = Lepus::Message::Metadata.new(content_type: content_type)
      Lepus::Message.new(delivery_info, metadata, payload)
    end

    context "with Hash payload" do
      let(:message) { build_message({user_id: 123, action: "created"}) }

      it "serializes the payload to JSON" do
        result_payload = nil

        middleware.call(message, proc { |msg|
          result_payload = msg.payload
          :ok
        })

        expect(result_payload).to eq('{"user_id":123,"action":"created"}')
      end

      it "sets content_type to application/json" do
        result_content_type = nil

        middleware.call(message, proc { |msg|
          result_content_type = msg.metadata.content_type
          :ok
        })

        expect(result_content_type).to eq("application/json")
      end

      it "returns the result of the next middleware" do
        result = middleware.call(message, proc { |_| :success })

        expect(result).to eq(:success)
      end

      it "does not mutate the original message" do
        original_payload = message.payload

        middleware.call(message, proc { |_| :ok })

        expect(message.payload).to eq(original_payload)
      end
    end

    context "with String payload" do
      let(:message) { build_message("plain text") }

      it "does not serialize the payload" do
        result_payload = nil

        middleware.call(message, proc { |msg|
          result_payload = msg.payload
          :ok
        })

        expect(result_payload).to eq("plain text")
      end

      it "does not change content_type" do
        result_content_type = nil

        middleware.call(message, proc { |msg|
          result_content_type = msg.metadata.content_type
          :ok
        })

        expect(result_content_type).to be_nil
      end
    end

    context "with only_hash: false" do
      let(:options) { {only_hash: false} }
      let(:message) { build_message([1, 2, 3]) }

      it "serializes non-Hash payloads" do
        result_payload = nil

        middleware.call(message, proc { |msg|
          result_payload = msg.payload
          :ok
        })

        expect(result_payload).to eq("[1,2,3]")
      end
    end

    context "with only_hash: true (default)" do
      let(:options) { {only_hash: true} }
      let(:message) { build_message([1, 2, 3]) }

      it "does not serialize non-Hash payloads" do
        result_payload = nil

        middleware.call(message, proc { |msg|
          result_payload = msg.payload
          :ok
        })

        expect(result_payload).to eq([1, 2, 3])
      end
    end

    it "preserves other metadata fields" do
      delivery_info = Lepus::Message::DeliveryInfo.new(
        exchange: "test_exchange",
        routing_key: "test.key"
      )
      metadata = Lepus::Message::Metadata.new(
        correlation_id: "abc-123",
        headers: {"x-custom" => "value"}
      )
      message = Lepus::Message.new(delivery_info, metadata, {foo: "bar"})

      result_metadata = nil

      middleware.call(message, proc { |msg|
        result_metadata = msg.metadata
        :ok
      })

      expect(result_metadata.correlation_id).to eq("abc-123")
      expect(result_metadata.headers).to eq({"x-custom" => "value"})
    end
  end
end
