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
  end

  describe "#channel_publish with delay" do
    let(:connection) { instance_double(Bunny::Session) }
    let(:channel) { instance_double(Bunny::Channel, connection: connection) }
    let(:exchange) { instance_double(Bunny::Exchange) }

    before do
      Lepus::Delay.reset!
      allow(channel).to receive(:exchange).and_return(exchange)
      allow(channel).to receive(:exchange_declare)
      allow(channel).to receive(:queue_declare)
      allow(channel).to receive(:queue_bind)
      allow(channel).to receive(:basic_publish)
      allow(exchange).to receive(:publish)
      allow(connection).to receive(:with_channel).and_yield(channel)
    end

    after { Lepus::Delay.reset! }

    it "publishes to the delayed exchange with the delay header and the original routing key" do
      publisher.channel_publish(channel, {key: "value"}, routing_key: "user.created", headers: {"tenant" => "a"}, delay: 500)

      expect(channel).to have_received(:exchange).with(exchange_name, described_class::DEFAULT_EXCHANGE_OPTIONS)
      expect(exchange).not_to have_received(:publish)
      expect(channel).to have_received(:queue_declare).with(
        "test_exchange.delayed.500",
        durable: true,
        arguments: Lepus::Delay.queue_args_for_exchange(exchange_name, 500)
      )
      expect(channel).to have_received(:basic_publish).with(
        MultiJson.dump(key: "value"),
        "test_exchange.delayed",
        "user.created",
        {
          headers: {"tenant" => "a", "lepus-delay" => 500},
          persistent: true,
          content_type: "application/json"
        }
      )
    end

    it "accepts objects responding to in_milliseconds" do
      publisher.channel_publish(channel, "msg", delay: Struct.new(:in_milliseconds).new(1000))

      expect(channel).to have_received(:basic_publish).with(
        "msg", "test_exchange.delayed", nil, hash_including(headers: {"lepus-delay" => 1000})
      )
    end

    it "raises for invalid delays before publishing" do
      expect {
        publisher.channel_publish(channel, "msg", delay: -1)
      }.to raise_error(ArgumentError)

      expect(channel).not_to have_received(:basic_publish)
    end

    it "instruments the delay" do
      allow(Lepus).to receive(:instrument).and_call_original

      publisher.channel_publish(channel, "msg", routing_key: "a", delay: 500)

      expect(Lepus).to have_received(:instrument).with(:publish, exchange: exchange_name, routing_key: "a", delay: 500)
    end

    context "with the default exchange" do
      let(:publisher) { described_class.new("") }

      it "publishes to the delay queue of the routing key queue" do
        publisher.channel_publish(channel, "msg", routing_key: "jobs", delay: 300)

        expect(channel).to have_received(:queue_declare).with(
          "jobs.delay.300",
          durable: true,
          arguments: Lepus::Delay.queue_args_for_queue("jobs", 300)
        )
        expect(channel).not_to have_received(:exchange_declare)
        expect(channel).to have_received(:basic_publish).with(
          "msg", "", "jobs.delay.300", {persistent: true, content_type: "text/plain"}
        )
      end

      it "requires a routing key" do
        expect {
          publisher.channel_publish(channel, "msg", delay: 300)
        }.to raise_error(ArgumentError, /routing_key/)
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
  end

  describe "named connections" do
    let(:mock_connection) { instance_double(Bunny::Session) }
    let(:channel) { instance_double(Bunny::Channel) }
    let(:exchange) { instance_double(Bunny::Exchange, publish: nil) }

    before do
      allow(Lepus.config.producer_config).to receive(:with_connection).and_yield(mock_connection)
      allow(mock_connection).to receive(:with_channel).and_yield(channel)
      allow(channel).to receive(:exchange).and_return(exchange)
    end

    it "uses the default connection by default" do
      publisher.publish("message")

      expect(publisher.connection).to eq(:default)
      expect(Lepus.config.producer_config).to have_received(:with_connection).with(:default)
    end

    it "publishes through the given connection" do
      named_publisher = described_class.new(exchange_name, connection: "analytics")
      named_publisher.publish("message")

      expect(named_publisher.connection).to eq(:analytics)
      expect(Lepus.config.producer_config).to have_received(:with_connection).with(:analytics)
    end

    it "does not pass the connection to the exchange declaration" do
      described_class.new(exchange_name, connection: :analytics).publish("message")

      expect(channel).to have_received(:exchange).with(exchange_name, described_class::DEFAULT_EXCHANGE_OPTIONS)
    end
  end
end
