# frozen_string_literal: true

require "spec_helper"
require "lepus/web"
require "rack/test"

RSpec.describe Lepus::Web::API do
  include Rack::Test::Methods

  let(:aggregator) { instance_double(Lepus::Web::Aggregator) }
  let(:management_api) { instance_double(Lepus::Web::ManagementAPI) }
  let(:api) { described_class.new(aggregator: aggregator, management_api: management_api) }

  describe "/health" do
    it "returns health status" do
      env = Rack::MockRequest.env_for("/health")
      status, headers, body = api.call(env)

      expect(status).to eq(200)
      expect(headers["content-type"]).to eq("application/json")
      expect(JSON.parse(body.first)).to eq({"status" => "ok"})
    end

    it "handles query parameters correctly" do
      env = Rack::MockRequest.env_for("/health?param=value")
      status, _, body = api.call(env)

      expect(status).to eq(200)
      expect(JSON.parse(body.first)).to eq({"status" => "ok"})
    end
  end

  describe "/processes" do
    context "with running aggregator" do
      let(:process_data) do
        [
          {id: "uuid-1", name: "supervisor", kind: "supervisor", application: "MyApp", rss_memory: 100_000, consumers: []},
          {id: "uuid-2", name: "worker", kind: "worker", supervisor_id: "uuid-1", rss_memory: 80_000, consumers: [
            {class_name: "OrdersConsumer", exchange: "orders", queue: "orders.main", processed: 100, rejected: 2, errored: 1}
          ]}
        ]
      end

      before do
        allow(aggregator).to receive_messages(running?: true, all_processes: process_data)
      end

      it "returns real process data from aggregator" do
        env = Rack::MockRequest.env_for("/processes")
        status, headers, body = api.call(env)

        expect(status).to eq(200)
        expect(headers["content-type"]).to eq("application/json")

        response_data = JSON.parse(body.first)
        expect(response_data).to be_an(Array)
        expect(response_data.length).to eq(2)
        expect(response_data.first["name"]).to eq("supervisor")
      end
    end

    context "without running aggregator" do
      before do
        allow(aggregator).to receive(:running?).and_return(false)
      end

      it "returns empty array" do
        env = Rack::MockRequest.env_for("/processes")
        status, _, body = api.call(env)

        expect(status).to eq(200)
        expect(JSON.parse(body.first)).to eq([])
      end
    end

    context "without aggregator" do
      let(:api) { described_class.new(aggregator: nil, management_api: management_api) }

      before do
        allow(Lepus::Web).to receive(:aggregator).and_return(nil)
      end

      it "returns empty array" do
        env = Rack::MockRequest.env_for("/processes")
        status, _, body = api.call(env)

        expect(status).to eq(200)
        expect(JSON.parse(body.first)).to eq([])
      end
    end
  end

  describe "/queues" do
    let(:queue_data) do
      [
        {name: "orders.main", type: "classic", messages: 42, messages_ready: 40, messages_unacknowledged: 2,
         consumers: 3, memory: 8_388_608, message_stats: {}}
      ]
    end

    context "with management API" do
      before do
        allow(management_api).to receive(:queues).and_return(queue_data)
        allow(aggregator).to receive(:running?).and_return(false)
      end

      it "returns real queue data" do
        env = Rack::MockRequest.env_for("/queues")
        status, _, body = api.call(env)

        expect(status).to eq(200)
        response_data = JSON.parse(body.first)
        expect(response_data.length).to eq(1)
        expect(response_data.first["name"]).to eq("orders.main")
      end
    end

    context "with queue-to-app annotation" do
      let(:process_data) do
        [
          {id: "uuid-1", application: "OrdersApp", consumers: [
            {class_name: "OrdersConsumer", exchange: "orders", queue: "orders.main"}
          ]}
        ]
      end

      before do
        allow(management_api).to receive(:queues).and_return(queue_data)
        allow(aggregator).to receive_messages(running?: true, all_processes: process_data)
      end

      it "annotates queues with application name" do
        env = Rack::MockRequest.env_for("/queues")
        _, _, body = api.call(env)

        response_data = JSON.parse(body.first)
        expect(response_data.first["application"]).to eq("OrdersApp")
      end
    end

    context "without management API" do
      let(:api) { described_class.new(aggregator: aggregator, management_api: nil) }

      before do
        allow(Lepus::Web).to receive(:management_api).and_return(nil)
      end

      it "returns empty array" do
        env = Rack::MockRequest.env_for("/queues")
        status, _, body = api.call(env)

        expect(status).to eq(200)
        expect(JSON.parse(body.first)).to eq([])
      end
    end

    context "when management API raises" do
      before do
        allow(management_api).to receive(:queues).and_raise(Lepus::Web::ManagementAPI::ConnectionError, "refused")
        allow(Lepus.logger).to receive(:warn)
      end

      it "returns empty array and logs warning" do
        env = Rack::MockRequest.env_for("/queues")
        status, _, body = api.call(env)

        expect(status).to eq(200)
        expect(JSON.parse(body.first)).to eq([])
        expect(Lepus.logger).to have_received(:warn).with(/Failed to fetch queues/)
      end
    end
  end

  describe "/connections" do
    let(:connection_data) do
      [{name: "conn-1", state: "running", user: "guest", vhost: "/", channels: 2}]
    end

    context "with management API" do
      before do
        allow(management_api).to receive(:connections).and_return(connection_data)
      end

      it "returns real connection data" do
        env = Rack::MockRequest.env_for("/connections")
        status, _, body = api.call(env)

        expect(status).to eq(200)
        response_data = JSON.parse(body.first)
        expect(response_data.length).to eq(1)
        expect(response_data.first["state"]).to eq("running")
      end
    end

    context "without management API" do
      let(:api) { described_class.new(aggregator: aggregator, management_api: nil) }

      before do
        allow(Lepus::Web).to receive(:management_api).and_return(nil)
      end

      it "returns empty array" do
        env = Rack::MockRequest.env_for("/connections")
        status, _, body = api.call(env)

        expect(status).to eq(200)
        expect(JSON.parse(body.first)).to eq([])
      end
    end
  end

  describe "/exchanges" do
    let(:exchange_data) do
      [
        {name: "orders", type: "topic", durable: true, auto_delete: false, message_stats: {}},
        {name: "invoices", type: "topic", durable: true, auto_delete: false, message_stats: {}}
      ]
    end

    context "with web_show_all_exchanges = true" do
      before do
        allow(Lepus.config).to receive(:web_show_all_exchanges).and_return(true)
        allow(management_api).to receive(:exchanges).and_return(exchange_data)
        allow(aggregator).to receive(:running?).and_return(false)
      end

      it "returns all exchanges" do
        env = Rack::MockRequest.env_for("/exchanges")
        status, _, body = api.call(env)

        expect(status).to eq(200)
        response_data = JSON.parse(body.first)
        expect(response_data.length).to eq(2)
      end
    end

    context "with web_show_all_exchanges = false (default)" do
      let(:process_data) do
        [
          {id: "uuid-1", application: "MyApp", consumers: [
            {class_name: "OrdersConsumer", exchange: "orders", queue: "orders.main"}
          ]}
        ]
      end

      before do
        allow(Lepus.config).to receive(:web_show_all_exchanges).and_return(false)
        allow(management_api).to receive(:exchanges).and_return(exchange_data)
        allow(aggregator).to receive_messages(running?: true, all_processes: process_data)
      end

      it "returns only lepus-managed exchanges" do
        env = Rack::MockRequest.env_for("/exchanges")
        status, _, body = api.call(env)

        expect(status).to eq(200)
        response_data = JSON.parse(body.first)
        expect(response_data.length).to eq(1)
        expect(response_data.first["name"]).to eq("orders")
      end
    end

    context "without management API" do
      let(:api) { described_class.new(aggregator: aggregator, management_api: nil) }

      before do
        allow(Lepus::Web).to receive(:management_api).and_return(nil)
      end

      it "returns empty array" do
        env = Rack::MockRequest.env_for("/exchanges")
        status, _, body = api.call(env)

        expect(status).to eq(200)
        expect(JSON.parse(body.first)).to eq([])
      end
    end
  end

  describe "/topology" do
    it "returns the assembled topology" do
      allow(aggregator).to receive_messages(running?: true, all_processes: [])
      allow(management_api).to receive_messages(queues: [], exchanges: [], bindings: [], consumers: [])

      status, headers, body = api.call(Rack::MockRequest.env_for("/topology"))
      payload = JSON.parse(body.first)

      expect(status).to eq(200)
      expect(headers["content-type"]).to eq("application/json")
      expect(payload).to include("management" => true, "exchanges" => [], "bindings" => [], "queues" => [], "consumers" => [])
      expect(payload["generated_at"]).to be_a(String)
    end

    it "includes the arguments that send a queue's messages on" do
      allow(aggregator).to receive_messages(running?: true, all_processes: [])
      allow(management_api).to receive_messages(
        queues: [
          {name: "orders", arguments: {}, message_stats: {}},
          {name: "orders.retry", arguments: {"x-message-ttl" => 30_000, "x-dead-letter-exchange" => "", "x-dead-letter-routing-key" => "orders", "x-expires" => 3_600_000}, message_stats: {}}
        ],
        exchanges: [], bindings: [], consumers: []
      )

      _, _, body = api.call(Rack::MockRequest.env_for("/topology"))
      retry_queue = JSON.parse(body.first)["queues"].find { |q| q["name"] == "orders.retry" }

      expect(retry_queue).to include("role" => "retry", "parent" => "orders", "ttl" => 30_000, "dead_letter_exchange" => "",
        "dead_letter_routing_key" => "orders", "expires" => 3_600_000)
    end

    it "flags an unreachable management API" do
      allow(aggregator).to receive(:running?).and_return(false)
      allow(management_api).to receive(:queues).and_raise(Lepus::Web::ManagementAPI::ConnectionError, "refused")

      _, _, body = api.call(Rack::MockRequest.env_for("/topology"))

      expect(JSON.parse(body.first)).to include("management" => false, "management_error" => "The RabbitMQ management API could not be reached")
    end

    it "keeps host names and response bodies out of the payload" do
      allow(aggregator).to receive(:running?).and_return(false)
      allow(management_api).to receive(:queues).and_raise(SocketError, "Failed to open TCP connection to rabbit-mgmt.internal:15672")

      _, _, body = api.call(Rack::MockRequest.env_for("/topology"))

      expect(body.first).not_to include("rabbit-mgmt.internal", "15672")
    end
  end

  describe "/overview" do
    it "asks for the history of an allowed window" do
      allow(management_api).to receive(:overview).with(age: 3600, increment: 60).and_return(rates: {}, history: [])

      _, _, body = api.call(Rack::MockRequest.env_for("/overview?age=3600"))

      expect(JSON.parse(body.first)).to include("management" => true, "age" => 3600, "history" => [])
    end

    it "falls back to the shortest window" do
      allow(management_api).to receive(:overview).with(age: 600, increment: 10).and_return(history: [])

      _, _, body = api.call(Rack::MockRequest.env_for("/overview?age=99999"))

      expect(JSON.parse(body.first)).to include("age" => 600)
    end

    it "reports a failure without raising" do
      allow(management_api).to receive(:overview).and_raise(Lepus::Web::ManagementAPI::Error, "RabbitMQ Management API error: 500 - <html>stack</html>")

      status, _, body = api.call(Rack::MockRequest.env_for("/overview"))

      expect(status).to eq(200)
      expect(JSON.parse(body.first)).to eq("management" => false, "error" => "The RabbitMQ management API returned an error")
    end

    context "without management API" do
      let(:api) { described_class.new(aggregator: aggregator, management_api: nil) }

      it "says so" do
        _, _, body = api.call(Rack::MockRequest.env_for("/overview"))

        expect(JSON.parse(body.first)).to eq("management" => false)
      end
    end
  end

  describe "/meta" do
    it "returns what the dashboard needs to poll" do
      _, _, body = api.call(Rack::MockRequest.env_for("/meta"))

      expect(JSON.parse(body.first)).to include(
        "version" => Lepus::VERSION, "heartbeat_interval" => 60, "alive_threshold" => 300,
        "poll_interval" => 5, "poll_intervals" => [0, 2, 5, 15, 60], "history_ages" => [600, 3600]
      )
    end
  end

  describe "unknown endpoint" do
    it "returns 404 not found" do
      env = Rack::MockRequest.env_for("/unknown")
      status, headers, body = api.call(env)

      expect(status).to eq(404)
      expect(headers["content-type"]).to eq("application/json")
      expect(JSON.parse(body.first)).to eq({"error" => "not_found"})
    end
  end
end
