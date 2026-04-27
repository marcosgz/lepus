# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Consumers::Stats do
  subject(:stats) { described_class.new(consumer_class) }

  let(:consumer_class) do
    Class.new(Lepus::Consumer) do
      configure(
        queue: "test_queue",
        exchange: "test_exchange",
        routing_key: "test.route",
        worker: {threads: 3}
      )

      def self.name
        "TestConsumer"
      end

      def perform(message)
        :ack
      end
    end
  end

  describe "#record_processed" do
    it "increments the processed counter" do
      expect { stats.record_processed }.to change(stats, :processed).from(0).to(1)
    end

    it "is thread-safe" do
      threads = Array.new(10) do
        Thread.new { 100.times { stats.record_processed } }
      end
      threads.each(&:join)

      expect(stats.processed).to eq(1000)
    end
  end

  describe "#record_rejected" do
    it "increments the rejected counter" do
      expect { stats.record_rejected }.to change(stats, :rejected).from(0).to(1)
    end
  end

  describe "#record_errored" do
    it "increments the errored counter" do
      expect { stats.record_errored }.to change(stats, :errored).from(0).to(1)
    end
  end

  describe "#to_h" do
    before do
      3.times { stats.record_processed }
      2.times { stats.record_rejected }
      stats.record_errored
    end

    it "returns a hash with consumer config and stats" do
      result = stats.to_h

      expect(result[:class_name]).to eq("TestConsumer")
      expect(result[:exchange]).to eq("test_exchange")
      expect(result[:queue]).to eq("test_queue")
      expect(result[:route]).to eq("test.route")
      expect(result[:threads]).to eq(3)
      expect(result[:processed]).to eq(3)
      expect(result[:rejected]).to eq(2)
      expect(result[:errored]).to eq(1)
    end
  end

  describe "routing key extraction" do
    context "with a single routing key" do
      it "returns the key as a string" do
        expect(stats.to_h[:route]).to eq("test.route")
      end
    end

    context "with multiple routing keys" do
      let(:consumer_class) do
        Class.new(Lepus::Consumer) do
          configure(
            queue: "multi_queue",
            exchange: "multi_exchange",
            routing_key: ["key.one", "key.two"]
          )

          def self.name
            "MultiRouteConsumer"
          end

          def perform(message)
            :ack
          end
        end
      end

      it "returns an array of keys" do
        expect(stats.to_h[:route]).to eq(["key.one", "key.two"])
      end
    end

    context "with no routing key on a fanout exchange" do
      let(:consumer_class) do
        Class.new(Lepus::Consumer) do
          configure(
            queue: "fanout_queue",
            exchange: {name: "fanout_exchange", type: :fanout}
          )

          def self.name
            "FanoutConsumer"
          end

          def perform(message)
            :ack
          end
        end
      end

      it "returns nil" do
        expect(stats.to_h[:route]).to be_nil
      end
    end
  end
end
