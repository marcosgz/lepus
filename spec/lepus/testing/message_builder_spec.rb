# frozen_string_literal: true

require "spec_helper"
require "lepus/testing"

RSpec.describe Lepus::Testing::MessageBuilder do
  let(:builder) { described_class.new }

  describe "#with_payload" do
    it "sets the payload" do
      builder.with_payload("test payload")
      message = builder.build
      expect(message.payload).to eq("test payload")
    end

    it "returns self for chaining" do
      expect(builder.with_payload("test")).to eq(builder)
    end
  end

  describe "#with_delivery_tag" do
    it "sets the delivery tag" do
      builder.with_payload("test").with_delivery_tag(42)
      message = builder.build
      expect(message.delivery_info.delivery_tag).to eq(42)
    end
  end

  describe "#with_routing_key" do
    it "sets the routing key" do
      builder.with_payload("test").with_routing_key("users.create")
      message = builder.build
      expect(message.delivery_info.routing_key).to eq("users.create")
    end
  end

  describe "#with_exchange" do
    it "sets the exchange name" do
      builder.with_payload("test").with_exchange("users")
      message = builder.build
      expect(message.delivery_info.exchange).to eq("users")
    end
  end

  describe "#with_consumer_tag" do
    it "sets the consumer tag" do
      builder.with_payload("test").with_consumer_tag("my_consumer")
      message = builder.build
      expect(message.delivery_info.consumer_tag).to eq("my_consumer")
    end
  end

  describe "#with_redelivered" do
    it "sets the redelivered flag" do
      builder.with_payload("test").with_redelivered(true)
      message = builder.build
      expect(message.delivery_info.redelivered).to be true
    end

    it "defaults to true when called without argument" do
      builder.with_payload("test").with_redelivered
      message = builder.build
      expect(message.delivery_info.redelivered).to be true
    end
  end

  describe "#with_content_type" do
    it "sets the content type" do
      builder.with_payload("test").with_content_type("application/xml")
      message = builder.build
      expect(message.metadata.content_type).to eq("application/xml")
    end
  end

  describe "#with_headers" do
    it "sets the headers" do
      headers = {"correlation_id" => "abc-123", "retry_count" => 3}
      builder.with_payload("test").with_headers(headers)
      message = builder.build
      expect(message.metadata.headers).to eq(headers)
    end
  end

  describe "#with_correlation_id" do
    it "sets the correlation ID" do
      builder.with_payload("test").with_correlation_id("corr-123")
      message = builder.build
      expect(message.metadata.correlation_id).to eq("corr-123")
    end
  end

  describe "#with_reply_to" do
    it "sets the reply to queue" do
      builder.with_payload("test").with_reply_to("reply_queue")
      message = builder.build
      expect(message.metadata.reply_to).to eq("reply_queue")
    end
  end

  describe "#with_expiration" do
    it "sets the message expiration" do
      builder.with_payload("test").with_expiration("60000")
      message = builder.build
      expect(message.metadata.expiration).to eq("60000")
    end
  end

  describe "#with_message_id" do
    it "sets the message ID" do
      message_id = "msg-123"
      builder.with_payload("test").with_message_id(message_id)
      message = builder.build
      expect(message.metadata.message_id).to eq(message_id)
    end
  end

  describe "#with_timestamp" do
    it "sets the timestamp" do
      timestamp = Time.now.to_i
      builder.with_payload("test").with_timestamp(timestamp)
      message = builder.build
      expect(message.metadata.timestamp).to eq(timestamp)
    end
  end

  describe "#with_type" do
    it "sets the message type" do
      builder.with_payload("test").with_type("user.created")
      message = builder.build
      expect(message.metadata.type).to eq("user.created")
    end
  end

  describe "#with_user_id" do
    it "sets the user ID" do
      builder.with_payload("test").with_user_id("user123")
      message = builder.build
      expect(message.metadata.user_id).to eq("user123")
    end
  end

  describe "#with_app_id" do
    it "sets the app ID" do
      builder.with_payload("test").with_app_id("my_app")
      message = builder.build
      expect(message.metadata.app_id).to eq("my_app")
    end
  end

  describe "#with_delivery_mode" do
    it "sets the delivery mode" do
      builder.with_payload("test").with_delivery_mode(1)
      message = builder.build
      expect(message.metadata.delivery_mode).to eq(1)
    end
  end

  describe "#with_priority" do
    it "sets the priority" do
      builder.with_payload("test").with_priority(5)
      message = builder.build
      expect(message.metadata.priority).to eq(5)
    end
  end

  describe "#with_delivery_info_attrs" do
    it "merges custom delivery info attributes" do
      attrs = {delivery_tag: 99, custom_attr: "value"}
      builder.with_payload("test").with_delivery_info_attrs(attrs)
      message = builder.build
      expect(message.delivery_info.delivery_tag).to eq(99)
      expect(message.delivery_info.custom_attr).to eq("value")
    end
  end

  describe "#with_metadata_attrs" do
    it "merges custom metadata attributes" do
      attrs = {content_type: "text/plain", custom_attr: "value"}
      builder.with_payload("test").with_metadata_attrs(attrs)
      message = builder.build
      expect(message.metadata.content_type).to eq("text/plain")
      expect(message.metadata.custom_attr).to eq("value")
    end
  end

  describe "#build" do
    it "creates a Lepus::Message with default values" do
      message = builder.with_payload("test").build

      expect(message).to be_a(Lepus::Message)
      expect(message.payload).to eq("test")
      expect(message.delivery_info.delivery_tag).to eq(1)
      expect(message.delivery_info.redelivered).to be false
      expect(message.delivery_info.exchange).to eq("test_exchange")
      expect(message.delivery_info.routing_key).to eq("test.routing.key")
      expect(message.delivery_info.consumer_tag).to eq("test_consumer_tag")
      expect(message.metadata.content_type).to eq("application/json")
      expect(message.metadata.content_encoding).to eq("utf-8")
      expect(message.metadata.headers).to eq({})
      expect(message.metadata.delivery_mode).to eq(2)
      expect(message.metadata.priority).to eq(0)
    end

    it "raises error when payload is not set" do
      expect { builder.build }.to raise_error(ArgumentError, "Payload is required")
    end

    it "creates proper mock objects with to_h method" do
      message = builder.with_payload("test").build

      expect(message.delivery_info.to_h).to include(
        delivery_tag: 1,
        redelivered: false,
        exchange: "test_exchange",
        routing_key: "test.routing.key",
        consumer_tag: "test_consumer_tag"
      )

      expect(message.metadata.to_h).to include(
        content_type: "application/json",
        content_encoding: "utf-8",
        headers: {},
        delivery_mode: 2,
        priority: 0
      )
    end
  end

  describe "method chaining" do
    it "allows chaining multiple methods" do
      message = builder
        .with_payload({user_id: 123, action: "create"})
        .with_delivery_tag(42)
        .with_routing_key("users.create")
        .with_exchange("users")
        .with_content_type("application/json")
        .with_headers({"correlation_id" => "abc-123"})
        .with_correlation_id("corr-456")
        .build

      expect(message.payload).to eq({user_id: 123, action: "create"})
      expect(message.delivery_info.delivery_tag).to eq(42)
      expect(message.delivery_info.routing_key).to eq("users.create")
      expect(message.delivery_info.exchange).to eq("users")
      expect(message.metadata.content_type).to eq("application/json")
      expect(message.metadata.headers).to eq({"correlation_id" => "abc-123"})
      expect(message.metadata.correlation_id).to eq("corr-456")
    end
  end
end
