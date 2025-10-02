# frozen_string_literal: true

require "spec_helper"
require "lepus/middlewares/json"

RSpec.describe Lepus::Middlewares::JSON do
  describe "#call" do
    let(:app) { proc { :result } }
    let(:middleware) { described_class.new(app, **options) }
    let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
    let(:metadata) { instance_double(Bunny::MessageProperties) }
    let(:payload) { MultiJson.dump({my: "payload"}) }
    let(:error_handler) { proc { :error_handler_result } }
    let(:options) { {on_error: error_handler} }
    let(:message) do
      Lepus::Message.new(delivery_info, metadata, payload)
    end

    it "returns the result of the downstream middleware" do
      expect(middleware.call(message)).to eq(:result)
    end

    it "calls the next middleware with a parsed payload" do
      received_message = nil
      app = proc { |msg| received_message = msg; :ok }
      middleware = described_class.new(app, **options)

      result = middleware.call(message)

      expect(result).to eq(:ok)
      expect(received_message.payload).to eq("my" => "payload")
    end

    it "does not mutate the original message and passes a new one downstream" do
      received_message = nil
      app = proc { |msg| received_message = msg; :ok }
      middleware = described_class.new(app, **options)

      result = middleware.call(message)

      expect(result).to eq(:ok)
      expect(message.payload).to eq(payload)
      expect(received_message).not_to equal(message)
    end

    it "preserves delivery_info and metadata when forwarding the message" do
      received_message = nil
      app = proc { |msg| received_message = msg; :ok }
      middleware = described_class.new(app, **options)

      middleware.call(message)

      expect(received_message.delivery_info).to equal(delivery_info)
      expect(received_message.metadata).to equal(metadata)
    end

    it "preserves consumer_class when forwarding the message" do
      consumer_class = Class.new
      message.consumer_class = consumer_class
      received_message = nil
      app = proc { |msg| received_message = msg; :ok }
      middleware = described_class.new(app, **options)

      middleware.call(message)

      expect(received_message.consumer_class).to equal(consumer_class)
    end

    it "can optionally symbolize keys" do
      received_message = nil
      app = proc { |msg| received_message = msg; :ok }
      middleware = described_class.new(
        app,
        symbolize_keys: true,
        on_error: error_handler
      )

      result = middleware.call(message)

      expect(result).to eq(:ok)
      expect(received_message.payload).to eq(my: "payload")
    end

    context "when initialized without error handler" do
      let(:options) { {} }
      let(:payload) { "This is not JSON" }

      it "does not raise" do
        expect { middleware }.not_to raise_error
      end

      it "rejects when encountering an error" do
        expect(middleware.call(message)).to eq(:reject)
      end

      it "does not call the next middleware when parsing fails" do
        app = proc { raise "next middleware should not be called" }
        middleware = described_class.new(app, **options)

        expect(middleware.call(message)).to eq(:reject)
      end
    end

    it "does not catch an error down the line" do
      app = proc { raise RuntimeError }
      middleware = described_class.new(app, **options)

      expect { middleware.call(message) }.to raise_error(RuntimeError)
    end

    context "when encountering an error" do
      let(:payload) { "This is not JSON" }

      it "returns the result of the error handler" do
        expect(middleware.call(message)).to eq(:error_handler_result)
      end

      it "calls the error handler with the error" do
        expect(error_handler).to receive(:call).with(
          instance_of(MultiJson::ParseError)
        )

        middleware.call(message)
      end

      it "does not call the next middleware when parsing fails" do
        app = proc { raise "next middleware should not be called" }
        middleware = described_class.new(app, **options)

        expect(middleware.call(message)).to eq(:error_handler_result)
      end
    end
  end
end
