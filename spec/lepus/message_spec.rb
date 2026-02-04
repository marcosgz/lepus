# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Message do
  let(:delivery_info) { instance_double(Bunny::DeliveryInfo, to_h: {exchange: "test_exchange", routing_key: "test_key"}) }
  let(:metadata) { instance_double(Bunny::DeliveryInfo, to_h: {content_type: "application/json", timestamp: 1234567890}) }
  let(:payload) { {key: "value"} }
  let(:message) { described_class.new(delivery_info, metadata, payload) }

  describe "#consumer_class" do
    it "can be set and retrieved" do
      consumer_class = Class.new
      message.consumer_class = consumer_class
      expect(message.consumer_class).to eq(consumer_class)
    end

    it "defaults to nil" do
      expect(message.consumer_class).to be_nil
    end
  end

  describe "#channel" do
    context "when channel is set" do
      it "returns the channel" do
        test_channel = instance_double(Bunny::Channel)
        message_with_channel = described_class.new(delivery_info, metadata, payload, channel: test_channel)
        expect(message_with_channel.channel).to eq(test_channel)
      end
    end

    context "when channel is not set" do
      let(:mock_connection) { instance_double(Bunny::Session) }
      let(:mock_channel) { instance_double(Bunny::Channel) }

      it "falls back to checking out a new channel from producer connection pool" do
        allow(Lepus.config.producer_config).to receive(:with_connection).and_yield(mock_connection)
        allow(mock_connection).to receive(:create_channel).and_return(mock_channel)

        expect(message.channel).to eq(mock_channel)
      end

      it "does not memoize the fallback channel" do
        allow(Lepus.config.producer_config).to receive(:with_connection).and_yield(mock_connection)
        allow(mock_connection).to receive(:create_channel).and_return(mock_channel)

        message.channel
        message.channel

        expect(mock_connection).to have_received(:create_channel).twice
      end

      it "returns nil when checkout fails" do
        allow(Lepus.config.producer_config).to receive(:with_connection).and_raise(StandardError)

        expect(message.channel).to be_nil
      end
    end
  end

  describe "#mutate" do
    let(:consumer_class) { Class.new }
    let(:test_channel) { instance_double(Bunny::Channel) }
    let(:message_with_channel) { described_class.new(delivery_info, metadata, payload, channel: test_channel) }

    before do
      message.consumer_class = consumer_class
      message_with_channel.consumer_class = consumer_class
    end

    it "preserves consumer_class when no new value is provided" do
      mutated_message = message.mutate(payload: "new payload")
      expect(mutated_message.consumer_class).to eq(consumer_class)
      expect(mutated_message.payload).to eq("new payload")
    end

    it "allows overriding consumer_class" do
      new_consumer_class = Class.new
      mutated_message = message.mutate(consumer_class: new_consumer_class)
      expect(mutated_message.consumer_class).to eq(new_consumer_class)
    end

    it "preserves other attributes when mutating consumer_class" do
      mutated_message = message.mutate(consumer_class: Class.new)
      expect(mutated_message.delivery_info).to eq(delivery_info)
      expect(mutated_message.metadata).to eq(metadata)
      expect(mutated_message.payload).to eq(payload)
    end

    it "preserves channel when no new value is provided" do
      mutated_message = message_with_channel.mutate(payload: "new payload")
      expect(mutated_message.channel).to eq(test_channel)
    end

    it "allows overriding channel" do
      other_channel = instance_double(Bunny::Channel)
      mutated_message = message_with_channel.mutate(channel: other_channel)
      expect(mutated_message.channel).to eq(other_channel)
    end
  end

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

  describe ".coerce" do
    subject(:coerced_message) { described_class.coerce(bunny_delivery_info, bunny_metadata, raw_payload) }

    let(:coerce_channel) { instance_double(Bunny::Channel) }
    let(:bunny_delivery_info) do
      instance_double(
        Bunny::DeliveryInfo,
        delivery_tag: 42,
        redelivered: true,
        exchange: "my_exchange",
        routing_key: "my.routing.key",
        consumer_tag: "my_consumer_tag",
        channel: coerce_channel
      )
    end
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
    let(:raw_payload) { '{"key":"value"}' }

    it "returns a Message instance" do
      expect(coerced_message).to be_a(described_class)
    end

    it "extracts channel separately" do
      expect(coerced_message.channel).to eq(coerce_channel)
    end

    it "converts delivery_info to DeliveryInfo class" do
      expect(coerced_message.delivery_info).to be_a(described_class::DeliveryInfo)
      expect(coerced_message.delivery_info.delivery_tag).to eq(42)
      expect(coerced_message.delivery_info.redelivered).to be(true)
      expect(coerced_message.delivery_info.exchange).to eq("my_exchange")
      expect(coerced_message.delivery_info.routing_key).to eq("my.routing.key")
      expect(coerced_message.delivery_info.consumer_tag).to eq("my_consumer_tag")
    end

    it "converts metadata to Metadata class" do
      expect(coerced_message.metadata).to be_a(described_class::Metadata)
      expect(coerced_message.metadata.content_type).to eq("application/json")
      expect(coerced_message.metadata.content_encoding).to eq("utf-8")
      expect(coerced_message.metadata.headers).to eq({"x-custom" => "value"})
      expect(coerced_message.metadata.delivery_mode).to eq(2)
      expect(coerced_message.metadata.priority).to eq(5)
      expect(coerced_message.metadata.correlation_id).to eq("corr-123")
      expect(coerced_message.metadata.reply_to).to eq("reply_queue")
      expect(coerced_message.metadata.expiration).to eq("60000")
      expect(coerced_message.metadata.message_id).to eq("msg-456")
      expect(coerced_message.metadata.timestamp).to eq(1234567890)
      expect(coerced_message.metadata.type).to eq("event")
      expect(coerced_message.metadata.user_id).to eq("guest")
      expect(coerced_message.metadata.app_id).to eq("my_app")
      expect(coerced_message.metadata.cluster_id).to be_nil
    end

    it "preserves the payload" do
      expect(coerced_message.payload).to eq(raw_payload)
    end
  end
end
