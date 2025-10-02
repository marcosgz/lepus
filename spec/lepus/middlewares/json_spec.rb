# frozen_string_literal: true

require "spec_helper"
require "lepus/middlewares/json"

RSpec.describe Lepus::Middlewares::JSON do
  describe "#call" do
    let(:middleware) { described_class.new(**options) }
    let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
    let(:metadata) { instance_double(Bunny::MessageProperties) }
    let(:payload) { MultiJson.dump({my: "payload"}) }
    let(:error_handler) { proc { :error_handler_result } }
    let(:options) { {on_error: error_handler} }
    let(:message) do
      Lepus::Message.new(delivery_info, metadata, payload)
    end

    it "returns the result of the downstream middleware" do
      expect(
        middleware.call(message, proc { :moep })
      ).to eq(:moep)
    end

    it "calls the next middleware with a parsed payload" do
      expect do |b|
        proc =
          proc do |message, _block|
            expect(message.payload).to eq("my" => "payload")
            Proc.new(&b).call
          end
        middleware.call(message, proc)
      end.to yield_control
    end

    it "does not mutate the original message and passes a new one downstream" do
      received_message = nil

      result = middleware.call(message, proc { |msg, _blk|
                                          received_message = msg
                                          :ok
                                        })

      expect(result).to eq(:ok)
      expect(message.payload).to eq(payload)
      expect(received_message).not_to equal(message)
    end

    it "preserves delivery_info and metadata when forwarding the message" do
      received_message = nil

      middleware.call(message, proc { |msg, _blk|
                                 received_message = msg
                                 :ok
                               })

      expect(received_message.delivery_info).to equal(delivery_info)
      expect(received_message.metadata).to equal(metadata)
    end

    it "preserves consumer_class when forwarding the message" do
      consumer_class = Class.new
      message.consumer_class = consumer_class
      received_message = nil

      middleware.call(message, proc { |msg, _blk|
                                 received_message = msg
                                 :ok
                               })

      expect(received_message.consumer_class).to equal(consumer_class)
    end

    it "can optionally symbolize keys" do
      middleware =
        described_class.new(
          symbolize_keys: true,
          on_error: error_handler
        )
      expect do |b|
        proc =
          proc do |message, _block|
            expect(message.payload).to eq(my: "payload")
            Proc.new(&b).call
          end
        middleware.call(message, proc)
      end.to yield_control
    end

    context "when initialized without error handler" do
      let(:options) { {} }
      let(:payload) { "This is not JSON" }

      it "does not raise" do
        expect { middleware }.not_to raise_error
      end

      it "rejects when encountering an error" do
        expect(
          middleware.call(
            message,
            proc { :success }
          )
        ).to eq(:reject)
      end

      it "does not call the next middleware when parsing fails" do
        next_middleware = proc { |_msg, _blk| raise "next middleware should not be called" }

        expect(
          middleware.call(
            message,
            next_middleware
          )
        ).to eq(:reject)
      end
    end

    it "does not catch an error down the line" do
      expect {
        middleware.call(message, proc { raise })
      }.to raise_error(RuntimeError)
    end

    context "when encountering an error" do
      let(:payload) { "This is not JSON" }

      it "returns the result of the error handler" do
        expect(
          middleware.call(
            message,
            proc { :success }
          )
        ).to eq(:error_handler_result)
      end

      it "calls the error handler with the error" do
        expect(error_handler).to receive(:call).with(
          instance_of(MultiJson::ParseError)
        )

        middleware.call(message, proc { :success })
      end

      it "does not call the next middleware when parsing fails" do
        next_middleware = proc { |_msg, _blk| raise "next middleware should not be called" }

        expect(
          middleware.call(
            message,
            next_middleware
          )
        ).to eq(:error_handler_result)
      end
    end
  end
end
