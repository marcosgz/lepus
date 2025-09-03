# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::ProcessRegistry do
  before do
    described_class.reset!
  end

  after do
    described_class.stop
  end

  let(:supervisor) { Lepus::Process.new(id: SecureRandom.uuid, name: "supervisor") }
  let(:process) { Lepus::Process.new(id: SecureRandom.uuid, name: "worker1", supervisor_id: supervisor.id) }

  describe "#add" do
    it "adds a process to the registry" do
      expect {
        described_class.add(supervisor)
      }.to change(described_class, :count).by(1)
    end
  end

  describe "#update" do
    it "updates a process in the registry" do
      described_class.add(process)

      expect {
        process.update_attributes(name: "new-name")
      }.to change { described_class.find(process.id).name }.to("new-name")
    end
  end

  describe "#delete" do
    it "deletes a process from the registry" do
      described_class.add(supervisor)
      described_class.add(process)

      described_class.delete(process)

      expect(described_class.all).to eq([supervisor])
    end
  end

  describe "#find" do
    it "returns a process by id" do
      described_class.add(supervisor)

      expect(described_class.find(supervisor.id)).to eq(supervisor)
    end

    it "raises an error when the process does not exist" do
      expect do
        described_class.find("non-existing")
      end.to raise_error(Lepus::Process::NotFoundError)
    end
  end

  describe "#exists?" do
    it "returns true when a process exists" do
      described_class.add(supervisor)

      expect(described_class.exists?(supervisor.id)).to be(true)
    end

    it "returns false when a process does not exist" do
      expect(described_class.exists?("non-existing")).to be(false)
    end
  end

  describe "#all" do
    it "returns all processes" do
      described_class.add(supervisor)
      described_class.add(process)

      expect(described_class.all).to eq([supervisor, process])
    end
  end

  describe "#clear" do
    it "clears all processes" do
      described_class.add(supervisor)
      described_class.add(process)

      described_class.clear

      expect(described_class.all).to eq([])
    end
  end
end
