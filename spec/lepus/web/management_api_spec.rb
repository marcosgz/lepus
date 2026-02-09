# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe Lepus::Web::ManagementAPI do
  subject(:api) { described_class.new(base_url: "http://localhost:15672") }

  describe "#initialize" do
    it "uses provided values" do
      api = described_class.new(
        base_url: "http://custom:15673",
        username: "admin",
        password: "secret"
      )

      expect(api.base_url).to eq("http://custom:15673")
      expect(api.username).to eq("admin")
      expect(api.password).to eq("secret")
    end

    it "derives management URL from rabbitmq_url" do
      allow(Lepus.config).to receive(:rabbitmq_url).and_return("amqp://rabbit-host:5672")

      api = described_class.new
      expect(api.base_url).to eq("http://rabbit-host:15672")
    end
  end

  describe "#queues" do
    it "fetches and normalizes queue data" do
      stub_request(:get, "http://localhost:15672/api/queues/%2F")
        .with(headers: {"Accept" => "application/json"})
        .to_return(
          status: 200,
          body: JSON.generate([
            {
              "name" => "orders.main",
              "type" => "classic",
              "messages" => 42,
              "messages_ready" => 40,
              "messages_unacknowledged" => 2,
              "consumers" => 3,
              "memory" => 8_388_608,
              "message_stats" => {
                "deliver_get" => 1000,
                "deliver_get_details" => {"rate" => 10.5},
                "ack" => 998,
                "ack_details" => {"rate" => 10.0}
              }
            }
          ]),
          headers: {"Content-Type" => "application/json"}
        )

      queues = api.queues

      expect(queues.size).to eq(1)
      expect(queues.first[:name]).to eq("orders.main")
      expect(queues.first[:type]).to eq("classic")
      expect(queues.first[:messages]).to eq(42)
      expect(queues.first[:consumers]).to eq(3)
      expect(queues.first[:message_stats][:deliver_get]).to eq(1000)
      expect(queues.first[:message_stats][:deliver_get_rate]).to eq(10.5)
    end

    it "returns empty array on empty response" do
      stub_request(:get, "http://localhost:15672/api/queues/%2F")
        .to_return(status: 200, body: "[]")

      expect(api.queues).to eq([])
    end

    it "raises ConnectionError on connection failure" do
      stub_request(:get, "http://localhost:15672/api/queues/%2F")
        .to_raise(Errno::ECONNREFUSED)

      expect { api.queues }.to raise_error(described_class::ConnectionError)
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, "http://localhost:15672/api/queues/%2F")
        .to_return(status: 401, body: "Unauthorized")

      expect { api.queues }.to raise_error(described_class::AuthenticationError)
    end
  end

  describe "#connections" do
    it "fetches and normalizes connection data" do
      stub_request(:get, "http://localhost:15672/api/connections")
        .to_return(
          status: 200,
          body: JSON.generate([
            {
              "name" => "127.0.0.1:54321 -> 127.0.0.1:5672",
              "state" => "running",
              "user" => "guest",
              "vhost" => "/",
              "channels" => 2,
              "connected_at" => 1707465600000,
              "client_properties" => {
                "connection_name" => "Lepus (0.0.1)"
              }
            }
          ])
        )

      connections = api.connections

      expect(connections.size).to eq(1)
      expect(connections.first[:state]).to eq("running")
      expect(connections.first[:user]).to eq("guest")
      expect(connections.first[:channels]).to eq(2)
      expect(connections.first[:client_properties][:connection_name]).to eq("Lepus (0.0.1)")
    end

    it "returns empty array on empty response" do
      stub_request(:get, "http://localhost:15672/api/connections")
        .to_return(status: 200, body: "[]")

      expect(api.connections).to eq([])
    end
  end

  describe "#queue" do
    it "fetches a specific queue" do
      stub_request(:get, "http://localhost:15672/api/queues/%2F/orders.main")
        .to_return(
          status: 200,
          body: JSON.generate({
            "name" => "orders.main",
            "messages" => 10
          })
        )

      queue = api.queue("orders.main")

      expect(queue[:name]).to eq("orders.main")
      expect(queue[:messages]).to eq(10)
    end

    it "returns nil for non-existent queue" do
      stub_request(:get, "http://localhost:15672/api/queues/%2F/missing")
        .to_return(status: 404, body: "Not Found")

      expect(api.queue("missing")).to be_nil
    end
  end
end
