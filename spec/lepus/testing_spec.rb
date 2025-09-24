# frozen_string_literal: true

require "spec_helper"
require "lepus/testing"

RSpec.describe Lepus::Testing do
  let(:test_producer1_class) do
    Class.new(Lepus::Producer) do
      configure(exchange: "test_exchange_1")
    end
  end

  let(:test_producer2_class) do
    Class.new(Lepus::Producer) do
      configure(exchange: "test_exchange_2")
    end
  end

  let(:test_producer_for_messages_class) do
    Class.new(Lepus::Producer) do
      configure(exchange: "test_exchange_for_messages")
    end
  end

  before do
    Lepus::Testing.enable! # rubocop:disable RSpec/DescribedClass
    Lepus::Testing.clear_all_messages! # rubocop:disable RSpec/DescribedClass

    # Stub the producer classes as constants
    stub_const("TestProducer1", test_producer1_class)
    stub_const("TestProducer2", test_producer2_class)
    stub_const("TestProducerForMessages", test_producer_for_messages_class)

    # Enable the specific producer classes
    Lepus::Producers.enable!(test_producer1_class, test_producer2_class, test_producer_for_messages_class)
  end

  after do
    Lepus::Testing.disable! # rubocop:disable RSpec/DescribedClass
  end

  describe ".fake_publisher!" do
    it "enables fake publishing mode" do
      described_class.disable!
      expect(described_class.fake_publisher_enabled?).to be false

      described_class.fake_publisher!
      expect(described_class.fake_publisher_enabled?).to be true
    end
  end

  describe ".disable!" do
    before do
      described_class.enable!
    end

    it "disables fake publishing mode" do
      expect(described_class.fake_publisher_enabled?).to be true
      expect(described_class.consumer_raise_errors?).to be true

      described_class.disable!
      expect(described_class.fake_publisher_enabled?).to be false
      expect(described_class.consumer_raise_errors?).to be false
    end
  end

  describe ".enable!" do
    before do
      described_class.disable!
    end

    it "enables fake publishing mode" do
      expect(described_class.fake_publisher_enabled?).to be false
      expect(described_class.consumer_raise_errors?).to be false

      described_class.enable!
      expect(described_class.fake_publisher_enabled?).to be true
      expect(described_class.consumer_raise_errors?).to be true
    end
  end

  describe "consumer error raising toggles" do
    before do
      described_class.disable!
    end

    it "enables and disables consumer error re-raising" do
      expect(described_class.consumer_raise_errors?).to be false

      described_class.consumer_raise_errors!
      expect(described_class.consumer_raise_errors?).to be true

      described_class.consumer_capture_errors!
      expect(described_class.consumer_raise_errors?).to be false
    end
  end

  describe ".clear_all_messages!" do
    it "clears all messages from all exchanges" do
      # Enable producers and publish some messages
      Lepus::Producers.enable!(TestProducer1, TestProducer2)
      TestProducer1.publish("message 1")
      TestProducer2.publish("message 2")

      expect(Lepus::Testing::Exchange.total_messages).to eq(2)

      described_class.clear_all_messages!
      expect(Lepus::Testing::Exchange.total_messages).to eq(0)
    end
  end

  describe ".exchange" do
    it "returns the exchange for the given name" do
      exchange = described_class.exchange("test_exchange")
      expect(exchange).to be_a(Lepus::Testing::Exchange)
      expect(exchange.name).to eq("test_exchange")
    end
  end

  describe ".producer_messages" do
    it "returns messages for a specific producer" do
      Lepus::Producers.enable!(TestProducerForMessages)
      TestProducerForMessages.publish("test message")

      messages = described_class.producer_messages(TestProducerForMessages)
      expect(messages.size).to eq(1)
      expect(messages.first[:payload]).to eq("test message")
    end
  end

  describe Lepus::Testing::Exchange do
    let(:exchange) { Lepus::Testing::Exchange["test_exchange"] } # rubocop:disable RSpec/DescribedClass

    before do
      Lepus::Testing.fake_publisher!
      Lepus::Testing.clear_all_messages!
      Lepus::Producers.enable!
    end

    after do
      Lepus::Testing.disable!
    end

    describe "#add_message" do
      it "adds a message to the exchange" do
        message = {payload: "test", routing_key: "test.key"}
        exchange.add_message(message)

        expect(exchange.size).to eq(1)
        expect(exchange.messages.first).to eq(message)
      end
    end

    describe "#clear_messages" do
      it "clears all messages from the exchange" do
        exchange.add_message({payload: "test"})
        expect(exchange.size).to eq(1)

        exchange.clear_messages
        expect(exchange.size).to eq(0)
      end
    end

    describe "#find_messages" do
      before do
        exchange.add_message({payload: "message 1", routing_key: "key1"})
        exchange.add_message({payload: "message 2", routing_key: "key2"})
        exchange.add_message({payload: {data: "json"}, routing_key: "key1"})
      end

      it "finds messages by routing key" do
        messages = exchange.find_messages(routing_key: "key1")
        expect(messages.size).to eq(2)
      end

      it "finds messages by payload" do
        messages = exchange.find_messages(payload: "message 1")
        expect(messages.size).to eq(1)
        expect(messages.first[:payload]).to eq("message 1")
      end

      it "returns all messages when no criteria provided" do
        messages = exchange.find_messages
        expect(messages.size).to eq(3)
      end
    end

    describe ".clear_all_messages!" do
      it "clears messages from all exchanges" do
        described_class["exchange1"].add_message({payload: "test1"})
        described_class["exchange2"].add_message({payload: "test2"})

        expect(Lepus::Testing::Exchange.total_messages).to eq(2) # rubocop:disable RSpec/DescribedClass

        Lepus::Testing::Exchange.clear_all_messages! # rubocop:disable RSpec/DescribedClass
        expect(Lepus::Testing::Exchange.total_messages).to eq(0) # rubocop:disable RSpec/DescribedClass
      end
    end
  end
end
