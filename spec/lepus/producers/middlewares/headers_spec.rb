# frozen_string_literal: true

require "spec_helper"
require "lepus/producers/middlewares/headers"

RSpec.describe Lepus::Producers::Middlewares::Headers do
  describe "#call" do
    let(:middleware) { described_class.new(**options) }
    let(:options) { {defaults: default_headers} }
    let(:default_headers) { {"app" => "test-service", "version" => "1.0"} }

    def build_message(payload = "test", headers: nil)
      delivery_info = Lepus::Message::DeliveryInfo.new(
        exchange: "test_exchange",
        routing_key: "test.key"
      )
      metadata = Lepus::Message::Metadata.new(headers: headers)
      Lepus::Message.new(delivery_info, metadata, payload)
    end

    it "adds default headers to the message" do
      message = build_message
      result_headers = nil

      middleware.call(message, proc { |msg|
        result_headers = msg.metadata.headers
        :ok
      })

      expect(result_headers).to include("app" => "test-service", "version" => "1.0")
    end

    it "preserves existing headers" do
      message = build_message(headers: {"x-existing" => "value"})
      result_headers = nil

      middleware.call(message, proc { |msg|
        result_headers = msg.metadata.headers
        :ok
      })

      expect(result_headers).to include(
        "app" => "test-service",
        "version" => "1.0",
        "x-existing" => "value"
      )
    end

    it "existing headers take precedence over defaults" do
      message = build_message(headers: {"app" => "overridden"})
      result_headers = nil

      middleware.call(message, proc { |msg|
        result_headers = msg.metadata.headers
        :ok
      })

      expect(result_headers["app"]).to eq("overridden")
    end

    it "returns the result of the next middleware" do
      result = middleware.call(build_message, proc { |_| :success })

      expect(result).to eq(:success)
    end

    context "with Proc values" do
      let(:default_headers) do
        {
          "timestamp" => -> { "2024-01-01T00:00:00Z" },
          "request_id" => ->(msg) { "req-#{msg.payload}" }
        }
      end

      it "evaluates Proc values at call time" do
        message = build_message("123")
        result_headers = nil

        middleware.call(message, proc { |msg|
          result_headers = msg.metadata.headers
          :ok
        })

        expect(result_headers["timestamp"]).to eq("2024-01-01T00:00:00Z")
        expect(result_headers["request_id"]).to eq("req-123")
      end
    end

    context "with symbol keys" do
      let(:default_headers) { {app: "test-service"} }

      it "converts symbol keys to strings" do
        message = build_message
        result_headers = nil

        middleware.call(message, proc { |msg|
          result_headers = msg.metadata.headers
          :ok
        })

        expect(result_headers).to include("app" => "test-service")
      end
    end

    context "with no default headers" do
      let(:options) { {} }

      it "passes through without modification" do
        message = build_message(headers: {"x-existing" => "value"})
        result_headers = nil

        middleware.call(message, proc { |msg|
          result_headers = msg.metadata.headers
          :ok
        })

        expect(result_headers).to eq("x-existing" => "value")
      end
    end
  end
end
