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
  let(:subscriber) { Lepus::LogSubscriber.new }

  before do
    previous_logger
    Lepus.logger = Logger.new(output)
  end

  after { Lepus.logger = previous_logger }

  def event(name, payload)
    now = Time.now
    ActiveSupport::Notifications::Event.new("#{name}.lepus", now, now, "id", payload)
  end

  it "logs a processed delivery with its result" do
    subscriber.process_delivery(event("process_delivery", consumer: "OrdersConsumer", routing_key: "orders.created", result: :ack))

    expect(output.string).to include("INFO").and include("Processed OrdersConsumer").and include('routing_key: "orders.created", result: :ack')
  end

  it "logs a consumer error" do
    subscriber.consumer_error(event("consumer_error", consumer: "OrdersConsumer", routing_key: "orders.created", error: RuntimeError.new("boom")))

    expect(output.string).to include("ERROR").and include("Error in OrdersConsumer").and include('error: "RuntimeError boom"')
  end
end
