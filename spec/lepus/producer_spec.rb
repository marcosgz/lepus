# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Producer do
  let(:exchange_name) { "test_exchange" }
  let(:producer) { described_class.new(exchange_name) }

  describe "#initialize" do
    it "sets the exchange name" do
      expect(producer.instance_variable_get(:@exchange_name)).to eq(exchange_name)
    end

    it "sets the exchange options" do
      expect(producer.instance_variable_get(:@exchange_options)).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS
      )

      producer = described_class.new(exchange_name, type: :direct, durable: false, auto_delete: true)
      expect(producer.instance_variable_get(:@exchange_options)).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS.merge(type: :direct, durable: false, auto_delete: true)
      )

      producer = described_class.new(exchange_name, type: :direct)
      expect(producer.instance_variable_get(:@exchange_options)).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS.merge(type: :direct)
      )

      producer = described_class.new(exchange_name, durable: false)
      expect(producer.instance_variable_get(:@exchange_options)).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS.merge(durable: false)
      )

      producer = described_class.new(exchange_name, auto_delete: true)
      expect(producer.instance_variable_get(:@exchange_options)).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS.merge(auto_delete: true)
      )

      producer = described_class.new(exchange_name, type: :direct, durable: false)
      expect(producer.instance_variable_get(:@exchange_options)).to eq(
        described_class::DEFAULT_EXCHANGE_OPTIONS.merge(type: :direct, durable: false)
      )
    end
  end

  describe "#publish" do
    let(:options) { {expiration: 60} }

    context "when the message is different than String" do
      let(:message) { {key: "value"} }

      it "publishes the message to the exchange as JSON" do
        bunny = instance_double(Bunny::Session)
        channel = instance_double(Bunny::Channel)
        exchange = instance_double(Bunny::Exchange)

        allow(producer).to receive(:bunny).and_return(bunny)
        expect(bunny).to receive(:with_channel).and_yield(channel)
        allow(channel).to receive(:exchange).and_return(exchange)
        allow(exchange).to receive(:publish)

        producer.publish(message, **options)

        expect(channel).to have_received(:exchange).with(exchange_name, described_class::DEFAULT_EXCHANGE_OPTIONS)
        expect(exchange).to have_received(:publish).with(MultiJson.dump(message),
          described_class::DEFAULT_PUBLISH_OPTIONS.merge(options).merge(content_type: "application/json"))
      end
    end

    context "when the message is a String" do
      let(:message) { "test message" }

      it "publishes the message to the exchange as text" do
        bunny = instance_double(Bunny::Session)
        channel = instance_double(Bunny::Channel)
        exchange = instance_double(Bunny::Exchange)

        allow(producer).to receive(:bunny).and_return(bunny)
        expect(bunny).to receive(:with_channel).and_yield(channel)
        allow(channel).to receive(:exchange).and_return(exchange)
        allow(exchange).to receive(:publish)

        producer.publish(message, **options)

        expect(channel).to have_received(:exchange).with(exchange_name, described_class::DEFAULT_EXCHANGE_OPTIONS)
        expect(exchange).to have_received(:publish).with(message,
          described_class::DEFAULT_PUBLISH_OPTIONS.merge(options).merge(content_type: "text/plain"))
      end
    end
  end
end
