# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe Lepus::Web::API do
  include Rack::Test::Methods

  let(:api) { described_class.new }

  describe "#call" do
    context "when requesting /health" do
      it "returns health status" do
        env = Rack::MockRequest.env_for("/health")
        status, headers, body = api.call(env)

        expect(status).to eq(200)
        expect(headers["Content-Type"]).to eq("application/json")
        expect(JSON.parse(body.first)).to eq({"status" => "ok"})
      end
    end

    context "when requesting /processes" do
      it "returns demo processes data" do
        env = Rack::MockRequest.env_for("/processes")
        status, headers, body = api.call(env)

        expect(status).to eq(200)
        expect(headers["Content-Type"]).to eq("application/json")

        response_data = JSON.parse(body.first)
        expect(response_data).to be_an(Array)
        expect(response_data.length).to eq(5)

        # Check first process (Supervisor A)
        supervisor = response_data.find { |p| p["name"] == "Supervisor A" }
        expect(supervisor).to include(
          "id" => 1,
          "name" => "Supervisor A",
          "pid" => 1001,
          "hostname" => Socket.gethostname,
          "kind" => "supervisor",
          "rss_memory" => 120_000_000
        )
        expect(supervisor["last_heartbeat_at"]).to be_a(Integer)

        # Check first worker (Worker A1)
        worker_a1 = response_data.find { |p| p["name"] == "Worker A1" }
        expect(worker_a1).to include(
          "id" => 2,
          "name" => "Worker A1",
          "pid" => 1002,
          "hostname" => Socket.gethostname,
          "kind" => "worker",
          "supervisor_id" => 1,
          "rss_memory" => 80_000_000
        )
        expect(worker_a1["last_heartbeat_at"]).to be_a(Integer)

        # Check second worker (Worker A2) - should have older heartbeat
        worker_a2 = response_data.find { |p| p["name"] == "Worker A2" }
        expect(worker_a2).to include(
          "id" => 3,
          "name" => "Worker A2",
          "pid" => 1003,
          "hostname" => Socket.gethostname,
          "kind" => "worker",
          "supervisor_id" => 1,
          "rss_memory" => 90_000_000
        )
        expect(worker_a2["last_heartbeat_at"]).to be < worker_a1["last_heartbeat_at"]
      end
    end

    context "when requesting /queues" do
      it "returns demo queues data" do
        env = Rack::MockRequest.env_for("/queues")
        status, headers, body = api.call(env)

        expect(status).to eq(200)
        expect(headers["Content-Type"]).to eq("application/json")

        response_data = JSON.parse(body.first)
        expect(response_data).to be_an(Array)
        expect(response_data.length).to eq(4)

        # Check orders.main queue
        main_queue = response_data.find { |q| q["name"] == "orders.main" }
        expect(main_queue).to include(
          "name" => "orders.main",
          "type" => "classic",
          "messages" => 42,
          "messages_ready" => 21,
          "messages_unacknowledged" => 2,
          "consumers" => 3,
          "memory" => 8 * 1024 * 1024
        )

        # Check orders.retry queue
        retry_queue = response_data.find { |q| q["name"] == "orders.retry" }
        expect(retry_queue).to include(
          "name" => "orders.retry",
          "type" => "classic",
          "messages" => 5,
          "messages_ready" => 5,
          "messages_unacknowledged" => 0,
          "consumers" => 0,
          "memory" => 1 * 1024 * 1024
        )

        # Check orders.error queue
        error_queue = response_data.find { |q| q["name"] == "orders.error" }
        expect(error_queue).to include(
          "name" => "orders.error",
          "type" => "classic",
          "messages" => 2,
          "messages_ready" => 2,
          "messages_unacknowledged" => 0,
          "consumers" => 0,
          "memory" => 512 * 1024
        )

        # Check invoices queue (quorum type)
        invoices_queue = response_data.find { |q| q["name"] == "invoices" }
        expect(invoices_queue).to include(
          "name" => "invoices",
          "type" => "quorum",
          "messages" => 12,
          "messages_ready" => 12,
          "messages_unacknowledged" => 0,
          "consumers" => 2,
          "memory" => 2 * 1024 * 1024
        )
      end
    end

    context "when requesting /connections" do
      it "returns demo connections data" do
        env = Rack::MockRequest.env_for("/connections")
        status, headers, body = api.call(env)

        expect(status).to eq(200)
        expect(headers["Content-Type"]).to eq("application/json")

        response_data = JSON.parse(body.first)
        expect(response_data).to be_an(Array)
        expect(response_data.length).to eq(3)

        expect(response_data[0]).to include("name" => "conn-1")
        expect(response_data[1]).to include("name" => "conn-2")
        expect(response_data[2]).to include("name" => "conn-3")
      end
    end

    context "when requesting an unknown endpoint" do
      it "returns 404 not found" do
        env = Rack::MockRequest.env_for("/unknown")
        status, headers, body = api.call(env)

        expect(status).to eq(404)
        expect(headers["Content-Type"]).to eq("application/json")
        expect(JSON.parse(body.first)).to eq({"error" => "not_found"})
      end
    end

    context "when requesting with query parameters" do
      it "handles query parameters correctly" do
        env = Rack::MockRequest.env_for("/health?param=value")
        status, headers, body = api.call(env)

        expect(status).to eq(200)
        expect(headers["Content-Type"]).to eq("application/json")
        expect(JSON.parse(body.first)).to eq({"status" => "ok"})
      end
    end

    context "when requesting with different HTTP methods" do
      it "handles GET requests" do
        env = Rack::MockRequest.env_for("/health", method: "GET")
        status, _, body = api.call(env)

        expect(status).to eq(200)
        expect(JSON.parse(body.first)).to eq({"status" => "ok"})
      end

      it "handles POST requests" do
        env = Rack::MockRequest.env_for("/health", method: "POST")
        status, _, body = api.call(env)

        expect(status).to eq(200)
        expect(JSON.parse(body.first)).to eq({"status" => "ok"})
      end
    end
  end

  describe "demo data consistency" do
    it "returns consistent process data across multiple calls" do
      env = Rack::MockRequest.env_for("/processes")

      # First call
      status1, _, body1 = api.call(env)
      data1 = JSON.parse(body1.first)

      # Second call
      status2, _, body2 = api.call(env)
      data2 = JSON.parse(body2.first)

      expect(status1).to eq(status2)
      expect(data1.length).to eq(data2.length)

      # Check that structure is consistent
      data1.each_with_index do |process1, index|
        process2 = data2[index]
        expect(process1.keys).to eq(process2.keys)
        expect(process1["id"]).to eq(process2["id"])
        expect(process1["name"]).to eq(process2["name"])
        expect(process1["pid"]).to eq(process2["pid"])
        expect(process1["kind"]).to eq(process2["kind"])
      end
    end

    it "returns consistent queue data across multiple calls" do
      env = Rack::MockRequest.env_for("/queues")

      # First call
      status1, _, body1 = api.call(env)
      data1 = JSON.parse(body1.first)

      # Second call
      status2, _, body2 = api.call(env)
      data2 = JSON.parse(body2.first)

      expect(status1).to eq(status2)
      expect(data1.length).to eq(data2.length)

      # Check that structure is consistent
      data1.each_with_index do |queue1, index|
        queue2 = data2[index]
        expect(queue1.keys).to eq(queue2.keys)
        expect(queue1["name"]).to eq(queue2["name"])
        expect(queue1["type"]).to eq(queue2["type"])
        expect(queue1["messages"]).to eq(queue2["messages"])
      end
    end
  end
end
