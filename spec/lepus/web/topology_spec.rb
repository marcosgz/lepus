# frozen_string_literal: true

require "spec_helper"
require "lepus/web"

RSpec.describe Lepus::Web::Topology do
  subject(:topology) { described_class.new(management_api: management_api, aggregator: aggregator, show_all_exchanges: show_all) }

  let(:show_all) { false }
  let(:management_api) { instance_double(Lepus::Web::ManagementAPI) }
  let(:aggregator) { instance_double(Lepus::Web::Aggregator, running?: true, all_processes: processes) }
  let(:processes) do
    [{
      id: "w1", name: "default", hostname: "app-1", pid: 10, kind: "Worker", application: "orders-service",
      consumers: [{class_name: "FulfillmentConsumer", exchange: "orders", queue: "orders.fulfillment", threads: 2,
                   processed: 90, rejected: 3, errored: 1, retry_queue: "orders.fulfillment.retry", error_queue: "orders.fulfillment.error"}]
    }]
  end

  def queue(name, arguments = {}, **extra)
    {name: name, type: "classic", messages: 0, messages_ready: 0, messages_unacknowledged: 0, consumers: 0,
     arguments: arguments, exclusive: false, messages_ready_rate: 0.0, message_stats: {}}.merge(extra)
  end

  before do
    allow(management_api).to receive_messages(
      queues: [
        queue("orders.fulfillment", {"x-dead-letter-exchange" => "", "x-dead-letter-routing-key" => "orders.fulfillment.retry"},
          messages_ready: 12, consumers: 2, message_stats: {publish_rate: 4.0, deliver_get_rate: 3.5, ack_rate: 3.4}),
        queue("orders.fulfillment.retry", {"x-dead-letter-exchange" => "", "x-dead-letter-routing-key" => "orders.fulfillment", "x-message-ttl" => 5000}),
        queue("orders.fulfillment.error"),
        queue("orders.fulfillment.delay.60000", {"x-dead-letter-exchange" => "", "x-dead-letter-routing-key" => "orders.fulfillment", "x-message-ttl" => 60_000}),
        queue("orders.delayed.30000", {"x-dead-letter-exchange" => "orders", "x-message-ttl" => 30_000}),
        queue("invoices.main", {"x-dead-letter-exchange" => "", "x-dead-letter-routing-key" => "invoices.dead"}),
        queue("invoices.dead"),
        queue("amq.gen-abc", exclusive: true)
      ],
      exchanges: [
        {name: "orders", type: "topic", message_stats: {publish_in_rate: 4.0}},
        {name: "orders.delayed", type: "headers", message_stats: {}},
        {name: "invoices", type: "direct", message_stats: {}}
      ],
      bindings: [
        {source: "orders", destination: "orders.fulfillment", destination_type: "queue", routing_key: "order.paid"},
        {source: "orders", destination: "orders.fulfillment", destination_type: "queue", routing_key: "order.created"},
        {source: "orders.delayed", destination: "orders.delayed.30000", destination_type: "queue", routing_key: ""},
        {source: "invoices", destination: "invoices.main", destination_type: "queue", routing_key: "invoice"}
      ],
      consumers: [
        {queue: "orders.fulfillment", consumer_tag: "FulfillmentConsumer-1", connection_name: "Lepus default", prefetch_count: 10},
        {queue: "orders.fulfillment", consumer_tag: "FulfillmentConsumer-2", connection_name: "Lepus default", prefetch_count: 10},
        {queue: "invoices.main", consumer_tag: "bunny-1-2", connection_name: "billing app", prefetch_count: 5}
      ]
    )
  end

  def roles(result)
    result[:queues].map { |q| [q[:name], [q[:role], q[:parent] || q[:parent_exchange]]] }.to_h
  end

  context "with all exchanges shown" do
    let(:show_all) { true }

    it "classifies retry, error and delay queues by their arguments and the consumers' declarations" do
      expect(roles(topology.to_h)).to eq(
        "orders.fulfillment" => ["main", nil],
        "orders.fulfillment.retry" => ["retry", "orders.fulfillment"],
        "orders.fulfillment.error" => ["error", "orders.fulfillment"],
        "orders.fulfillment.delay.60000" => ["delay", "orders.fulfillment"],
        "orders.delayed.30000" => ["delay", "orders"],
        "invoices.main" => ["main", nil],
        "invoices.dead" => ["error", "invoices.main"]
      )
    end

    it "groups routing keys per binding and flattens queue rates" do
      result = topology.to_h

      expect(result[:management]).to be(true)
      expect(result[:bindings]).to include(source: "orders", destination: "orders.fulfillment", destination_type: "queue", routing_keys: %w[order.paid order.created])
      main = result[:queues].find { |q| q[:name] == "orders.fulfillment" }
      expect(main).to include(ready: 12, consumers: 2, publish_rate: 4.0, deliver_rate: 3.5, ack_rate: 3.4, ttl: nil, application: "orders-service")
    end

    it "describes where each child queue sends its messages" do
      queues = topology.to_h[:queues].to_h { |q| [q[:name], q] }

      expect(queues["orders.fulfillment.retry"]).to include(ttl: 5000, dead_letter_exchange: "", dead_letter_routing_key: "orders.fulfillment", expires: nil)
      expect(queues["orders.delayed.30000"]).to include(ttl: 30_000, dead_letter_exchange: "orders", dead_letter_routing_key: nil)
      expect(queues["orders.fulfillment.error"]).to include(ttl: nil, dead_letter_exchange: nil, dead_letter_routing_key: nil, expires: nil)
    end

    it "merges heartbeat counters with the broker's subscriptions" do
      consumers = topology.to_h[:consumers]

      expect(consumers).to contain_exactly(
        include(queue: "orders.fulfillment", class_name: "FulfillmentConsumer", reporting: true, channels: 2, prefetch: 10, threads: 2, processed: 90, errored: 1),
        include(queue: "invoices.main", class_name: nil, connection_name: "billing app", reporting: false, channels: 1)
      )
    end
  end

  context "when the queue consumers read has a TTL of its own" do
    let(:show_all) { true }
    let(:processes) do
      [{id: "w1", name: "default", hostname: "app-1", pid: 10, kind: "Worker",
        consumers: [{class_name: "OrdersConsumer", exchange: "orders", queue: "orders"}]}]
    end

    def roles_for(queues, bindings: [], heartbeats: processes)
      allow(management_api).to receive_messages(queues: queues, exchanges: [], bindings: bindings, consumers: [])
      allow(aggregator).to receive(:all_processes).and_return(heartbeats)
      roles(topology.to_h)
    end

    it "keeps it as the main queue when it expires into a dead letter queue" do
      result = roles_for([
        queue("orders", {"x-message-ttl" => 86_400_000, "x-dead-letter-exchange" => "", "x-dead-letter-routing-key" => "orders.dlq"}),
        queue("orders.dlq")
      ])

      expect(result).to eq("orders" => ["main", nil], "orders.dlq" => ["error", "orders"])
    end

    it "keeps it as the main queue next to its retry queue" do
      queues = [
        queue("orders", {"x-message-ttl" => 60_000, "x-dead-letter-exchange" => "", "x-dead-letter-routing-key" => "orders.retry"}),
        queue("orders.retry", {"x-message-ttl" => 5000, "x-dead-letter-exchange" => "", "x-dead-letter-routing-key" => "orders"})
      ]
      expected = {"orders" => ["main", nil], "orders.retry" => ["retry", "orders"]}

      expect(roles_for(queues)).to eq(expected)
      expect(roles_for(queues, heartbeats: [], bindings: [{source: "orders", destination: "orders", destination_type: "queue", routing_key: "#"}])).to eq(expected)
    end
  end

  context "when only the consumers' exchanges are shown" do
    it "keeps their exchanges, delayed fronts and the queues hanging off them" do
      result = topology.to_h

      expect(result[:exchanges].map { |e| e[:name] }).to eq(%w[orders orders.delayed])
      expect(result[:bindings].map { |b| b[:source] }.uniq).to eq(%w[orders orders.delayed])
      expect(result[:queues].map { |q| q[:name] }).not_to include("invoices.main", "invoices.dead")
      expect(result[:queues].map { |q| q[:name] }).to include("orders.fulfillment.retry", "orders.delayed.30000")
    end
  end

  context "when the management API fails" do
    before { allow(management_api).to receive(:queues).and_raise(Lepus::Web::ManagementAPI::ConnectionError, "refused") }

    it "reports it and draws what the consumers declared" do
      result = topology.to_h

      expect(result).to include(management: false, management_error: "The RabbitMQ management API could not be reached")
      expect(result[:exchanges].map { |e| e[:name] }).to eq(["orders"])
      expect(result[:bindings]).to eq([{source: "orders", destination: "orders.fulfillment", destination_type: "queue", routing_keys: []}])
      expect(result[:queues].map { |q| [q[:name], q[:role], q[:ready]] }).to eq([["orders.fulfillment", "main", 0]])
      expect(result[:consumers].map { |c| c[:class_name] }).to eq(["FulfillmentConsumer"])
    end
  end

  context "without a management API" do
    it "says it is not configured" do
      expect(described_class.new(management_api: nil, aggregator: aggregator).to_h).to include(management: false, management_error: /not configured/)
    end
  end
end
