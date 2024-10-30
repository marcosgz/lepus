# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::ProcessRegistry do
  after do
    Lepus::ProcessRegistry.instance.clear
  end

  let(:supervisor) { instance_double(Lepus::Process, id: "p1") }
  let(:process) { instance_double(Lepus::Process, id: "p2", supervisor_id: "p1") }

  describe "#add" do
    it "adds a process to the registry" do
      Lepus::ProcessRegistry.instance.add(supervisor)

      expect(Lepus::ProcessRegistry.instance.instance_variable_get(:@processes)).to eq("p1" => supervisor)
    end
  end

  describe "#delete" do
    it "deletes a process from the registry" do
      Lepus::ProcessRegistry.instance.add(supervisor)
      Lepus::ProcessRegistry.instance.add(process)

      Lepus::ProcessRegistry.instance.delete(process)

      expect(Lepus::ProcessRegistry.instance.all).to eq([supervisor])
    end
  end

  describe "#find" do
    it "returns a process by id" do
      Lepus::ProcessRegistry.instance.add(supervisor)

      expect(Lepus::ProcessRegistry.instance.find("p1")).to eq(supervisor)
    end

    it "raises an error when the process does not exist" do
      expect do
        Lepus::ProcessRegistry.instance.find("non-existing")
      end.to raise_error(Lepus::Process::NotFoundError)
    end
  end

  describe "#exists?" do
    it "returns true when a process exists" do
      Lepus::ProcessRegistry.instance.add(supervisor)

      expect(Lepus::ProcessRegistry.instance.exists?("p1")).to be(true)
    end

    it "returns false when a process does not exist" do
      expect(Lepus::ProcessRegistry.instance.exists?("non-existing")).to be(false)
    end
  end

  describe "#all" do
    it "returns all processes" do
      Lepus::ProcessRegistry.instance.add(supervisor)
      Lepus::ProcessRegistry.instance.add(process)

      expect(Lepus::ProcessRegistry.instance.all).to eq([supervisor, process])
    end
  end

  describe "#clear" do
    it "clears all processes" do
      Lepus::ProcessRegistry.instance.add(supervisor)
      Lepus::ProcessRegistry.instance.add(process)

      Lepus::ProcessRegistry.instance.clear

      expect(Lepus::ProcessRegistry.instance.all).to eq([])
    end
  end
end
