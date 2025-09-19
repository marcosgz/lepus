# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Producer do
  let(:producer_class) do
    Class.new(Lepus::Producer)
  end

  before do
    stub_const("TestProducer", producer_class)
  end

  describe ".abstract_class?" do
    context "when the class is abstract" do
      it "returns true" do
        expect(Lepus::Producer.abstract_class?).to be true
      end
    end

    context "when the class is not abstract" do
      it "returns false" do
        expect(producer_class.abstract_class?).to be false
      end
    end
  end

  describe ".definition" do
    context "when no configuration is set" do
      it "returns a default definition with class name as exchange" do
        definition = producer_class.definition
        expect(definition).to be_a(Lepus::Producers::Definition)
        expect(definition.exchange_name).to eq("test_producer")
      end
    end

    context "when configuration is set" do
      before do
        producer_class.configure(exchange: "custom_exchange")
      end

      it "returns the configured definition" do
        definition = producer_class.definition
        expect(definition.exchange_name).to eq("custom_exchange")
      end
    end
  end

  describe ".configure" do
    context "with string exchange name" do
      it "configures the producer with the exchange name" do
        definition = producer_class.configure(exchange: "my_exchange")
        expect(definition.exchange_name).to eq("my_exchange")
        expect(definition.exchange_options[:type]).to eq(:topic)
        expect(definition.exchange_options[:durable]).to be true
      end
    end

    context "with hash exchange configuration" do
      it "configures the producer with exchange options" do
        definition = producer_class.configure(
          exchange: {
            name: "my_exchange",
            type: :direct,
            durable: false,
            auto_delete: true
          }
        )
        expect(definition.exchange_name).to eq("my_exchange")
        expect(definition.exchange_options[:type]).to eq(:direct)
        expect(definition.exchange_options[:durable]).to be false
        expect(definition.exchange_options[:auto_delete]).to be true
      end
    end

    context "with publish options" do
      it "configures default publish options" do
        definition = producer_class.configure(
          exchange: "my_exchange",
          publish: {
            persistent: false,
            mandatory: true
          }
        )
        expect(definition.publish_options).to include(
          persistent: false,
          mandatory: true
        )
      end
    end

    context "with block configuration" do
      it "yields the definition object for further configuration" do
        definition = producer_class.configure(exchange: "my_exchange") do |d|
          d.publish_options[:persistent] = false
        end
        expect(definition.publish_options[:persistent]).to be false
      end
    end

    context "when called on abstract class" do
      it "raises an error" do
        expect { Lepus::Producer.configure(exchange: "test") }.to raise_error(ArgumentError, "Cannot configure an abstract class")
      end
    end
  end

  describe ".publisher" do
    before do
      producer_class.configure(exchange: "test_exchange", type: :direct)
    end

    it "returns a publisher instance with configured exchange" do
      publisher = producer_class.publisher
      expect(publisher).to be_a(Lepus::Publisher)
    end

    it "memoizes the publisher instance" do
      publisher1 = producer_class.publisher
      publisher2 = producer_class.publisher
      expect(publisher1).to be(publisher2)
    end
  end

  describe ".publish" do
    let(:mock_connection) { double("connection") }
    let(:mock_channel) { double("channel") }
    let(:mock_exchange) { double("exchange") }

    before do
      producer_class.configure(
        exchange: "test_exchange",
        publish: { persistent: true, mandatory: false }
      )

      # Ensure hooks are enabled for this producer
      Lepus::Producers.enable!(producer_class)

      allow(Lepus.config.producer_config).to receive(:with_connection).and_yield(mock_connection)
      allow(mock_connection).to receive(:with_channel).and_yield(mock_channel)
      allow(mock_channel).to receive(:exchange).and_return(mock_exchange)
      allow(mock_exchange).to receive(:publish)
    end

    context "with string message" do
      it "publishes the message with default options" do
        producer_class.publish("Hello World")

        expect(mock_exchange).to have_received(:publish).with(
          "Hello World",
          hash_including(
            content_type: "text/plain",
            persistent: true,
            mandatory: false
          )
        )
      end
    end

    context "with hash message" do
      it "publishes the message as JSON" do
        message = { user_id: 123, action: "created" }
        producer_class.publish(message)

        expect(mock_exchange).to have_received(:publish).with(
          '{"user_id":123,"action":"created"}',
          hash_including(
            content_type: "application/json",
            persistent: true,
            mandatory: false
          )
        )
      end
    end

    context "with additional options" do
      it "merges additional options with defaults" do
        producer_class.publish("Hello", routing_key: "test.key", headers: { "x-custom": "value" })

        expect(mock_exchange).to have_received(:publish).with(
          "Hello",
          hash_including(
            routing_key: "test.key",
            headers: { "x-custom": "value" },
            persistent: true,
            mandatory: false
          )
        )
      end
    end

    context "when overriding default publish options" do
      it "uses the provided options over defaults" do
        producer_class.publish("Hello", persistent: false, mandatory: true)

        expect(mock_exchange).to have_received(:publish).with(
          "Hello",
          hash_including(
            persistent: false,
            mandatory: true
          )
        )
      end
    end
  end

  describe "#initialize" do
    it "creates an instance with the class definition" do
      producer_class.configure(exchange: "instance_exchange")
      instance = producer_class.new
      expect(instance.definition.exchange_name).to eq("instance_exchange")
    end
  end

  describe "#publisher" do
    before do
      producer_class.configure(exchange: "instance_exchange")
    end

    it "returns a publisher instance" do
      instance = producer_class.new
      publisher = instance.publisher
      expect(publisher).to be_a(Lepus::Publisher)
    end

    it "memoizes the publisher instance" do
      instance = producer_class.new
      publisher1 = instance.publisher
      publisher2 = instance.publisher
      expect(publisher1).to be(publisher2)
    end
  end

  describe "#publish" do
    let(:mock_connection) { double("connection") }
    let(:mock_channel) { double("channel") }
    let(:mock_exchange) { double("exchange") }

    before do
      producer_class.configure(
        exchange: "instance_exchange",
        publish: { persistent: false }
      )

      # Ensure hooks are enabled for this producer
      Lepus::Producers.enable!(producer_class)

      allow(Lepus.config.producer_config).to receive(:with_connection).and_yield(mock_connection)
      allow(mock_connection).to receive(:with_channel).and_yield(mock_channel)
      allow(mock_channel).to receive(:exchange).and_return(mock_exchange)
      allow(mock_exchange).to receive(:publish)
    end

    it "publishes messages using instance methods" do
      instance = producer_class.new
      instance.publish("Instance message")

      expect(mock_exchange).to have_received(:publish).with(
        "Instance message",
        hash_including(persistent: false)
      )
    end
  end

  describe ".descendants" do
    let(:child_class) do
      Class.new(Lepus::Producer)
    end

    before do
      stub_const("ChildProducer", child_class)
    end

    it "returns all descendant classes" do
      # Create the classes to ensure they're registered
      producer_class
      child_class

      descendants = Lepus::Producer.descendants
      expect(descendants).to include(producer_class, child_class)
    end
  end

  describe "hooks integration" do
    let(:configured_producer_class) do
      Class.new(Lepus::Producer) do
        configure(exchange: "test_exchange")
      end
    end

    let(:mock_connection) { double("connection") }
    let(:mock_channel) { double("channel") }
    let(:mock_exchange) { double("exchange") }

    before do
      Lepus::Producers::Hooks.reset!
      stub_const("ConfiguredProducer", configured_producer_class)

      allow(Lepus.config.producer_config).to receive(:with_connection).and_yield(mock_connection)
      allow(mock_connection).to receive(:with_channel).and_yield(mock_channel)
      allow(mock_channel).to receive(:exchange).and_return(mock_exchange)
      allow(mock_exchange).to receive(:publish)
    end

    after do
      Lepus::Producers::Hooks.reset!
    end

    describe ".publish" do
      it "publishes when hooks are enabled" do
        Lepus::Producers.enable!(configured_producer_class)

        configured_producer_class.publish("test message")

        expect(mock_exchange).to have_received(:publish).with("test message", hash_including(persistent: true))
      end

      it "does not publish when hooks are disabled" do
        Lepus::Producers.disable!(configured_producer_class)

        configured_producer_class.publish("test message")

        expect(mock_exchange).not_to have_received(:publish)
      end

      it "publishes when all producers are enabled" do
        Lepus::Producers.enable!

        configured_producer_class.publish("test message")

        expect(mock_exchange).to have_received(:publish).with("test message", hash_including(persistent: true))
      end

      it "does not publish when all producers are disabled" do
        Lepus::Producers.disable!

        configured_producer_class.publish("test message")

        expect(mock_exchange).not_to have_received(:publish)
      end
    end

    describe "#publish" do
      it "publishes when hooks are enabled" do
        Lepus::Producers.enable!(configured_producer_class)

        instance = configured_producer_class.new
        instance.publish("test message")

        expect(mock_exchange).to have_received(:publish).with("test message", hash_including(persistent: true))
      end

      it "does not publish when hooks are disabled" do
        Lepus::Producers.disable!(configured_producer_class)

        instance = configured_producer_class.new
        instance.publish("test message")

        expect(mock_exchange).not_to have_received(:publish)
      end
    end
  end
end
