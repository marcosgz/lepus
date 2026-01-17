# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Consumer do
  let(:channel) { instance_double(Bunny::Channel) }
  let(:queue) { instance_double(Bunny::Queue) }
  let(:instance) { Class.new(described_class).new }
  let(:delivery_info) do
    instance_double(Bunny::DeliveryInfo, delivery_tag: delivery_tag)
  end
  let(:delivery_tag) { 1 }
  let(:metadata) { instance_double(Bunny::MessageProperties) }
  let(:payload) { "my payload" }
  let(:message) do
    Lepus::Message.new(delivery_info, metadata, payload)
  end

  before do
    allow(channel).to receive_messages(generate_consumer_tag: "test", number: 1)
    allow(channel).to receive(:ack).with(delivery_tag, false)
  end

  describe ".descendants" do
    specify do
      expect(described_class.descendants).to be_a(Array)
    end
  end

  describe ".abstract_class?" do
    it "returns true when is not configured" do
      expect(described_class.abstract_class?).to be true
    end

    it "returns false when configured" do
      instance.class.configure(queue: "test")
      expect(instance.class.abstract_class?).to be false
    end

    context "when abstract class is set" do
      let(:abstract_class) do
        Class.new(described_class) do
          self.abstract_class = true
        end
      end

      it "returns true" do
        expect(abstract_class.abstract_class?).to be true
        expect(abstract_class.config).to be_nil
      end
    end
  end

  describe ".configure" do
    let(:mandatory_options) do
      {queue: "test", exchange: "exchange", routing_key: ["test.new"]}
    end
    let(:custom_consumer_class) { Class.new(described_class) }

    it "sets the config" do
      custom_consumer_class.configure(mandatory_options)

      expect(custom_consumer_class.config).to be_a(Lepus::Consumers::Config)
      expect(custom_consumer_class.config.consumer_queue_args).to eq(["test", {durable: true}])
      expect(custom_consumer_class.config.exchange_options).to eq({durable: true, type: :topic})
      expect(custom_consumer_class.config.exchange_name).to eq("exchange")
      expect(custom_consumer_class.config.binds_args).to eq([{routing_key: "test.new"}])
    end
  end

  describe "#perform" do
    it "raises a not implemented error" do
      expect { instance.perform(message) }.to raise_error(
        NotImplementedError
      )
    end
  end

  describe "#process_delivery" do
    it "calls #perform" do
      expect(instance).to receive(:perform).with(
        message
      ).and_return(:ack)

      instance.process_delivery(delivery_info, metadata, payload)
    end

    it "returns the result of #perform" do
      allow(instance).to receive(:perform).and_return(:ack)

      expect(instance.process_delivery(delivery_info, metadata, payload)).to eq(
        :ack
      )
    end

    it "allows returning :ack" do
      allow(instance).to receive(:perform).and_return(:ack)

      expect(
        instance.process_delivery(delivery_info, metadata, payload)
      ).to be :ack
    end

    it "allows returning :reject" do
      allow(instance).to receive(:perform).and_return(:reject)

      expect(
        instance.process_delivery(delivery_info, metadata, payload)
      ).to be :reject
    end

    it "allows returning :requeue" do
      allow(instance).to receive(:perform).and_return(:requeue)

      expect(
        instance.process_delivery(delivery_info, metadata, payload)
      ).to be :requeue
    end

    it "allows returning :nack" do
      allow(instance).to receive(:perform).and_return(:nack)

      expect(
        instance.process_delivery(delivery_info, metadata, payload)
      ).to be :nack
    end

    it "raises an error if #perform does not return a valid symbol" do
      allow(instance).to receive(:perform).and_return(:blorg)

      expect {
        instance.process_delivery(delivery_info, metadata, payload)
      }.to raise_error(
        Lepus::InvalidConsumerReturnError,
        "#perform must return :ack, :reject or :requeue, received :blorg instead"
      )
    end
  end

  describe "#ack" do
    let(:instance) do
      Class.new(Lepus::Consumer) do
        def perform(_message)
          ack
        end
      end.new
    end

    it "returns :ack when called in #message" do
      expect(instance.perform(message)).to eq(:ack)
    end
  end

  describe "#reject" do
    let(:instance) do
      Class.new(Lepus::Consumer) do
        def perform(_message)
          reject
        end
      end.new
    end

    it "returns :reject when called in #perform" do
      expect(instance.perform(message)).to eq(:reject)
    end
  end

  describe "#requeue" do
    let(:instance) do
      Class.new(Lepus::Consumer) do
        def perform(_message)
          requeue
        end
      end.new
    end

    it "returns :requeue when called in #perform" do
      expect(instance.perform(message)).to eq(:requeue)
    end
  end

  describe "#nack" do
    let(:instance) do
      Class.new(Lepus::Consumer) do
        def perform(_message)
          nack
        end
      end.new
    end

    it "returns :nack when called in #perform" do
      expect(instance.perform(message)).to eq(:nack)
    end
  end

  describe ".use" do
    let(:instance) do
      Class.new(Lepus::Consumer) do
        use Middleware

        def perform(_message)
          ack
        end
      end.new
    end

    let(:instance_with_two_middlewares) do
      Class.new(Lepus::Consumer) do
        use Middleware
        use SecondMiddleware

        def perform(_message)
          ack
        end
      end.new
    end

    let(:middleware_class) do
      Class.new(Lepus::Middleware) do
        def call(message, app)
          app.call(message)
        end
      end
    end
    let(:middleware) { stub_const("Middleware", middleware_class) }
    let(:middleware_instance) { instance_double(Middleware) }
    let(:second_middleware) { stub_const("SecondMiddleware", middleware_class) }
    let(:second_middleware_instance) { instance_double(SecondMiddleware) }

    it "wraps the given middleware around the call to perform" do
      expect(middleware).to receive(:new).and_return(middleware_instance)
      expect(middleware_instance).to receive(:call) do |msg, app|
        expect(message).to eq(msg)
        app.call(msg)
      end

      expect(instance.process_delivery(delivery_info, metadata, payload)).to eq(
        :ack
      )
    end

    it "calls middlewares in the correct order" do
      expect(middleware).to receive(:new).and_return(
        middleware_instance
      ).ordered
      expect(second_middleware).to receive(:new).and_return(
        second_middleware_instance
      ).ordered
      expect(middleware_instance).to receive(:call) do |m, app|
        app.call(m)
      end.ordered
      expect(second_middleware_instance).to receive(:call) do |m, app|
        app.call(m)
      end.ordered

      expect(
        instance_with_two_middlewares.process_delivery(
          delivery_info,
          metadata,
          payload
        )
      ).to eq(:ack)
    end
  end

  describe "#publish_message" do
    let(:test_producer_class) do
      Class.new(Lepus::Producer) do
        configure(exchange: "test_exchange")
      end
    end
    let(:consumer_class) do
      Class.new(Lepus::Consumer) do
        configure(
          queue: "test_queue",
          exchange: "test_exchange",
          routing_key: "test.routing.key",
          exchange_options: {type: :topic, durable: true}
        )
      end
    end
    let(:instance) { consumer_class.new }
    let(:mock_connection) { instance_double(Bunny::Session) }
    let(:mock_channel) { instance_double(Bunny::Channel) }
    let(:mock_exchange) { instance_double(Bunny::Exchange) }
    let(:test_message) { "test message" }
    let(:test_hash_message) { {key: "value"} }

    before do
      stub_const("TestProducerClass", test_producer_class)
      allow(Lepus.config.producer_config).to receive(:with_connection).and_yield(mock_connection)
      allow(mock_connection).to receive(:with_channel).and_yield(mock_channel)
      allow(mock_channel).to receive(:exchange).and_return(mock_exchange)
      allow(mock_exchange).to receive(:publish)
      Lepus::Producers::Hooks.reset!
    end

    after do
      Lepus::Producers::Hooks.reset!
    end

    context "when exchange is enabled and no channel parameter" do
      before do
        Lepus::Producers.enable!(test_producer_class)
      end

      it "publishes message using default exchange and publish method" do
        instance.send(:publish_message, test_message)

        expect(Lepus.config.producer_config).to have_received(:with_connection)
        expect(mock_connection).to have_received(:with_channel)
        expect(mock_channel).to have_received(:exchange).with("test_exchange", {type: :topic, durable: true, auto_delete: false})
        expect(mock_exchange).to have_received(:publish).with(test_message, hash_including(persistent: true))
      end

      it "publishes hash message as JSON" do
        instance.send(:publish_message, test_hash_message)

        expect(mock_exchange).to have_received(:publish).with(
          MultiJson.dump(test_hash_message),
          hash_including(content_type: "application/json", persistent: true)
        )
      end

      it "merges custom options with exchange options" do
        instance.send(:publish_message, test_message, expiration: 60, content_type: "text/xml")

        expect(mock_exchange).to have_received(:publish).with(
          test_message,
          hash_including(expiration: 60, content_type: "text/xml", persistent: true)
        )
      end
    end

    context "when exchange is enabled and with channel parameter" do
      let(:provided_channel) { instance_double(Bunny::Channel) }

      before do
        Lepus::Producers.enable!(test_producer_class)
        allow(provided_channel).to receive(:exchange).and_return(mock_exchange)
      end

      it "publishes message using provided channel and channel_publish method" do
        instance.send(:publish_message, test_message, channel: provided_channel)

        expect(Lepus.config.producer_config).not_to have_received(:with_connection)
        expect(provided_channel).to have_received(:exchange).with("test_exchange", {type: :topic, durable: true, auto_delete: false})
        expect(mock_exchange).to have_received(:publish).with(test_message, hash_including(persistent: true))
      end

      it "publishes hash message as JSON using provided channel" do
        instance.send(:publish_message, test_hash_message, channel: provided_channel)

        expect(mock_exchange).to have_received(:publish).with(
          MultiJson.dump(test_hash_message),
          hash_including(content_type: "application/json", persistent: true)
        )
      end

      it "merges custom options when using provided channel" do
        instance.send(:publish_message, test_message, channel: provided_channel, expiration: 30)

        expect(mock_exchange).to have_received(:publish).with(
          test_message,
          hash_including(expiration: 30, persistent: true)
        )
      end
    end

    context "when exchange is enabled and with custom exchange_name" do
      before do
        Lepus::Producers.enable!(test_producer_class)
      end

      it "uses custom exchange name instead of consumer's exchange" do
        instance.send(:publish_message, test_message, exchange_name: "custom_exchange")

        expect(mock_channel).to have_received(:exchange).with("custom_exchange", {type: :topic, durable: true, auto_delete: false})
        expect(mock_exchange).to have_received(:publish).with(test_message, hash_including(persistent: true))
      end

      it "uses default exchange options for custom exchange" do
        instance.send(:publish_message, test_message, exchange_name: "custom_exchange", type: :direct)

        expect(mock_channel).to have_received(:exchange).with("custom_exchange", {type: :direct, durable: true, auto_delete: false})
      end

      it "merges custom options for custom exchange" do
        instance.send(:publish_message, test_message, exchange_name: "custom_exchange", expiration: 120)

        expect(mock_exchange).to have_received(:publish).with(
          test_message,
          hash_including(expiration: 120, persistent: true)
        )
      end
    end

    context "when exchange is enabled and with handler channel" do
      before do
        Lepus::Producers.enable!(test_producer_class)
        # Simulate the handler setting the channel
        instance.instance_variable_set(:@_handler_channel, mock_channel)
        allow(mock_channel).to receive(:exchange).and_return(mock_exchange)
      end

      it "uses handler channel when no channel parameter is provided" do
        instance.send(:publish_message, test_message)

        expect(Lepus.config.producer_config).not_to have_received(:with_connection)
        expect(mock_channel).to have_received(:exchange).with("test_exchange", {type: :topic, durable: true, auto_delete: false})
        expect(mock_exchange).to have_received(:publish).with(test_message, hash_including(persistent: true))
      end

      it "prioritizes provided channel over handler channel" do
        provided_channel = instance_double(Bunny::Channel)
        allow(provided_channel).to receive(:exchange).and_return(mock_exchange)

        instance.send(:publish_message, test_message, channel: provided_channel)

        expect(provided_channel).to have_received(:exchange)
        expect(mock_channel).not_to have_received(:exchange)
      end
    end

    context "when exchange is disabled" do
      before do
        Lepus::Producers.disable!(test_producer_class)
      end

      it "does not publish message" do
        instance.send(:publish_message, test_message)

        expect(Lepus.config.producer_config).not_to have_received(:with_connection)
        expect(mock_exchange).not_to have_received(:publish)
      end

      it "does not publish message even with channel parameter" do
        provided_channel = instance_double(Bunny::Channel)
        allow(provided_channel).to receive(:exchange).and_return(mock_exchange)

        instance.send(:publish_message, test_message, channel: provided_channel)

        expect(provided_channel).not_to have_received(:exchange)
        expect(mock_exchange).not_to have_received(:publish)
      end

      it "does not publish message with custom exchange_name when that exchange is disabled" do
        custom_producer_class = Class.new(Lepus::Producer) do
          configure(exchange: "custom_exchange")
        end
        stub_const("CustomProducerClass", custom_producer_class)

        Lepus::Producers.disable!(custom_producer_class)

        instance.send(:publish_message, test_message, exchange_name: "custom_exchange")

        expect(Lepus.config.producer_config).not_to have_received(:with_connection)
        expect(mock_exchange).not_to have_received(:publish)
      end
    end

    context "with producer class hooks" do
      it "respects producer class enable/disable" do
        Lepus::Producers.enable!(test_producer_class)

        instance.send(:publish_message, test_message)

        expect(mock_exchange).to have_received(:publish)
      end

      it "does not publish when producer class is disabled" do
        Lepus::Producers.disable!(test_producer_class)

        instance.send(:publish_message, test_message)

        expect(mock_exchange).not_to have_received(:publish)
      end
    end

    context "with exchange options merging" do
      it "uses consumer exchange options for same exchange" do
        instance.send(:publish_message, test_message, exchange_name: "test_exchange", durable: false)

        expect(mock_channel).to have_received(:exchange).with(
          "test_exchange",
          {type: :topic, durable: false, auto_delete: false}
        )
      end

      it "uses only custom options for different exchange" do
        instance.send(:publish_message, test_message, exchange_name: "other_exchange", type: :direct, durable: false)

        expect(mock_channel).to have_received(:exchange).with(
          "other_exchange",
          {type: :direct, durable: false, auto_delete: false}
        )
      end
    end

    context "with unknown exchange (default enabled)" do
      it "publishes to unknown exchange by default" do
        instance.send(:publish_message, test_message, exchange_name: "unknown_exchange")

        expect(mock_exchange).to have_received(:publish).with(test_message, hash_including(persistent: true))
      end
    end
  end
end
