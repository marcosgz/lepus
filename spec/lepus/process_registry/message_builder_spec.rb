# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::ProcessRegistry::MessageBuilder do
  let(:process) do
    Lepus::Process.new(
      id: "test-uuid",
      name: "worker1",
      pid: 12345,
      hostname: "test-host",
      kind: "Worker",
      supervisor_id: "supervisor-uuid",
      last_heartbeat_at: Time.new(2026, 2, 9, 10, 0, 0)
    )
  end

  let(:metrics) do
    {
      rss_memory: 100_000_000,
      connections: 2,
      consumers: [
        {
          class_name: "TestConsumer",
          queue: "test.queue",
          exchange: "test.exchange"
        }
      ]
    }
  end

  describe "#build_heartbeat" do
    context "with metrics" do
      subject(:builder) { described_class.new(process, metrics: metrics) }

      it "builds a heartbeat message" do
        message = builder.build_heartbeat

        expect(message[:type]).to eq("heartbeat")
        expect(message[:version]).to eq("1.0")
        expect(message[:process][:id]).to eq("test-uuid")
        expect(message[:process][:name]).to eq("worker1")
        expect(message[:process][:pid]).to eq(12345)
        expect(message[:process][:hostname]).to eq("test-host")
        expect(message[:process][:kind]).to eq("Worker")
        expect(message[:process][:supervisor_id]).to eq("supervisor-uuid")
        expect(message[:metrics][:rss_memory]).to eq(100_000_000)
        expect(message[:metrics][:connections]).to eq(2)
        expect(message[:metrics][:consumers]).to eq(metrics[:consumers])
      end
    end

    context "without metrics" do
      subject(:builder) { described_class.new(process) }

      it "builds a heartbeat with default metrics" do
        message = builder.build_heartbeat

        expect(message[:metrics][:connections]).to eq(0)
        expect(message[:metrics][:consumers]).to eq([])
      end
    end
  end

  describe "#build_deregister" do
    subject(:builder) { described_class.new(process) }

    it "builds a deregister message" do
      message = builder.build_deregister

      expect(message[:type]).to eq("deregister")
      expect(message[:version]).to eq("1.0")
      expect(message[:process_id]).to eq("test-uuid")
      expect(message[:timestamp]).to be_a(String)
    end
  end

  describe "#to_json" do
    subject(:builder) { described_class.new(process, metrics: metrics) }

    it "returns JSON string" do
      json = builder.to_json

      expect(json).to be_a(String)

      parsed = JSON.parse(json)
      expect(parsed["type"]).to eq("heartbeat")
      expect(parsed["process"]["id"]).to eq("test-uuid")
    end
  end
end
