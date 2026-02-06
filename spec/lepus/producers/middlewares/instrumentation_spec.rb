# frozen_string_literal: true

require "spec_helper"
require "lepus/producers/middlewares/instrumentation"

RSpec.describe Lepus::Producers::Middlewares::Instrumentation do
  describe "#call" do
    let(:middleware) { described_class.new(**options) }
    let(:options) { {} }

    def build_message(payload = "test", exchange: "test_exchange", routing_key: "test.key")
      delivery_info = Lepus::Message::DeliveryInfo.new(
        exchange: exchange,
        routing_key: routing_key
      )
      metadata = Lepus::Message::Metadata.new
      Lepus::Message.new(delivery_info, metadata, payload)
    end

    it "calls Lepus.instrument with default event name" do
      message = build_message

      expect(Lepus).to receive(:instrument).with(
        "publish",
        hash_including(
          exchange: "test_exchange",
          routing_key: "test.key",
          message: message
        )
      ).and_yield

      middleware.call(message, proc { |_| :ok })
    end

    it "returns the result of the next middleware" do
      allow(Lepus).to receive(:instrument).and_yield

      result = middleware.call(build_message, proc { |_| :success })

      expect(result).to eq(:success)
    end

    it "passes the message unchanged to the next middleware" do
      allow(Lepus).to receive(:instrument).and_yield
      message = build_message("original")
      received_message = nil

      middleware.call(message, proc { |msg|
        received_message = msg
        :ok
      })

      expect(received_message).to eq(message)
    end

    context "with custom event name" do
      let(:options) { {event_name: "producer.send"} }

      it "uses the custom event name" do
        expect(Lepus).to receive(:instrument).with(
          "producer.send",
          hash_including(exchange: "test_exchange")
        ).and_yield

        middleware.call(build_message, proc { |_| :ok })
      end
    end

    context "when next middleware raises" do
      it "propagates the exception" do
        allow(Lepus).to receive(:instrument).and_yield

        expect {
          middleware.call(build_message, proc { |_| raise "test error" })
        }.to raise_error("test error")
      end
    end
  end
end
