# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Consumers::Config do
  let(:config) { described_class.new(options) }
  let(:options) { {} }

  describe "#initialize" do
    let(:options) { {} }

    it "sets the options" do
      expect(config.options).to eq({})
    end

    it "sets the default process options" do
      expect(config.instance_variable_get(:@process_opts)).to eq({
        name: "default",
        threads: 1
      })
    end

    it "sets the default exchange options" do
      expect(config.instance_variable_get(:@exchange_opts)).to eq({
        name: nil,
        type: :topic,
        durable: true
      })
    end

    it "sets the default queue options" do
      expect(config.instance_variable_get(:@queue_opts)).to eq({
        name: nil,
        durable: true
      })
    end

    it "sets the default bind options" do
      expect(config.instance_variable_get(:@bind_opts)).to eq({})
    end

    context "when options are provided" do
      let(:options) do
        {
          process: {name: "custom", threads: 5},
          exchange: {name: "exchange-name", type: :direct, auto_delete: true},
          queue: {name: "queue-name", auto_delete: true},
          retry_queue: {delay: 10000},
          error_queue: true,
          bind: {routing_key: "routing-key"},
          custom_option: "value"
        }
      end

      it "sets the custom options" do
        expect(config.options).to eq({custom_option: "value"})
      end

      it "sets the custom process options" do
        expect(config.instance_variable_get(:@process_opts)).to eq({
          name: "custom",
          threads: 5
        })
      end

      it "sets the custom exchange options" do
        expect(config.instance_variable_get(:@exchange_opts)).to eq({
          name: "exchange-name",
          type: :direct,
          durable: true,
          auto_delete: true
        })
      end

      it "sets the custom queue options" do
        expect(config.instance_variable_get(:@queue_opts)).to eq({
          name: "queue-name",
          durable: true,
          auto_delete: true
        })
      end

      it "sets the custom retry queue options" do
        expect(config.instance_variable_get(:@retry_queue_opts)).to eq({
          name: nil,
          durable: true,
          delay: 10000,
          arguments: {}
        })
      end

      it "sets the custom error queue options" do
        expect(config.instance_variable_get(:@error_queue_opts)).to eq({
          name: nil,
          durable: true
        })
      end

      it "sets the custom bind options" do
        expect(config.instance_variable_get(:@bind_opts)).to eq({routing_key: "routing-key"})
      end
    end
  end

  describe "#process_name" do
    it "returns the default process name" do
      expect(config.process_name).to eq("default")
    end

    context "when process name is provided" do
      let(:options) { {process: {name: "custom"}} }

      it "returns the custom process name" do
        expect(config.process_name).to eq("custom")
      end
    end
  end

  describe "#exchange_args" do
    it "raises InvalidConsumerConfigError when exchange name is not given" do
      expect { config.exchange_args }.to raise_error(Lepus::InvalidConsumerConfigError)
    end

    context "when exchange is set as a string" do
      let(:options) { {exchange: "exchange-name"} }

      it "returns the exchange args" do
        expect(config.exchange_args).to eq(["exchange-name", {type: :topic, durable: true}])
      end
    end

    context "when exchange is set as a hash" do
      let(:options) { {exchange: {name: "exchange-name", type: :direct, auto_delete: false}} }

      it "returns the exchange args" do
        expect(config.exchange_args).to eq(["exchange-name", {type: :direct, durable: true, auto_delete: false}])
      end
    end
  end

  describe "#consumer_queue_args" do
    it "raises InvalidConsumerConfigError when queue name is not given" do
      expect { config.consumer_queue_args }.to raise_error(Lepus::InvalidConsumerConfigError)
    end

    context "when queue is set as a string" do
      let(:options) { {queue: "queue-name"} }

      it "returns the queue args" do
        expect(config.consumer_queue_args).to eq(["queue-name", {durable: true}])
      end
    end

    context "when queue is set as a hash" do
      let(:options) { {queue: {name: "queue-name", auto_delete: false}} }

      it "returns the queue args" do
        expect(config.consumer_queue_args).to eq(["queue-name", {durable: true, auto_delete: false}])
      end
    end
  end

  describe "#retry_queue_args" do
    it "returns nil when retry_queue is not set" do
      expect(config.retry_queue_args).to be_nil
    end

    context "when the retry_queue is set false" do
      let(:options) { {retry_queue: false} }

      it "returns nil" do
        expect(config.retry_queue_args).to be_nil
      end
    end

    context "when queue is set and the retry_queue is set as true" do
      let(:options) { {queue: "queue-name", retry_queue: true} }

      it "returns the retry queue args" do
        expect(config.retry_queue_args).to eq([
          "queue-name.retry", {
            durable: true,
            arguments: {
              "x-message-ttl" => 5000,
              "x-dead-letter-exchange" => "",
              "x-dead-letter-routing-key" => "queue-name"
            }
          }
        ])
      end
    end

    context "when queue is set and the retry_queue is set as a hash" do
      let(:options) { {queue: "queue-name", retry_queue: {delay: 10000}} }

      it "returns the retry queue args" do
        expect(config.retry_queue_args).to eq([
          "queue-name.retry", {
            durable: true,
            arguments: {
              "x-message-ttl" => 10000,
              "x-dead-letter-exchange" => "",
              "x-dead-letter-routing-key" => "queue-name"
            }
          }
        ])
      end
    end

    context "when queue is set and the retry_queue is set as a hash with name" do
      let(:options) { {queue: "queue-name", retry_queue: {name: "retry-queue"}} }

      it "returns the retry queue args" do
        expect(config.retry_queue_args).to eq([
          "retry-queue", {
            durable: true,
            arguments: {
              "x-message-ttl" => 5000,
              "x-dead-letter-exchange" => "",
              "x-dead-letter-routing-key" => "queue-name"
            }
          }
        ])
      end
    end
  end

  describe "#error_queue_args" do
    it "returns nil when error_queue is not set" do
      expect(config.error_queue_args).to be_nil
    end

    context "when the error_queue is set false" do
      let(:options) { {error_queue: false} }

      it "returns nil" do
        expect(config.error_queue_args).to be_nil
      end
    end

    context "when queue is set and the error_queue is set as true" do
      let(:options) { {queue: "queue-name", error_queue: true} }

      it "returns the error queue args" do
        expect(config.error_queue_args).to eq([
          "queue-name.error", {
            durable: true
          }
        ])
      end
    end

    context "when queue is set and the error_queue is set as a hash" do
      let(:options) { {queue: "queue-name", error_queue: {auto_delete: true}} }

      it "returns the error queue args" do
        expect(config.error_queue_args).to eq([
          "queue-name.error", {
            durable: true,
            auto_delete: true
          }
        ])
      end
    end

    context "when queue is set and the error_queue is set as a hash with name" do
      let(:options) { {queue: "queue-name", error_queue: {name: "error-queue"}} }

      it "returns the error queue args" do
        expect(config.error_queue_args).to eq([
          "error-queue", {
            durable: true
          }
        ])
      end
    end
  end

  describe "#binds_args" do
    it "returns an array with an empty hash" do
      expect(config.binds_args).to eq([{}])
    end

    context "when binds is set with a single routing key" do
      let(:options) { {bind: {routing_key: "routing-key"}} }

      it "returns the binds args" do
        expect(config.binds_args).to eq([{routing_key: "routing-key"}])
      end
    end

    context "when binds is set with multiple routing keys" do
      let(:options) { {bind: {routing_key: %w[routing-key-1 routing-key-2]}} }

      it "returns the binds args" do
        expect(config.binds_args).to eq([
          {routing_key: "routing-key-1"},
          {routing_key: "routing-key-2"}
        ])
      end
    end

    context "when binds is set with a single routing key and arguments" do
      let(:options) { {bind: {routing_key: "routing-key", arguments: {"x-match" => "all"}}} }

      it "returns the binds args" do
        expect(config.binds_args).to eq([
          {routing_key: "routing-key", arguments: {"x-match" => "all"}}
        ])
      end
    end

    context "when the routing_key is set from global options" do
      let(:options) { {routing_key: %w[routing-key]} }

      it "returns the binds args" do
        expect(config.binds_args).to eq([
          {routing_key: "routing-key"}
        ])
      end
    end
  end
end
