# frozen_string_literal: true

require "spec_helper"
require "lepus/middlewares/exception_logger"

RSpec.describe Lepus::Middlewares::ExceptionLogger do
  let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
  let(:metadata) { instance_double(Bunny::MessageProperties) }
  let(:payload) { "payload" }
  let(:logger) { instance_double(Logger) }
  let(:middleware) do
    described_class.new(logger: logger)
  end
  let(:message) do
    Lepus::Message.new(delivery_info, metadata, payload)
  end

  before do
    allow(logger).to receive(:error)
  end

  it "returns the result of the downstream middleware" do
    result =
      middleware.call(message, proc { :moep })

    expect(result).to eq(:moep)
  end

  it "logs error when an error is raised and re-raises it" do
    error = RuntimeError.new("moep")
    expect(logger).to receive(:error).with("moep")

    expect do
      middleware.call(
        message,
        proc { raise error }
      )
    end.to raise_error(error)
  end
end
