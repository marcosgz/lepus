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
