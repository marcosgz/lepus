# frozen_string_literal: true

require "spec_helper"

begin
  require "active_support"
  require "active_support/log_subscriber"
  require "lepus/rails/log_subscriber"
rescue LoadError
  nil
end

RSpec.describe "Lepus::LogSubscriber", if: defined?(Lepus::LogSubscriber) do
  let(:output) { StringIO.new }
  let(:previous_logger) { Lepus.logger }

  before do
    previous_logger
    Lepus.logger = Logger.new(output)
    Lepus::LogSubscriber.attach_to(:lepus)
  end

  after do
    Lepus::LogSubscriber.detach_from(:lepus)
    Lepus.logger = previous_logger
  end

  it "logs a processed delivery with its result" do
    ActiveSupport::Notifications.instrument("process_delivery.lepus", consumer: "OrdersConsumer", routing_key: "orders.created", result: :ack) {}

    expect(output.string).to include("INFO").and include("Processed OrdersConsumer").and include('routing_key: "orders.created", result: :ack')
  end

  it "logs a consumer error" do
    ActiveSupport::Notifications.instrument("consumer_error.lepus", consumer: "OrdersConsumer", routing_key: "orders.created", error: RuntimeError.new("boom"))

    expect(output.string).to include("ERROR").and include("Error in OrdersConsumer").and include('error: "RuntimeError boom"')
  end
end
