# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Publisher do
  let(:exchange_name) { "test_exchange" }
  let(:bunny) { instance_double(Bunny::Session) }
  let(:publisher) { described_class.new(exchange_name) }

  describe "#initialize" do
    it "sets the exchange name" do
      expect(publisher.instance_variable_get(:@exchange_name)).to eq(exchange_name)
    end

    it "sets the exchange options" do
      expect(publisher.instance_variable_get(:@exchange_options)).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS
      )

      publisher = described_class.new(exchange_name, type: :direct, durable: false, auto_delete: true)
      expect(publisher.instance_variable_get(:@exchange_options)).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS.merge(type: :direct, durable: false, auto_delete: true)
      )

      publisher = described_class.new(exchange_name, type: :direct)
      expect(publisher.instance_variable_get(:@exchange_options)).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS.merge(type: :direct)
      )

      publisher = described_class.new(exchange_name, durable: false)
      expect(publisher.instance_variable_get(:@exchange_options)).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS.merge(durable: false)
      )

      publisher = described_class.new(exchange_name, auto_delete: true)
      expect(publisher.instance_variable_get(:@exchange_options)).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS.merge(auto_delete: true)
      )

      publisher = described_class.new(exchange_name, type: :direct, durable: false)
      expect(publisher.instance_variable_get(:@exchange_options)).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS.merge(type: :direct, durable: false)
      )
    end
  end

  describe "#publish" do
    let(:options) { {expiration: 60} }

    before do
      allow(Lepus.config.producer_config).to receive(:with_connection).and_yield(bunny)
    end

    context "when the message is different than String" do
      let(:message) { {key: "value"} }

      it "publishes the message to the exchange as JSON" do
        channel = instance_double(Bunny::Channel)
        exchange = instance_double(Bunny::Exchange)

        expect(bunny).to receive(:with_channel).and_yield(channel)
        allow(channel).to receive(:exchange).and_return(exchange)
        allow(exchange).to receive(:publish)

        publisher.publish(message, **options)

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

    context "when the message is a String" do
      let(:message) { "test message" }

      it "publishes the message to the exchange as text" do
        channel = instance_double(Bunny::Channel)
        exchange = instance_double(Bunny::Exchange)

        expect(bunny).to receive(:with_channel).and_yield(channel)
        allow(channel).to receive(:exchange).and_return(exchange)
        allow(exchange).to receive(:publish)

        publisher.publish(message, **options)

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
  end

  describe "hooks integration" do
    let(:test_producer_class) do
      Class.new(Lepus::Producer) do
        configure(exchange: "test_exchange")
      end
    end

    let(:mock_connection) { double("connection") }
    let(:mock_channel) { double("channel") }
    let(:mock_exchange) { double("exchange") }

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

      publisher = Lepus::Publisher.new("test_exchange")
      publisher.publish("test message")

      expect(mock_exchange).to have_received(:publish).with("test message", hash_including(persistent: true))
    end

    it "does not publish when exchange is disabled" do
      Lepus::Producers.disable!("test_exchange")

      publisher = Lepus::Publisher.new("test_exchange")
      publisher.publish("test message")

      expect(mock_exchange).not_to have_received(:publish)
    end

    it "publishes when exchange is enabled via producer class" do
      Lepus::Producers.enable!(test_producer_class)

      publisher = Lepus::Publisher.new("test_exchange")
      publisher.publish("test message")

      expect(mock_exchange).to have_received(:publish).with("test message", hash_including(persistent: true))
    end

    it "does not publish when exchange is disabled via producer class" do
      Lepus::Producers.disable!(test_producer_class)

      publisher = Lepus::Publisher.new("test_exchange")
      publisher.publish("test message")

      expect(mock_exchange).not_to have_received(:publish)
    end

    it "publishes for exchanges with no producers (default enabled)" do
      publisher = Lepus::Publisher.new("nonexistent_exchange")
      publisher.publish("test message")

      expect(mock_exchange).to have_received(:publish).with("test message", hash_including(persistent: true))
    end
  end
end
