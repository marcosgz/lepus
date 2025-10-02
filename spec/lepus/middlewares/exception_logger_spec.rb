# frozen_string_literal: true

require "spec_helper"
require "lepus/middlewares/exception_logger"

RSpec.describe Lepus::Middlewares::ExceptionLogger do
  let(:delivery_info) { instance_double(Bunny::DeliveryInfo) }
  let(:metadata) { instance_double(Bunny::MessageProperties) }
  let(:payload) { "payload" }
  let(:logger) { instance_double(Logger) }
  let(:app) { proc { :result } }
  let(:middleware) do
    described_class.new(app, logger: logger)
  end
  let(:message) do
    Lepus::Message.new(delivery_info, metadata, payload)
  end

  before do
    allow(logger).to receive(:error)
  end

  it "returns the result of the downstream middleware" do
    result = middleware.call(message)

    expect(result).to eq(:result)
  end

  it "logs error when an error is raised and re-raises it" do
    error = RuntimeError.new("moep")
    expect(logger).to receive(:error).with("moep")

    middleware = described_class.new(proc { raise error }, logger: logger)

    expect do
      middleware.call(message)
    end.to raise_error(error)
  end
end
