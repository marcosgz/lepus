# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Web::Aggregator do
  subject(:aggregator) { described_class.new(stale_threshold: 60) }

  after do
    aggregator.stop if aggregator.running?
  end

  describe "#initialize" do
    it "uses config stale_threshold by default" do
      agg = described_class.new
      expect(agg.stale_threshold).to eq(Lepus.config.process_alive_threshold)
    end

    it "allows custom stale_threshold" do
      agg = described_class.new(stale_threshold: 120)
      expect(agg.stale_threshold).to eq(120)
    end
  end

  describe "#running?" do
    it "returns false initially" do
      expect(aggregator.running?).to be(false)
    end
  end

  describe "#count" do
    it "returns 0 initially" do
      expect(aggregator.count).to eq(0)
    end
  end

  describe "#clear" do
    it "clears all processes" do
      aggregator.send(:process_heartbeat, {
        process: {id: "test-1", name: "worker1"}
      })

      aggregator.clear

      expect(aggregator.count).to eq(0)
    end
  end

  describe "#all_processes" do
    it "returns empty array initially" do
      expect(aggregator.all_processes).to eq([])
    end

    it "returns processes after heartbeat" do
      aggregator.send(:process_heartbeat, {
        process: {id: "test-1", name: "worker1"},
        metrics: {rss_memory: 100}
      })

      processes = aggregator.all_processes
      expect(processes.size).to eq(1)
      expect(processes.first[:id]).to eq("test-1")
    end
  end

  describe "#find" do
    it "returns nil for unknown id" do
      expect(aggregator.find("unknown")).to be_nil
    end

    it "returns process by id" do
      aggregator.send(:process_heartbeat, {
        process: {id: "test-1", name: "worker1"}
      })

      process = aggregator.find("test-1")
      expect(process[:name]).to eq("worker1")
    end
  end

  describe "message handling" do
    describe "heartbeat messages" do
      it "stores process from heartbeat" do
        aggregator.send(:handle_message, JSON.generate({
          type: "heartbeat",
          process: {id: "test-1", name: "worker1"},
          metrics: {rss_memory: 100}
        }))

        expect(aggregator.count).to eq(1)
      end

      it "updates existing process" do
        aggregator.send(:handle_message, JSON.generate({
          type: "heartbeat",
          process: {id: "test-1", name: "worker1"}
        }))

        aggregator.send(:handle_message, JSON.generate({
          type: "heartbeat",
          process: {id: "test-1", name: "worker1-updated"}
        }))

        expect(aggregator.count).to eq(1)
        expect(aggregator.find("test-1")[:name]).to eq("worker1-updated")
      end
    end

    describe "deregister messages" do
      it "removes process on deregister" do
        aggregator.send(:process_heartbeat, {
          process: {id: "test-1", name: "worker1"}
        })

        aggregator.send(:handle_message, JSON.generate({
          type: "deregister",
          process_id: "test-1"
        }))

        expect(aggregator.count).to eq(0)
      end
    end
  end

  describe "stale process pruning" do
    it "prunes stale processes" do
      # Manually inject a stale entry
      aggregator.instance_variable_get(:@processes)["stale-1"] = {
        process: {id: "stale-1", name: "stale"},
        received_at: Time.now - 120 # older than stale_threshold
      }

      aggregator.instance_variable_get(:@processes)["fresh-1"] = {
        process: {id: "fresh-1", name: "fresh"},
        received_at: Time.now
      }

      # Trigger pruning via all_processes
      processes = aggregator.all_processes

      expect(processes.size).to eq(1)
      expect(processes.first[:id]).to eq("fresh-1")
    end
  end
end
