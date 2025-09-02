# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Consumers::Handler do
  let(:channel) { instance_double(Bunny::Channel) }
  let(:queue) { instance_double(Bunny::Queue) }
  let(:consumer_class) { Class.new(Lepus::Consumer) }
  let(:consumer) { instance_double(consumer_class) }
  let(:handler) do
    described_class.new(consumer_class, channel, queue, "tag", {test: 1})
  end
  let(:delivery_info) do
    instance_double(Bunny::DeliveryInfo, delivery_tag: delivery_tag)
  end
  let(:delivery_tag) { 1 }
  let(:metadata) { instance_double(Bunny::MessageProperties) }
  let(:payload) { "my payload" }

  before do
    allow(channel).to receive(:generate_consumer_tag)
    allow(channel).to receive(:ack)
    handler.instance_variable_set(:@consumer, consumer)
  end

  it "sets the channel" do
    expect(handler.channel).to eq(channel)
  end

  it "sets the queue" do
    expect(handler.queue).to eq(queue)
  end

  it "sets the consumer_tag" do
    expect(handler.consumer_tag).to eq("tag")
  end

  it "sets the arguments" do
    expect(handler.arguments).to eq({test: 1})
  end

  describe "#process_delivery" do
    it "calls the consumer" do
      expect(consumer).to receive(:process_delivery).with(
        delivery_info,
        metadata,
        payload
      ).and_return(:ack)

      handler.process_delivery(delivery_info, metadata, payload)
    end

    it "returns the result of the consumer" do
      allow(consumer).to receive(:process_delivery).and_return(:ack)

      expect(handler.process_delivery(delivery_info, metadata, payload)).to eq(
        :ack
      )
    end

    it "acks the message if #work returns :ack" do
      allow(consumer).to receive(:process_delivery).and_return(:ack)

      expect(channel).to receive(:ack).with(delivery_tag, false)

      handler.process_delivery(delivery_info, metadata, payload)
    end

    it "rejects the message if #work returns :reject" do
      allow(consumer).to receive(:process_delivery).and_return(:reject)

      expect(channel).to receive(:reject).with(delivery_tag)

      handler.process_delivery(delivery_info, metadata, payload)
    end

    it "requeues the message if #work returns :requeue" do
      allow(consumer).to receive(:process_delivery).and_return(:requeue)

      expect(channel).to receive(:reject).with(delivery_tag, true)

      handler.process_delivery(delivery_info, metadata, payload)
    end
  end
end
