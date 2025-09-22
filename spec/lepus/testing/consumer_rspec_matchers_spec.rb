# frozen_string_literal: true

require "spec_helper"
require "lepus/testing"

RSpec.describe Lepus::Testing::RSpecMatchers do # rubocop:disable RSpec/SpecFilePathFormat
  let(:test_consumer_class) do
    Class.new(Lepus::Consumer) do
      configure(queue: "test_queue", exchange: "test_exchange")

      def perform(message)
        content = /^(\{.*\}|".*")$/.match?(message.payload.to_s) ? MultiJson.load(message.payload) : message.payload
        case content
        when Hash
          case content["action"]
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
        when "reject"
          :reject
        when "requeue"
          :requeue
        when "nack"
          :nack
        when "error"
          raise "Simulated error"
        else
          :ack
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
      allow(custom_delivery_info).to receive_messages(delivery_tag: 99, redelivered: false, exchange: "custom", routing_key: "custom.key", consumer_tag: "custom_consumer", to_h: {})

      expect(TestConsumer).to lepus_acknowledge_message
        .with_message({"action" => "create"})
        .with_delivery_info(custom_delivery_info)
    end

    it "allows chaining with_metadata" do
      custom_metadata = instance_double(Bunny::MessageProperties)
      allow(custom_metadata).to receive_messages(content_type: "text/plain", content_encoding: "utf-8", headers: {}, delivery_mode: 1, priority: 0, correlation_id: nil, reply_to: nil, expiration: nil, message_id: "custom-id", timestamp: Time.now.to_i, type: nil, user_id: nil, app_id: nil, cluster_id: nil, to_h: {})

      expect(TestConsumer).to lepus_acknowledge_message
        .with_message({"action" => "create"})
        .with_metadata(custom_metadata)
    end
  end

  describe "error handling" do
    it "handles consumer errors gracefully" do
      allow(Lepus).to receive(:logger).and_return(instance_double(Logger, error: nil))

      expect {
        expect(TestConsumer).to lepus_acknowledge_message({"action" => "error"})
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end
end
