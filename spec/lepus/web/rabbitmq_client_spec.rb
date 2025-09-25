# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe Lepus::Web::RabbitMQClient do
  let(:configuration) { double("Configuration", rabbitmq_url: "amqp://guest:guest@localhost:5672") }
  let(:client) { described_class.new(configuration) }

  before do
    WebMock.enable!
  end

  after do
    WebMock.disable!
  end

  describe "#initialize" do
    it "creates a client with default configuration" do
      expect(described_class.new).to be_a(described_class)
    end

    it "creates a client with custom configuration" do
      expect(described_class.new(configuration)).to be_a(described_class)
    end
  end

  describe "#overview" do
    let(:overview_data) do
      {
        "management_version" => "3.12.0",
        "rates_mode" => "basic",
        "rabbitmq_version" => "3.12.0",
        "cluster_name" => "rabbit@localhost",
        "erlang_version" => "26.0.2",
        "erlang_full_version" => "Erlang/OTP 26 [erts-14.0.2] [source] [64-bit] [smp:8:8] [ds:8:8:10] [async-threads:1] [jit]",
        "exchange_types" => [
          {"name" => "direct", "description" => "AMQP direct exchange, as per the AMQP specification"},
          {"name" => "fanout", "description" => "AMQP fanout exchange, as per the AMQP specification"},
          {"name" => "headers", "description" => "AMQP headers exchange, as per the AMQP specification"},
          {"name" => "topic", "description" => "AMQP topic exchange, as per the AMQP specification"}
        ],
        "product_version" => "3.12.0",
        "product_name" => "RabbitMQ"
      }
    end

    before do
      stub_request(:get, "http://localhost:15672/api/overview")
        .with(headers: {"Authorization" => "Basic Z3Vlc3Q6Z3Vlc3Q="})
        .to_return(
          status: 200,
          body: overview_data.to_json,
          headers: {"Content-Type" => "application/json"}
        )
    end

    it "returns overview data" do
      result = client.overview
      expect(result).to eq(overview_data)
    end
  end

  describe "#nodes" do
    let(:nodes_data) do
      [
        {
          "name" => "rabbit@localhost",
          "type" => "disc",
          "running" => true,
          "os_pid" => 12345,
          "fd_used" => 10,
          "fd_total" => 65536,
          "sockets_used" => 2,
          "sockets_total" => 32768,
          "mem_used" => 50000000,
          "mem_limit" => 1000000000,
          "mem_alarm" => false,
          "disk_free" => 1000000000,
          "disk_free_limit" => 100000000,
          "disk_free_alarm" => false,
          "proc_used" => 100,
          "proc_total" => 1048576,
          "rates_mode" => "basic",
          "uptime" => 3600,
          "run_queue" => 0,
          "processors" => 8,
          "exchange_types" => [],
          "auth_mechanisms" => [],
          "applications" => [],
          "contexts" => [],
          "log_file" => "/var/log/rabbitmq/rabbit@localhost.log",
          "sasl_log_file" => "/var/log/rabbitmq/rabbit@localhost-sasl.log",
          "db_dir" => "/var/lib/rabbitmq/mnesia/rabbit@localhost",
          "config_files" => [],
          "net_ticktime" => 60,
          "enabled_plugins" => [],
          "mem_calculation_strategy" => "rss"
        }
      ]
    end

    before do
      stub_request(:get, "http://localhost:15672/api/nodes")
        .with(headers: {"Authorization" => "Basic Z3Vlc3Q6Z3Vlc3Q="})
        .to_return(
          status: 200,
          body: nodes_data.to_json,
          headers: {"Content-Type" => "application/json"}
        )
    end

    it "returns nodes data" do
      result = client.nodes
      expect(result).to eq(nodes_data)
    end
  end

  describe "#queues" do
    let(:queues_data) do
      [
        {
          "name" => "test.queue",
          "vhost" => "/",
          "type" => "classic",
          "durable" => true,
          "auto_delete" => false,
          "exclusive" => false,
          "arguments" => {},
          "node" => "rabbit@localhost",
          "message_stats" => {
            "publish" => 100,
            "publish_details" => {"rate" => 0.0},
            "deliver" => 95,
            "deliver_details" => {"rate" => 0.0},
            "deliver_get" => 95,
            "deliver_get_details" => {"rate" => 0.0},
            "redeliver" => 5,
            "redeliver_details" => {"rate" => 0.0},
            "ack" => 90,
            "ack_details" => {"rate" => 0.0}
          },
          "messages" => 10,
          "messages_details" => {"rate" => 0.0},
          "messages_ready" => 8,
          "messages_ready_details" => {"rate" => 0.0},
          "messages_unacknowledged" => 2,
          "messages_unacknowledged_details" => {"rate" => 0.0},
          "consumers" => 1,
          "consumer_details" => {"rate" => 0.0},
          "consumer_utilisation" => 0.8,
          "memory" => 1024,
          "state" => "running"
        }
      ]
    end

    before do
      stub_request(:get, "http://localhost:15672/api/queues")
        .with(headers: {"Authorization" => "Basic Z3Vlc3Q6Z3Vlc3Q="})
        .to_return(
          status: 200,
          body: queues_data.to_json,
          headers: {"Content-Type" => "application/json"}
        )
    end

    it "returns queues data" do
      result = client.queues
      expect(result).to eq(queues_data)
    end
  end

  describe "#connections" do
    let(:connections_data) do
      [
        {
          "name" => "127.0.0.1:5672 -> 127.0.0.1:12345",
          "vhost" => "/",
          "user" => "guest",
          "node" => "rabbit@localhost",
          "channels" => 1,
          "state" => "running",
          "garbage_collection" => {
            "minor_gcs" => 10,
            "fullsweep_after" => 65535,
            "min_heap_size" => 233,
            "min_bin_vheap_size" => 46422,
            "max_heap_size" => 0
          },
          "reductions" => {
            "rate" => 0.0
          },
          "channel_max" => 2047,
          "frame_max" => 131072,
          "timeout" => 60,
          "protocol" => "AMQP 0-9-1",
          "auth_mechanism" => "PLAIN",
          "ssl" => false,
          "ssl_protocol" => nil,
          "ssl_key_exchange" => nil,
          "ssl_cipher" => nil,
          "ssl_hash" => nil,
          "peer_cert_issuer" => nil,
          "peer_cert_subject" => nil,
          "peer_cert_validity" => nil,
          "exchange" => "",
          "routing_key" => "",
          "queue" => "",
          "prefetch_count" => 0,
          "global_prefetch_count" => 0,
          "reconnect_delay" => 0,
          "client_properties" => {
            "product" => "Bunny",
            "version" => "2.19.0",
            "platform" => "Ruby",
            "capabilities" => {
              "publisher_confirms" => true,
              "exchange_exchange_bindings" => true,
              "basic.nack" => true,
              "consumer_cancel_notify" => true,
              "connection.blocked" => true,
              "authentication_failure_close" => true
            },
            "information" => "http://rubybunny.info",
            "copyright" => "Copyright (c) 2007-2018 GoPivotal, Inc.",
            "connection_name" => "Bunny 2.19.0"
          }
        }
      ]
    end

    before do
      stub_request(:get, "http://localhost:15672/api/connections")
        .with(headers: {"Authorization" => "Basic Z3Vlc3Q6Z3Vlc3Q="})
        .to_return(
          status: 200,
          body: connections_data.to_json,
          headers: {"Content-Type" => "application/json"}
        )
    end

    it "returns connections data" do
      result = client.connections
      expect(result).to eq(connections_data)
    end
  end

  describe "error handling" do
    context "when authentication fails" do
      before do
        stub_request(:get, "http://localhost:15672/api/overview")
          .with(headers: {"Authorization" => "Basic Z3Vlc3Q6Z3Vlc3Q="})
          .to_return(status: 401)
      end

      it "raises AuthenticationError" do
        expect { client.overview }.to raise_error(Lepus::Web::RabbitMQClient::AuthenticationError)
      end
    end

    context "when resource is not found" do
      before do
        stub_request(:get, "http://localhost:15672/api/overview")
          .with(headers: {"Authorization" => "Basic Z3Vlc3Q6Z3Vlc3Q="})
          .to_return(status: 404)
      end

      it "raises NotFoundError" do
        expect { client.overview }.to raise_error(Lepus::Web::RabbitMQClient::NotFoundError)
      end
    end

    context "when server error occurs" do
      before do
        stub_request(:get, "http://localhost:15672/api/overview")
          .with(headers: {"Authorization" => "Basic Z3Vlc3Q6Z3Vlc3Q="})
          .to_return(status: 500)
      end

      it "raises Error" do
        expect { client.overview }.to raise_error(Lepus::Web::RabbitMQClient::Error)
      end
    end

    context "when connection fails" do
      before do
        stub_request(:get, "http://localhost:15672/api/overview")
          .with(headers: {"Authorization" => "Basic Z3Vlc3Q6Z3Vlc3Q="})
          .to_raise(Errno::ECONNREFUSED.new)
      end

      it "raises ConnectionError" do
        expect { client.overview }.to raise_error(Lepus::Web::RabbitMQClient::ConnectionError)
      end
    end
  end

  describe "URL parsing" do
    context "with AMQP URL" do
      let(:configuration) { double("Configuration", rabbitmq_url: "amqp://guest:guest@localhost:5672") }

      it "converts to HTTP management URL" do
        expect(client.send(:rabbitmq_management_url)).to eq("http://localhost:15672")
      end
    end

    context "with AMQPS URL" do
      let(:configuration) { double("Configuration", rabbitmq_url: "amqps://guest:guest@localhost:5671") }

      it "converts to HTTPS management URL" do
        expect(client.send(:rabbitmq_management_url)).to eq("https://localhost:15671")
      end
    end

    context "with custom credentials" do
      let(:configuration) { double("Configuration", rabbitmq_url: "amqp://admin:secret@rabbitmq.example.com:5672") }

      it "extracts username and password" do
        expect(client.send(:username)).to eq("admin")
        expect(client.send(:password)).to eq("secret")
      end
    end
  end
end
