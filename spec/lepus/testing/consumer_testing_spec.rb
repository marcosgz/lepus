# frozen_string_literal: true

require "spec_helper"
require "lepus/testing"

RSpec.describe Lepus::Testing do # rubocop:disable RSpec/SpecFilePathFormat
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

  before do
    described_class.fake_publisher!
    described_class.clear_all_messages!
    stub_const("TestConsumer", test_consumer_class)
  end

  after do
    described_class.disable!
  end

  describe ".consumer_perform" do
    context "with Lepus::Message" do
      it "processes the message and returns the result" do
        message = described_class.message_builder
          .with_payload({action: "create"})
          .build

        result = described_class.consumer_perform(TestConsumer, message)
        expect(result).to eq(:ack)
      end
    end

    context "with Hash payload" do
      it "creates a message from hash payload and processes it" do
        result = described_class.consumer_perform(TestConsumer, {"action" => "create"})
        expect(result).to eq(:ack)
      end

      it "handles reject action" do
        result = described_class.consumer_perform(TestConsumer, {"action" => "reject"})
        expect(result).to eq(:reject)
      end

      it "handles requeue action" do
        result = described_class.consumer_perform(TestConsumer, {"action" => "requeue"})
        expect(result).to eq(:requeue)
      end

      it "handles nack action" do
        result = described_class.consumer_perform(TestConsumer, {"action" => "nack"})
        expect(result).to eq(:nack)
      end
    end

    context "with String payload" do
      it "creates a message from string payload and processes it" do
        result = described_class.consumer_perform(TestConsumer, "test message")
        expect(result).to eq(:ack)
      end

      it "handles reject string" do
        result = described_class.consumer_perform(TestConsumer, "reject")
        expect(result).to eq(:reject)
      end

      it "handles requeue string" do
        result = described_class.consumer_perform(TestConsumer, "requeue")
        expect(result).to eq(:requeue)
      end

      it "handles nack string" do
        result = described_class.consumer_perform(TestConsumer, "nack")
        expect(result).to eq(:nack)
      end
    end

    context "with Hash containing payload key" do
      it "creates a message with payload and additional options" do
        result = described_class.consumer_perform(TestConsumer, {
          payload: {"action" => "create"},
          routing_key: "custom.key",
          exchange: "custom_exchange"
        })
        expect(result).to eq(:ack)
      end
    end

    context "with invalid message type" do
      it "raises ArgumentError" do
        expect {
          described_class.consumer_perform(TestConsumer, 123)
        }.to raise_error(ArgumentError, "Invalid message type: Integer")
      end
    end
  end

  describe ".message_builder" do
    it "returns a new MessageBuilder instance" do
      builder = described_class.message_builder
      expect(builder).to be_a(Lepus::Testing::MessageBuilder)
    end
  end

  describe "integration with consumer testing" do
    it "can test consumer with MessageBuilder" do
      message = described_class.message_builder
        .with_payload({"action" => "create"})
        .with_content_type("application/json")
        .build
      result = described_class.consumer_perform(TestConsumer, message)
      expect(result).to eq(:ack)
    end

    it "can test consumer with string payload" do
      result = described_class.consumer_perform(TestConsumer, "test")
      expect(result).to eq(:ack)
    end

    it "can test consumer with hash payload" do
      result = described_class.consumer_perform(TestConsumer, {"action" => "create"})
      expect(result).to eq(:ack)
    end
  end
end
