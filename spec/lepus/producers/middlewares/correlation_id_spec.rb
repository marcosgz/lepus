# frozen_string_literal: true

require "spec_helper"
require "lepus/producers/middlewares/correlation_id"

RSpec.describe Lepus::Producers::Middlewares::CorrelationId do
  describe "#call" do
    let(:middleware) { described_class.new(**options) }
    let(:options) { {} }

    def build_message(payload = "test", correlation_id: nil)
      delivery_info = Lepus::Message::DeliveryInfo.new(
        exchange: "test_exchange",
        routing_key: "test.key"
      )
      metadata = Lepus::Message::Metadata.new(correlation_id: correlation_id)
      Lepus::Message.new(delivery_info, metadata, payload)
    end

    it "generates a correlation_id when missing" do
      message = build_message
      result_correlation_id = nil

      middleware.call(message, proc { |msg|
        result_correlation_id = msg.metadata.correlation_id
        :ok
      })

      expect(result_correlation_id).not_to be_nil
      expect(result_correlation_id).to match(/^[0-9a-f-]{36}$/)
    end

    it "preserves existing correlation_id" do
      message = build_message(correlation_id: "existing-id")
      result_correlation_id = nil

      middleware.call(message, proc { |msg|
        result_correlation_id = msg.metadata.correlation_id
        :ok
      })

      expect(result_correlation_id).to eq("existing-id")
    end

    it "treats empty string correlation_id as missing" do
      message = build_message(correlation_id: "")
      result_correlation_id = nil

      middleware.call(message, proc { |msg|
        result_correlation_id = msg.metadata.correlation_id
        :ok
      })

      expect(result_correlation_id).not_to eq("")
      expect(result_correlation_id).to match(/^[0-9a-f-]{36}$/)
    end

    it "returns the result of the next middleware" do
      result = middleware.call(build_message, proc { |_| :success })

      expect(result).to eq(:success)
    end

    context "with custom generator" do
      let(:options) { {generator: -> { "custom-id-123" }} }

      it "uses the custom generator" do
        message = build_message
        result_correlation_id = nil

        middleware.call(message, proc { |msg|
          result_correlation_id = msg.metadata.correlation_id
          :ok
        })

        expect(result_correlation_id).to eq("custom-id-123")
      end
    end

    it "preserves other metadata fields" do
      delivery_info = Lepus::Message::DeliveryInfo.new(
        exchange: "test_exchange",
        routing_key: "test.key"
      )
      metadata = Lepus::Message::Metadata.new(
        content_type: "application/json",
        headers: {"x-custom" => "value"}
      )
      message = Lepus::Message.new(delivery_info, metadata, "payload")

      result_metadata = nil

      middleware.call(message, proc { |msg|
        result_metadata = msg.metadata
        :ok
      })

      expect(result_metadata.content_type).to eq("application/json")
      expect(result_metadata.headers).to eq({"x-custom" => "value"})
    end
  end
end
