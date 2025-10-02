# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Publisher do
  let(:exchange_name) { "test_exchange" }
  let(:bunny) { instance_double(Bunny::Session) }
  let(:publisher) { described_class.new(exchange_name) }

  describe "#initialize" do
    it "sets the exchange name" do
      expect(publisher.exchange_name).to eq(exchange_name)
    end

    it "sets the exchange options" do
      expect(publisher.exchange_options).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS
      )

      publisher = described_class.new(exchange_name, type: :direct, durable: false, auto_delete: true)
      expect(publisher.exchange_options).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS.merge(type: :direct, durable: false, auto_delete: true)
      )

      publisher = described_class.new(exchange_name, type: :direct)
      expect(publisher.exchange_options).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS.merge(type: :direct)
      )

      publisher = described_class.new(exchange_name, durable: false)
      expect(publisher.exchange_options).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS.merge(durable: false)
      )

      publisher = described_class.new(exchange_name, auto_delete: true)
      expect(publisher.exchange_options).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS.merge(auto_delete: true)
      )

      publisher = described_class.new(exchange_name, type: :direct, durable: false)
      expect(publisher.exchange_options).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS.merge(type: :direct, durable: false)
      )
    end

    context "with exchange namespace configured" do
      before { Lepus.config.producer_config.exchange_namespace = "ns" }

      after { reset_config! }

      it "prefixes the exchange name with the namespace" do
        publisher = described_class.new(exchange_name)
        expect(publisher.exchange_name).to eq("ns.#{exchange_name}")
      end

      it "works with custom exchange options" do
        publisher = described_class.new(exchange_name, type: :direct, durable: false)
        expect(publisher.exchange_name).to eq("ns.#{exchange_name}")
        expect(publisher.exchange_options).to eq(
          described_class::DEFAULT_EXCHANGE_OPTIONS.merge(type: :direct, durable: false)
        )
      end
    end

    context "without exchange namespace configured" do
      after { reset_config! }

      it "uses the original exchange name" do
        publisher = described_class.new(exchange_name)
        expect(publisher.exchange_name).to eq(exchange_name)
      end
    end
  end

  describe "#channel_publish" do
    let(:channel) { instance_double(Bunny::Channel) }
    let(:exchange) { instance_double(Bunny::Exchange) }
    let(:options) { {expiration: 60} }

    before do
      allow(channel).to receive(:exchange).and_return(exchange)
      allow(exchange).to receive(:publish)
    end

    context "when channel is provided and message is different than String" do
      let(:message) { {key: "value"} }

      it "publishes the message to the exchange as JSON" do
        publisher.channel_publish(channel, message, **options)

        expect(channel).to have_received(:exchange).with(exchange_name, described_class::DEFAULT_EXCHANGE_OPTIONS)
        expect(exchange).to have_received(:publish).with(
          MultiJson.dump(message),
          a_hash_including(
            content_type: "application/json",
            expiration: 60,
            persistent: true
          )
        )
      end
    end

    context "when channel is provided and message is a String" do
      let(:message) { "test message" }

      it "publishes the message to the exchange as text" do
        publisher.channel_publish(channel, message, **options)

        expect(channel).to have_received(:exchange).with(exchange_name, described_class::DEFAULT_EXCHANGE_OPTIONS)
        expect(exchange).to have_received(:publish).with(
          message,
          a_hash_including(
            content_type: "text/plain",
            expiration: 60,
            persistent: true
          )
        )
      end
    end

    context "when channel is provided and custom content type is provided" do
      let(:message) { "test message" }
      let(:options) { {content_type: "application/xml"} }

      it "uses the provided content type" do
        publisher.channel_publish(channel, message, **options)

        expect(exchange).to have_received(:publish).with(
          message,
          a_hash_including(content_type: "application/xml")
        )
      end
    end

    context "when channel is provided and custom exchange options are provided" do
      let(:publisher) { described_class.new(exchange_name, type: :direct, durable: false) }
      let(:message) { "test message" }

      it "uses the custom exchange options" do
        publisher.channel_publish(channel, message)

        expect(channel).to have_received(:exchange).with(
          exchange_name,
          described_class::DEFAULT_EXCHANGE_OPTIONS.merge(type: :direct, durable: false)
        )
      end
    end

    context "when channel is nil" do
      it "raises ArgumentError" do
        expect {
          publisher.channel_publish(nil, "test message")
        }.to raise_error(ArgumentError, "channel is required")
      end
    end

    context "when channel is not provided" do
      it "raises ArgumentError for wrong number of arguments" do
        expect {
          publisher.channel_publish("test message")
        }.to raise_error(ArgumentError, /wrong number of arguments/)
      end
    end

    context "with exchange namespace configured" do
      before do
        allow(Lepus.config.producer_config).to receive(:exchange_namespace).and_return("ns")
      end

      let(:namespaced_publisher) { described_class.new(exchange_name) }

      it "uses the namespaced exchange name when publishing" do
        message = "test message"
        namespaced_publisher.channel_publish(channel, message, **options)

        expect(channel).to have_received(:exchange).with("ns.#{exchange_name}", described_class::DEFAULT_EXCHANGE_OPTIONS)
        expect(exchange).to have_received(:publish).with(
          message,
          a_hash_including(
            content_type: "text/plain",
            expiration: 60,
            persistent: true
          )
        )
      end
    end
  end

  describe "#publish" do
    let(:options) { {expiration: 60} }

    before do
      allow(Lepus.config.producer_config).to receive(:with_connection).and_yield(bunny)
    end

    context "when the message is different than String" do
      let(:message) { {key: "value"} }

      it "publishes the message to the exchange as JSON using channel_publish" do
        channel = instance_double(Bunny::Channel)
        exchange = instance_double(Bunny::Exchange)

        expect(bunny).to receive(:with_channel).and_yield(channel)
        allow(channel).to receive(:exchange).and_return(exchange)
        allow(exchange).to receive(:publish)
        allow(publisher).to receive(:channel_publish).and_call_original

        publisher.publish(message, **options)

        expect(publisher).to have_received(:channel_publish).with(channel, message, **options)
      end
    end

    context "when the message is a String" do
      let(:message) { "test message" }

      it "publishes the message to the exchange as text using channel_publish" do
        channel = instance_double(Bunny::Channel)
        exchange = instance_double(Bunny::Exchange)

        expect(bunny).to receive(:with_channel).and_yield(channel)
        allow(channel).to receive(:exchange).and_return(exchange)
        allow(exchange).to receive(:publish)
        allow(publisher).to receive(:channel_publish).and_call_original

        publisher.publish(message, **options)

        expect(publisher).to have_received(:channel_publish).with(channel, message, **options)
      end
    end

    context "with exchange namespace configured" do
      before do
        allow(Lepus.config.producer_config).to receive(:exchange_namespace).and_return("ns")
      end

      let(:namespaced_publisher) { described_class.new(exchange_name) }

      it "uses the namespaced exchange name when publishing" do
        message = "test message"
        channel = instance_double(Bunny::Channel)
        exchange = instance_double(Bunny::Exchange)

        expect(bunny).to receive(:with_channel).and_yield(channel)
        allow(channel).to receive(:exchange).and_return(exchange)
        allow(exchange).to receive(:publish)
        allow(namespaced_publisher).to receive(:channel_publish).and_call_original

        namespaced_publisher.publish(message, **options)

        expect(namespaced_publisher).to have_received(:channel_publish).with(channel, message, **options)
      end
    end
  end

  describe "hooks integration" do
    let(:test_producer_class) do
      Class.new(Lepus::Producer) do
        configure(exchange: "test_exchange")
      end
    end

    let(:mock_connection) { instance_double(Bunny::Session) }
    let(:mock_channel) { instance_double(Bunny::Channel) }
    let(:mock_exchange) { instance_double(Bunny::Exchange) }

    before do
      Lepus::Producers::Hooks.reset!
      stub_const("TestProducerClass", test_producer_class)

      allow(Lepus.config.producer_config).to receive(:with_connection).and_yield(mock_connection)
      allow(mock_connection).to receive(:with_channel).and_yield(mock_channel)
      allow(mock_channel).to receive(:exchange).and_return(mock_exchange)
      allow(mock_exchange).to receive(:publish)
    end

    after do
      Lepus::Producers::Hooks.reset!
    end

    it "publishes when exchange is enabled" do
      Lepus::Producers.enable!("test_exchange")

      publisher = described_class.new("test_exchange")
      publisher.publish("test message")

      expect(mock_exchange).to have_received(:publish).with("test message", hash_including(persistent: true))
    end

    it "does not publish when exchange is disabled" do
      Lepus::Producers.disable!("test_exchange")

      publisher = described_class.new("test_exchange")
      publisher.publish("test message")

      expect(mock_exchange).not_to have_received(:publish)
    end

    it "publishes when exchange is enabled via producer class" do
      Lepus::Producers.enable!(test_producer_class)

      publisher = described_class.new("test_exchange")
      publisher.publish("test message")

      expect(mock_exchange).to have_received(:publish).with("test message", hash_including(persistent: true))
    end

    it "does not publish when exchange is disabled via producer class" do
      Lepus::Producers.disable!(test_producer_class)

      publisher = described_class.new("test_exchange")
      publisher.publish("test message")

      expect(mock_exchange).not_to have_received(:publish)
    end

    it "publishes for exchanges with no producers (default enabled)" do
      publisher = described_class.new("nonexistent_exchange")
      publisher.publish("test message")

      expect(mock_exchange).to have_received(:publish).with("test message", hash_including(persistent: true))
    end

    context "with exchange namespace configured" do
      before do
        allow(Lepus.config.producer_config).to receive(:exchange_namespace).and_return("ns")
      end

      it "publishes when namespaced exchange is enabled" do
        Lepus::Producers.enable!("ns.test_exchange")

        publisher = described_class.new("test_exchange")
        publisher.publish("test message")

        expect(mock_exchange).to have_received(:publish).with("test message", hash_including(persistent: true))
      end

      it "does not publish when namespaced exchange is disabled" do
        Lepus::Producers.disable!("ns.test_exchange")

        publisher = described_class.new("test_exchange")
        publisher.publish("test message")

        expect(mock_exchange).not_to have_received(:publish)
      end
    end
  end

  describe "channel_publish hooks integration" do
    let(:test_producer_class) do
      Class.new(Lepus::Producer) do
        configure(exchange: "test_exchange")
      end
    end

    let(:channel) { instance_double(Bunny::Channel) }
    let(:exchange) { instance_double(Bunny::Exchange) }

    before do
      Lepus::Producers::Hooks.reset!
      stub_const("TestProducerClass", test_producer_class)

      allow(channel).to receive(:exchange).and_return(exchange)
      allow(exchange).to receive(:publish)
    end

    after do
      Lepus::Producers::Hooks.reset!
    end

    it "publishes when exchange is enabled" do
      Lepus::Producers.enable!("test_exchange")

      publisher = described_class.new("test_exchange")
      publisher.channel_publish(channel, "test message")

      expect(exchange).to have_received(:publish).with("test message", hash_including(persistent: true))
    end

    it "does not publish when exchange is disabled" do
      Lepus::Producers.disable!("test_exchange")

      publisher = described_class.new("test_exchange")
      publisher.channel_publish(channel, "test message")

      expect(exchange).not_to have_received(:publish)
    end

    it "publishes when exchange is enabled via producer class" do
      Lepus::Producers.enable!(test_producer_class)

      publisher = described_class.new("test_exchange")
      publisher.channel_publish(channel, "test message")

      expect(exchange).to have_received(:publish).with("test message", hash_including(persistent: true))
    end

    it "does not publish when exchange is disabled via producer class" do
      Lepus::Producers.disable!(test_producer_class)

      publisher = described_class.new("test_exchange")
      publisher.channel_publish(channel, "test message")

      expect(exchange).not_to have_received(:publish)
    end

    it "publishes for exchanges with no producers (default enabled)" do
      publisher = described_class.new("nonexistent_exchange")
      publisher.channel_publish(channel, "test message")

      expect(exchange).to have_received(:publish).with("test message", hash_including(persistent: true))
    end

    it "respects hooks when publishing JSON messages" do
      Lepus::Producers.disable!("test_exchange")

      publisher = described_class.new("test_exchange")
      publisher.channel_publish(channel, {key: "value"})

      expect(exchange).not_to have_received(:publish)
    end

    it "respects hooks when publishing with custom options" do
      Lepus::Producers.disable!("test_exchange")

      publisher = described_class.new("test_exchange")
      publisher.channel_publish(channel, "test message", expiration: 60, content_type: "text/xml")

      expect(exchange).not_to have_received(:publish)
    end

    context "with exchange namespace configured" do
      before do
        allow(Lepus.config.producer_config).to receive(:exchange_namespace).and_return("ns")
      end

      it "publishes when namespaced exchange is enabled" do
        Lepus::Producers.enable!("ns.test_exchange")

        publisher = described_class.new("test_exchange")
        publisher.channel_publish(channel, "test message")

        expect(exchange).to have_received(:publish).with("test message", hash_including(persistent: true))
      end

      it "does not publish when namespaced exchange is disabled" do
        Lepus::Producers.disable!("ns.test_exchange")

        publisher = described_class.new("test_exchange")
        publisher.channel_publish(channel, "test message")

        expect(exchange).not_to have_received(:publish)
      end
    end
  end
end
