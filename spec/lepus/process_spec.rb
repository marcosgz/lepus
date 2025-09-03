# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Process do
  after do
    Lepus::ProcessRegistry.instance.clear
  end

  describe ".register" do
    it "creates a process and adds it to the registry" do
      process = described_class.register(name: "my-process")

      expect(process.id).to be_a(String)
      expect(Lepus::ProcessRegistry.instance.all).to eq([process])
    end
  end

  describe ".prune" do
    it "deletes all processes that are not running" do
      described_class.register(last_heartbeat_at: Time.now - 5 * 60, name: "prune-me")
      keep = described_class.register(last_heartbeat_at: Time.now, name: "keep-me")

      described_class.prune

      expect(Lepus::ProcessRegistry.instance.all).to eq([keep])
    end

    it "does not prune the excluded process" do
      old = described_class.register(last_heartbeat_at: Time.now - 10 * 60, name: "old")
      keep = described_class.register(last_heartbeat_at: Time.now, name: "keep")

      described_class.prune(excluding: old)

      expect(Lepus::ProcessRegistry.instance.all).to contain_exactly(old, keep)
    end
  end

  describe "#heartbeat" do
    it "updates the last_heartbeat_at" do
      process = described_class.register(name: "my-process")

      expect { process.heartbeat }.to change { Lepus::ProcessRegistry.instance.find(process.id).last_heartbeat_at }
    end

    it "raises when the process is not registered anymore" do
      process = described_class.new(id: "gone", name: "ghost")

      expect { process.heartbeat }.to raise_error(Lepus::Process::NotFoundError)
    end
  end

  describe "#update_attributes" do
    it "updates the attributes" do
      process = described_class.register(name: "my-process")

      process.update_attributes(name: "new-name")

      expect(process.name).to eq("new-name")
    end
  end

  describe "#destroy!" do
    it "removes the process from the registry" do
      process = described_class.register(name: "my-process")

      process.destroy!

      expect(Lepus::ProcessRegistry.instance.all).to eq([])
    end
  end

  describe "#deregister" do
    it "removes the process from the registry and deregisters supervisees" do
      supervisor1 = described_class.register(name: "supervisor-1")
      described_class.register(name: "supervisee-1", supervisor_id: supervisor1.id)

      supervisor2 = described_class.register(name: "supervisor-2")
      supervisee2 = described_class.register(name: "supervisee-2", supervisor_id: supervisor2.id)

      supervisor1.deregister

      expect(Lepus::ProcessRegistry.instance.all).to eq([supervisor2, supervisee2])
    end

    it "does not deregister supervisor" do
      supervisor = described_class.register(name: "supervisor")
      supervisee = described_class.register(name: "supervisee", supervisor_id: supervisor.id)

      supervisee.deregister

      expect(Lepus::ProcessRegistry.instance.all).to eq([supervisor])
    end

    it "does not deregister supervisees when pruned" do
      supervisor = described_class.register(name: "supervisor")
      supervisee = described_class.register(name: "supervisee", supervisor_id: supervisor.id)

      supervisor.prune

      expect(Lepus::ProcessRegistry.instance.all).to eq([supervisee])
    end
  end

  describe "#supervised?" do
    it "returns true if the process is supervised" do
      process = described_class.register(supervisor_id: "supervisor-id")

      expect(process).to be_supervised
    end

    it "returns false if the process is not supervised" do
      process = described_class.register

      expect(process).not_to be_supervised
    end
  end

  describe ".prunable" do
    it "returns processes whose heartbeat is older than the threshold" do
      threshold = Lepus.config.process_alive_threshold
      old = described_class.register(last_heartbeat_at: Time.now - (threshold + 1), name: "old-one")
      fresh = described_class.register(last_heartbeat_at: Time.now, name: "fresh-one")

      expect(described_class.prunable).to eq([old])
      expect(described_class.prunable).not_to include(fresh)
    end
  end

  describe "#rss_memory" do
    it "returns the value from the memory grabber" do
      stub_const("#{described_class}::MEMORY_GRABBER", ->(_pid) { 1234 })
      process = described_class.register(pid: 42, name: "proc")

      expect(process.rss_memory).to eq(1234)
    end
  end

  describe "#eql?" do
    it "returns true if the processes are equal" do
      process1 = described_class.register(id: "id", pid: "pid")
      process2 = described_class.register(id: "id", pid: "pid")

      expect(process1).to eq(process2)
    end

    it "returns false if the processes are not equal" do
      process1 = described_class.register(id: "id", pid: "pid")
      process2 = described_class.register(id: "id", pid: "other-pid")

      expect(process1).not_to eq(process2)
    end

    it "aliases == to eql?" do
      a = described_class.register(id: "same", pid: "p")
      b = described_class.register(id: "same", pid: "p")
      c = described_class.register(id: "same", pid: "q")

      expect(a == b).to be(true)
      expect(a == c).to be(false)
    end
  end
end
