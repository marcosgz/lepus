# frozen_string_literal: true

require "spec_helper"
require "lepus/testing"

RSpec.describe Lepus::Testing do # rubocop:disable RSpec/SpecFilePathFormat
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
            raise MyCustomError, "Simulated error"
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
          raise MyCustomError, "Simulated error"
        else
          :ack
        end
      end
    end
  end

  before do
    described_class.enable!
    described_class.clear_all_messages!
    stub_const("TestConsumer", test_consumer_class)
    stub_const("MyCustomError", Class.new(StandardError))
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

      it "handles error action" do
        expect(described_class.consumer_raise_errors?).to be true
        expect {
          described_class.consumer_perform(TestConsumer, {"action" => "error"})
        }.to raise_error(MyCustomError, "Simulated error")
      end

      it "handles error action with consumer_capture_errors!" do
        described_class.consumer_capture_errors!
        expect(described_class.consumer_raise_errors?).to be false
        result = nil
        expect {
          result = described_class.consumer_perform(TestConsumer, {"action" => "error"})
        }.not_to raise_error
        expect(result).to eq(:reject)
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
  end

  describe ".build_message" do
    it "raises ArgumentError" do
      expect {
        described_class.send(:build_message, 123)
      }.to raise_error(ArgumentError, "Invalid message type: Integer")
    end

    it "builds a message from a hash" do
      message = described_class.send(:build_message, {"action" => "create"})
      expect(message).to be_a(Lepus::Message)
      expect(message.payload).to eq(MultiJson.dump({"action" => "create"}))
    end

    it "builds a message from a string" do
      message = described_class.send(:build_message, "test message")
      expect(message).to be_a(Lepus::Message)
      expect(message.payload).to eq("test message")
    end

    it "builds a message from a Lepus::Message" do
      message = described_class.send(:build_message, Lepus::Message.new(nil, nil, "test message"))
      expect(message).to be_a(Lepus::Message)
      expect(message.payload).to eq("test message")
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

  describe "middlewares integration" do
    context "with Lepus::Middlewares::JSON" do
      before do
        stub_const("JsonTestConsumer", Class.new(TestConsumer) do
          use(:json)

          def perform(message)
            raise "not a json" unless message.payload.is_a?(Hash)

            ack!
          end
        end)
      end

      it "can test consumer with Lepus::Middlewares::JSON" do
        message = described_class.message_builder
          .with_payload({action: "create"})
          .build

        result = described_class.consumer_perform(JsonTestConsumer, message)
        expect(result).to eq(:ack)
      end
    end

    context "with Lepus::Middlewares::ExceptionLogger" do
      before do
        stub_const("MyLogger", Logger.new(StringIO.new))

        stub_const("ExceptionLoggerTestConsumer", Class.new(TestConsumer) do
          use(:exception_logger, logger: MyLogger)
        end)

        allow(MyLogger).to receive(:error)
      end

      it "does not log error when the message is processed successfully" do
        message = described_class.message_builder
          .with_payload("ok")
          .build

        result = described_class.consumer_perform(ExceptionLoggerTestConsumer, message)
        expect(result).to eq(:ack)
        expect(MyLogger).not_to have_received(:error).with("ok")
      end

      it "logs error when the message is processed with an error" do
        message = described_class.message_builder
          .with_payload("error")
          .build

        expect {
          described_class.consumer_perform(ExceptionLoggerTestConsumer, message)
        }.to raise_error(MyCustomError)

        expect(MyLogger).to have_received(:error).with("Simulated error")
      end
    end
  end
end
