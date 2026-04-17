# frozen_string_literal: true

# rubocop:disable RSpec/MultipleDescribes

require "spec_helper"
begin
  require "active_support"
  require "active_support/notifications"
  HAS_ACTIVE_SUPPORT = true
rescue LoadError
  HAS_ACTIVE_SUPPORT = false
end
require "lepus/prometheus"
require "lepus/prometheus/collector"

RSpec.describe Lepus::Prometheus do
  let(:fake_client) do
    Class.new do
      attr_reader :sent
      def initialize
        @sent = []
      end

      def send_json(payload)
        @sent << payload
      end
    end.new
  end

  before { described_class.client = fake_client }
  after { described_class.client = nil }

  describe ".emit" do
    it "forwards payloads to the configured client with type=lepus" do
      described_class.emit(:delivery, consumer: "MyConsumer", result: "ack")

      expect(fake_client.sent).to eq([
        {type: "lepus", metric: "delivery", consumer: "MyConsumer", result: "ack"}
      ])
    end

    it "swallows transport errors so callers cannot fail" do
      broken = Object.new
      def broken.send_json(*)
        raise IOError, "down"
      end
      described_class.client = broken

      expect { described_class.emit(:delivery) }.not_to raise_error
    end
  end

  describe "publish event subscription", if: HAS_ACTIVE_SUPPORT do
    it "emits a publish metric when publish.lepus is instrumented" do
      ActiveSupport::Notifications.instrument("publish.lepus", exchange: "orders", routing_key: "created") {}

      publish = fake_client.sent.find { |p| p[:metric] == "publish" }
      expect(publish).to include(type: "lepus", metric: "publish", exchange: "orders", routing_key: "created")
      expect(publish[:duration]).to be >= 0
    end
  end
end

RSpec.describe Lepus::Prometheus::Instrumentation::QueuePoller do
  let(:fake_client) do
    Class.new do
      attr_reader :sent
      def initialize
        @sent = []
      end

      def send_json(payload)
        @sent << payload
      end
    end.new
  end

  let(:api) do
    Class.new do
      def queues
        [{name: "q1", messages: 5, messages_ready: 3, messages_unacknowledged: 2, consumers: 1, memory: 1024}]
      end
    end.new
  end

  before { Lepus::Prometheus.client = fake_client }

  after do
    described_class.stop
    Lepus::Prometheus.client = nil
  end

  it "emits one queue metric per queue and keeps running" do
    described_class.start(interval: 0.05, api: api)
    sleep 0.1
    described_class.stop

    queue_events = fake_client.sent.select { |p| p[:metric] == "queue" }
    expect(queue_events).not_to be_empty
    expect(queue_events.first).to include(
      metric: "queue",
      name: "q1",
      messages: 5,
      messages_ready: 3,
      messages_unacknowledged: 2,
      consumers: 1,
      memory: 1024
    )
  end
end

RSpec.describe Lepus::Prometheus::Collector do
  subject(:collector) { described_class.new }

  def metric_named(name)
    collector.metrics.find { |m| m.name == name }
  end

  def render(metric)
    metric.metric_text
  end

  it "declares type 'lepus'" do
    expect(collector.type).to eq("lepus")
  end

  describe "delivery metric" do
    it "tracks messages and duration with consumer/queue/result labels" do
      collector.collect(
        "metric" => "delivery",
        "consumer" => "OrdersConsumer",
        "queue" => "orders.q",
        "result" => "ack",
        "duration" => 0.12
      )

      counter = metric_named("lepus_messages_processed_total")
      expect(counter).not_to be_nil
      expect(render(counter)).to include('consumer="OrdersConsumer"')
      expect(render(counter)).to include('queue="orders.q"')
      expect(render(counter)).to include('result="ack"')

      hist = metric_named("lepus_delivery_duration_seconds")
      expect(hist).not_to be_nil
      expect(render(hist)).to include('consumer="OrdersConsumer"')
    end
  end

  describe "publish metric" do
    it "tracks a counter and histogram with exchange/routing_key labels" do
      collector.collect(
        "metric" => "publish",
        "exchange" => "events",
        "routing_key" => "order.created",
        "duration" => 0.002
      )

      counter = metric_named("lepus_messages_published_total")
      expect(render(counter)).to include('exchange="events"')
      expect(render(counter)).to include('routing_key="order.created"')

      expect(metric_named("lepus_publish_duration_seconds")).not_to be_nil
    end
  end

  describe "process metric" do
    it "records RSS gauge with kind/name/pid labels" do
      collector.collect(
        "metric" => "process",
        "kind" => "Worker",
        "name" => "default",
        "pid" => 4242,
        "rss_memory" => 123_456
      )

      gauge = metric_named("lepus_process_rss_memory_bytes")
      expect(gauge).not_to be_nil
      expect(render(gauge)).to include('kind="Worker"')
      expect(render(gauge)).to include('name="default"')
      expect(render(gauge)).to include('pid="4242"')
    end
  end

  describe "queue metric" do
    it "records all queue gauges labeled by name" do
      collector.collect(
        "metric" => "queue",
        "name" => "orders.q",
        "messages" => 10,
        "messages_ready" => 7,
        "messages_unacknowledged" => 3,
        "consumers" => 2,
        "memory" => 2048
      )

      %w[
        lepus_queue_messages
        lepus_queue_messages_ready
        lepus_queue_messages_unacknowledged
        lepus_queue_consumers
        lepus_queue_memory_bytes
      ].each do |n|
        expect(metric_named(n)).not_to be_nil, "expected collector to register #{n}"
        expect(render(metric_named(n))).to include('name="orders.q"')
      end
    end
  end

  it "ignores unknown metric payloads" do
    expect { collector.collect("metric" => "bogus") }.not_to raise_error
    expect(collector.metrics).to be_empty
  end
end
# rubocop:enable RSpec/MultipleDescribes
