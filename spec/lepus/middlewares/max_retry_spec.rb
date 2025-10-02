# frozen_string_literal: true

require "spec_helper"

require "lepus/middlewares/max_retry"

RSpec.describe Lepus::Middlewares::MaxRetry do
  let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }

  let(:metadata) do
    instance_double(
      Bunny::MessageProperties,
      headers: {
        "x-death" => [
          {
            "count" => 10,
            "exchange" => "",
            "queue" => "my_queue.retry",
            "reason" => "expired",
            "routing-keys" => ["my_queue.retry"],
            "time" => Time.parse("2024-09-10T10:56:22Z")
          },
          {
            "count" => 2,
            "reason" => "rejected",
            "queue" => "my_queue",
            "time" => Time.parse("2024-09-10T10:56:20Z"),
            "exchange" => "my_exchange",
            "routing-keys" => [""]
          }
        ]
      }
    )
  end

  let(:payload) { "payload" }
  let(:error_queue) { "my_queue.error" }
  let(:max_retries) { 2 }

  let(:app) { proc { :result } }
  let(:middleware) { described_class.new(app, retries: max_retries, error_queue: error_queue) }
  let(:channel) { instance_double(Bunny::Channel) }
  let(:default_exchange) { instance_double(Bunny::Exchange) }
  let(:message) { Lepus::Message.new(delivery_info, metadata, payload) }

  before do
    allow(delivery_info).to receive(:channel).and_return(channel)

    allow(Bunny::Exchange).to receive(:default).and_return(default_exchange)
  end

  context "when retry count is not exceeded" do
    it "returns the result of the downstream middleware" do
      expect(middleware.call(message)).to eq(:result)
    end
  end

  context "when retry count is exceeded" do
    let(:max_retries) { 1 }

    it "acks the message when the max retry count is exceeded" do
      allow(default_exchange).to receive(:publish)

      expect(middleware.call(message)).to eq(:ack)
    end

    it "publishes the message to the configured error exchange" do
      expect(Bunny::Exchange).to receive(:default).with(channel).and_return(
        default_exchange
      )
      expect(default_exchange).to receive(:publish).with(
        payload,
        routing_key: error_queue
      )

      middleware.call(message)
    end

    context "when payload is a Hash" do
      let(:payload) { {"a" => 1, :b => 2} }

      it "serializes the payload to JSON before publishing" do
        expect(Bunny::Exchange).to receive(:default).with(channel).and_return(default_exchange)
        expect(default_exchange).to receive(:publish).with(
          MultiJson.dump(payload),
          routing_key: error_queue
        )

        expect(middleware.call(message)).to eq(:ack)
      end
    end

    context "when publishing raises an error" do
      let(:error) { StandardError.new("boom") }

      it "handles the error via thread error handler and does not raise" do
        expect(Bunny::Exchange).to receive(:default).with(channel).and_return(default_exchange)
        expect(default_exchange).to receive(:publish).and_raise(error)

        # Avoid LocalJumpError in Lepus.instrument when AS::Notifications is not present
        allow(Lepus).to receive(:instrument)

        handler_called_with = nil
        Lepus.configure { |c| c.on_thread_error = proc { |e| handler_called_with = e } }
        begin
          result = middleware.call(message)
          expect(result).not_to eq(:ack)
          expect(handler_called_with).to eq(error)
        ensure
          Lepus.configure { |c| c.on_thread_error = nil }
        end
      end
    end
  end

  context "when no death headers are present" do
    let(:metadata) { instance_double(Bunny::MessageProperties, headers: {}) }

    it "returns downstream result if no death headers are present" do
      expect(middleware.call(message)).to eq(:result)
    end
  end

  context "when metadata has no headers" do
    let(:metadata) { instance_double(Bunny::MessageProperties, headers: nil) }

    it "returns downstream result if no death headers are present" do
      expect(middleware.call(message)).to eq(:result)
    end
  end

  context "when x-death has entries but none rejected" do
    let(:metadata) do
      instance_double(
        Bunny::MessageProperties,
        headers: {
          "x-death" => [
            {"count" => 3, "reason" => "expired"}
          ]
        }
      )
    end

    it "passes the message downstream" do
      expect(middleware.call(message)).to eq(:result)
    end
  end

  context "when rejected entries have no count" do
    let(:metadata) do
      instance_double(
        Bunny::MessageProperties,
        headers: {
          "x-death" => [
            {"reason" => "rejected"}
          ]
        }
      )
    end

    it "passes the message downstream" do
      expect(middleware.call(message)).to eq(:result)
    end
  end
end
