# frozen_string_literal: true

require "spec_helper"
require "lepus/testing"

RSpec.describe Lepus::Testing::RSpecMatchers do
  let(:test_consumer_class) do
    Class.new(Lepus::Consumer) do
      configure(queue: "test_queue", exchange: "test_exchange")

      def perform(message)
        case message.payload
        when Hash
          case message.payload["action"]
          when "reject"
            reject!
          when "requeue"
            requeue!
          when "nack"
            nack!
          when "error"
            raise "Simulated error"
          else
            ack!
          end
        when String
          if message.payload == "reject"
            reject!
          elsif message.payload == "requeue"
            requeue!
          elsif message.payload == "nack"
            nack!
          elsif message.payload == "error"
            raise "Simulated error"
          else
            ack!
          end
        else
          ack!
        end
      end
    end
  end

  let(:publishing_consumer_class) do
    Class.new(Lepus::Consumer) do
      configure(queue: "test_queue", exchange: "test_exchange")

      def perform(message)
        publish_message("published message", exchange_name: "output_exchange")
        ack!
      end
    end
  end

  before do
    Lepus::Testing.fake_publisher!
    Lepus::Testing.clear_all_messages!
    stub_const("TestConsumer", test_consumer_class)
    stub_const("PublishingConsumer", publishing_consumer_class)

    # Enable the output exchange for publishing tests
    output_producer_class = Class.new(Lepus::Producer) do
      configure(exchange: "output_exchange")
    end
    stub_const("OutputProducer", output_producer_class)
    Lepus::Producers.enable!(output_producer_class)
  end

  after do
    Lepus::Testing.disable!
  end

  describe "lepus_acknowledge_message matcher" do
    it "passes when consumer acknowledges message" do
      expect(TestConsumer).to lepus_acknowledge_message({"action" => "create"})
    end

    it "passes when consumer acknowledges string message" do
      expect(TestConsumer).to lepus_acknowledge_message("test message")
    end

    it "fails when consumer rejects message" do
      expect(TestConsumer).not_to lepus_acknowledge_message({"action" => "reject"})
    end

    it "fails when consumer requeues message" do
      expect(TestConsumer).not_to lepus_acknowledge_message({"action" => "requeue"})
    end

    it "fails when consumer nacks message" do
      expect(TestConsumer).not_to lepus_acknowledge_message({"action" => "nack"})
    end

    it "works with Lepus::Message" do
      message = Lepus::Testing.message_builder
        .with_payload({"action" => "create"})
        .with_content_type("application/json")
        .build
      expect(TestConsumer).to lepus_acknowledge_message(message)
    end

    it "provides clear failure message" do
      expect {
        expect(TestConsumer).to lepus_acknowledge_message({"action" => "reject"})
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /expected TestConsumer to ack message, but got reject/)
    end

    it "supports short hand lepus_ack_message alias" do
      expect(TestConsumer).to lepus_ack_message({"action" => "create"})
    end
  end

  describe "lepus_reject_message matcher" do
    it "passes when consumer rejects message" do
      expect(TestConsumer).to lepus_reject_message({"action" => "reject"})
    end

    it "passes when consumer rejects string message" do
      expect(TestConsumer).to lepus_reject_message("reject")
    end

    it "fails when consumer acknowledges message" do
      expect(TestConsumer).not_to lepus_reject_message({"action" => "create"})
    end

    it "fails when consumer requeues message" do
      expect(TestConsumer).not_to lepus_reject_message({"action" => "requeue"})
    end

    it "fails when consumer nacks message" do
      expect(TestConsumer).not_to lepus_reject_message({"action" => "nack"})
    end
  end

  describe "lepus_requeue_message matcher" do
    it "passes when consumer requeues message" do
      expect(TestConsumer).to lepus_requeue_message({"action" => "requeue"})
    end

    it "passes when consumer requeues string message" do
      expect(TestConsumer).to lepus_requeue_message("requeue")
    end

    it "fails when consumer acknowledges message" do
      expect(TestConsumer).not_to lepus_requeue_message({"action" => "create"})
    end

    it "fails when consumer rejects message" do
      expect(TestConsumer).not_to lepus_requeue_message({"action" => "reject"})
    end

    it "fails when consumer nacks message" do
      expect(TestConsumer).not_to lepus_requeue_message({"action" => "nack"})
    end
  end

  describe "lepus_nack_message matcher" do
    it "passes when consumer nacks message" do
      expect(TestConsumer).to lepus_nack_message({"action" => "nack"})
    end

    it "passes when consumer nacks string message" do
      expect(TestConsumer).to lepus_nack_message("nack")
    end

    it "fails when consumer acknowledges message" do
      expect(TestConsumer).not_to lepus_nack_message({"action" => "create"})
    end

    it "fails when consumer rejects message" do
      expect(TestConsumer).not_to lepus_nack_message({"action" => "reject"})
    end

    it "fails when consumer requeues message" do
      expect(TestConsumer).not_to lepus_nack_message({"action" => "requeue"})
    end
  end

  describe "matcher chaining" do
    it "allows chaining with_message" do
      expect(TestConsumer).to lepus_acknowledge_message.with_message({"action" => "create"})
    end

    it "allows shorthand with message as argument" do
      message = Lepus::Testing.message_builder
        .with_payload({"action" => "create"})
        .with_content_type("application/json")
        .build
      expect(TestConsumer).to lepus_acknowledge_message(message)
    end

    it "allows chaining with_delivery_info" do
      custom_delivery_info = instance_double(Bunny::DeliveryInfo)
      allow(custom_delivery_info).to receive(:delivery_tag).and_return(99)
      allow(custom_delivery_info).to receive(:redelivered).and_return(false)
      allow(custom_delivery_info).to receive(:exchange).and_return("custom")
      allow(custom_delivery_info).to receive(:routing_key).and_return("custom.key")
      allow(custom_delivery_info).to receive(:consumer_tag).and_return("custom_consumer")
      allow(custom_delivery_info).to receive(:to_h).and_return({})

      expect(TestConsumer).to lepus_acknowledge_message
        .with_message({"action" => "create"})
        .with_delivery_info(custom_delivery_info)
    end

    it "allows chaining with_metadata" do
      custom_metadata = instance_double(Bunny::MessageProperties)
      allow(custom_metadata).to receive(:content_type).and_return("text/plain")
      allow(custom_metadata).to receive(:content_encoding).and_return("utf-8")
      allow(custom_metadata).to receive(:headers).and_return({})
      allow(custom_metadata).to receive(:delivery_mode).and_return(1)
      allow(custom_metadata).to receive(:priority).and_return(0)
      allow(custom_metadata).to receive(:correlation_id).and_return(nil)
      allow(custom_metadata).to receive(:reply_to).and_return(nil)
      allow(custom_metadata).to receive(:expiration).and_return(nil)
      allow(custom_metadata).to receive(:message_id).and_return("custom-id")
      allow(custom_metadata).to receive(:timestamp).and_return(Time.now.to_i)
      allow(custom_metadata).to receive(:type).and_return(nil)
      allow(custom_metadata).to receive(:user_id).and_return(nil)
      allow(custom_metadata).to receive(:app_id).and_return(nil)
      allow(custom_metadata).to receive(:cluster_id).and_return(nil)
      allow(custom_metadata).to receive(:to_h).and_return({})

      expect(TestConsumer).to lepus_acknowledge_message
        .with_message({"action" => "create"})
        .with_metadata(custom_metadata)
    end
  end

  describe "error handling" do
    it "handles consumer errors gracefully" do
      allow(Lepus).to receive(:logger).and_return(double("logger", error: nil))

      expect {
        expect(TestConsumer).to lepus_acknowledge_message({"action" => "error"})
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end
end
