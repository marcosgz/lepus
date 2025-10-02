# frozen_string_literal: true

require "spec_helper"
require "lepus/middlewares/honeybadger"

RSpec.describe Lepus::Middlewares::Honeybadger do
  let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
  let(:metadata) { instance_double(Bunny::MessageProperties) }
  let(:payload) { "payload" }
  let(:honeybadger) do
    stub_const("Honeybadger", Class.new do
      def self.add_breadcrumb(*)
      end

      def self.notify(*)
      end
    end)
  end
  let(:middleware) do
    described_class.new(class_name: "MyConsumer")
  end
  let(:message) do
    Lepus::Message.new(delivery_info, metadata, payload)
  end

  it "returns the result of the downstream middleware" do
    result =
      middleware.call(message, proc { :moep })

    expect(result).to eq(:moep)
  end

  it "calls notify when an error is raised" do
    error = RuntimeError.new("moep")
    expect(honeybadger).to receive(:notify).with(error, context: {class_name: "MyConsumer"})

    expect do
      middleware.call(
        message,
        proc { raise error }
      )
    end.to raise_error(error)
  end

  context "when no class_name is provided" do
    let(:middleware) { described_class.new }
    let(:consumer_class) { Class.new }

    before do
      message.consumer_class = consumer_class
      allow(consumer_class).to receive(:name).and_return("TestConsumer")
    end

    it "uses consumer_class name as fallback" do
      error = RuntimeError.new("moep")
      expect(honeybadger).to receive(:notify).with(error, context: {class_name: "TestConsumer"})

      expect do
        middleware.call(
          message,
          proc { raise error }
        )
      end.to raise_error(error)
    end
  end

  context "when no class_name and no consumer_class" do
    let(:middleware) { described_class.new }

    it "uses empty context" do
      error = RuntimeError.new("moep")
      expect(honeybadger).to receive(:notify).with(error, context: {})

      expect do
        middleware.call(
          message,
          proc { raise error }
        )
      end.to raise_error(error)
    end
  end
end
