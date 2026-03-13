# frozen_string_literal: true

require "spec_helper"
require "lepus/consumers/middlewares/unique"

RSpec.describe Lepus::Consumers::Middlewares::Unique do
  describe "#call" do
    let(:lock_class) do
      stub_const("DeDupe::Lock", Class.new do
        attr_reader :lock_key, :lock_id

        def initialize(lock_key:, lock_id:, **opts)
          @lock_key = lock_key
          @lock_id = lock_id
        end

        def release
          true
        end
      end)
    end

    let(:middleware) { described_class.new }

    def build_message(headers: nil)
      delivery_info = Lepus::Message::DeliveryInfo.new(
        exchange: "test_exchange",
        routing_key: "test.key"
      )
      metadata = Lepus::Message::Metadata.new(headers: headers)
      Lepus::Message.new(delivery_info, metadata, "test payload")
    end

    def dedupe_headers(lock_key: "story", lock_id: "123")
      {
        "x-dedupe-lock-key" => lock_key,
        "x-dedupe-lock-id" => lock_id
      }
    end

    before { lock_class }

    context "when result is :ack" do
      it "releases the lock" do
        message = build_message(headers: dedupe_headers)

        expect(lock_class).to receive(:new).with(
          lock_key: "story",
          lock_id: "123"
        ).and_call_original

        lock_released = false
        allow_any_instance_of(lock_class).to receive(:release) do
          lock_released = true
        end

        result = middleware.call(message, proc { |_| :ack })

        expect(result).to eq(:ack)
        expect(lock_released).to be true
      end
    end

    context "when result is :reject" do
      it "does NOT release the lock" do
        message = build_message(headers: dedupe_headers)

        expect(lock_class).not_to receive(:new)

        result = middleware.call(message, proc { |_| :reject })

        expect(result).to eq(:reject)
      end
    end

    context "when result is :requeue" do
      it "does NOT release the lock" do
        message = build_message(headers: dedupe_headers)

        expect(lock_class).not_to receive(:new)

        result = middleware.call(message, proc { |_| :requeue })

        expect(result).to eq(:requeue)
      end
    end

    context "when result is :nack" do
      it "does NOT release the lock" do
        message = build_message(headers: dedupe_headers)

        expect(lock_class).not_to receive(:new)

        result = middleware.call(message, proc { |_| :nack })

        expect(result).to eq(:nack)
      end
    end

    context "when dedupe headers are missing" do
      it "passes through without error" do
        message = build_message(headers: nil)

        expect(lock_class).not_to receive(:new)

        result = middleware.call(message, proc { |_| :ack })

        expect(result).to eq(:ack)
      end
    end

    context "when only lock_key header is present" do
      it "does not attempt to release" do
        message = build_message(headers: {"x-dedupe-lock-key" => "story"})

        expect(lock_class).not_to receive(:new)

        result = middleware.call(message, proc { |_| :ack })

        expect(result).to eq(:ack)
      end
    end

    context "when only lock_id header is present" do
      it "does not attempt to release" do
        message = build_message(headers: {"x-dedupe-lock-id" => "123"})

        expect(lock_class).not_to receive(:new)

        result = middleware.call(message, proc { |_| :ack })

        expect(result).to eq(:ack)
      end
    end

    it "returns the result from downstream" do
      message = build_message(headers: dedupe_headers)
      result = middleware.call(message, proc { |_| :ack })

      expect(result).to eq(:ack)
    end

    it "does not modify the message passed downstream" do
      message = build_message(headers: dedupe_headers)
      downstream_message = nil

      middleware.call(message, proc { |msg|
        downstream_message = msg
        :ack
      })

      expect(downstream_message).to eq(message)
    end
  end
end
