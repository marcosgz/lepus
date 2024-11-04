# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::ProcessRegistry do
  after do
    described_class.instance.clear
  end

  let(:supervisor) { instance_double(Lepus::Process, id: "p1") }
  let(:process) { instance_double(Lepus::Process, id: "p2", supervisor_id: "p1") }

  describe "#add" do
    it "adds a process to the registry" do
      described_class.instance.add(supervisor)

      expect(described_class.instance.instance_variable_get(:@processes)).to eq("p1" => supervisor)
    end
  end

  describe "#delete" do
    it "deletes a process from the registry" do
      described_class.instance.add(supervisor)
      described_class.instance.add(process)

      described_class.instance.delete(process)

      expect(described_class.instance.all).to eq([supervisor])
    end
  end

  describe "#find" do
    it "returns a process by id" do
      described_class.instance.add(supervisor)

      expect(described_class.instance.find("p1")).to eq(supervisor)
    end

    it "raises an error when the process does not exist" do
      expect do
        described_class.instance.find("non-existing")
      end.to raise_error(Lepus::Process::NotFoundError)
    end
  end

  describe "#exists?" do
    it "returns true when a process exists" do
      described_class.instance.add(supervisor)

      expect(described_class.instance.exists?("p1")).to be(true)
    end

    it "returns false when a process does not exist" do
      expect(described_class.instance.exists?("non-existing")).to be(false)
    end
  end

  describe "#all" do
    it "returns all processes" do
      described_class.instance.add(supervisor)
      described_class.instance.add(process)

      expect(described_class.instance.all).to eq([supervisor, process])
    end
  end

  describe "#clear" do
    it "clears all processes" do
      described_class.instance.add(supervisor)
      described_class.instance.add(process)

      described_class.instance.clear

      expect(described_class.instance.all).to eq([])
    end
  end
end
