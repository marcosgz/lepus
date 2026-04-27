# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::ProcessRegistry::FileBackend do
  subject(:backend) { described_class.new }

  before do
    backend.start
  end

  after do
    backend.stop
  end

  let(:process) { Lepus::Process.new(id: SecureRandom.uuid, name: "worker1") }

  describe "#start" do
    it "initializes the path" do
      expect(backend.path).not_to be_nil
    end
  end

  describe "#add" do
    it "adds a process" do
      expect {
        backend.add(process)
      }.to change(backend, :count).by(1)
    end
  end

  describe "#delete" do
    it "deletes a process" do
      backend.add(process)

      expect {
        backend.delete(process)
      }.to change(backend, :count).by(-1)
    end
  end

  describe "#find" do
    it "returns a process by id" do
      backend.add(process)

      expect(backend.find(process.id)).to eq(process)
    end

    it "raises an error when not found" do
      expect {
        backend.find("non-existing")
      }.to raise_error(Lepus::Process::NotFoundError)
    end
  end

  describe "#exists?" do
    it "returns true when process exists" do
      backend.add(process)

      expect(backend.exists?(process.id)).to be(true)
    end

    it "returns false when process does not exist" do
      expect(backend.exists?("non-existing")).to be(false)
    end
  end

  describe "#all" do
    it "returns all processes" do
      backend.add(process)

      expect(backend.all).to eq([process])
    end
  end

  describe "#count" do
    it "returns the count of processes" do
      expect(backend.count).to eq(0)

      backend.add(process)

      expect(backend.count).to eq(1)
    end
  end

  describe "#clear" do
    it "clears all processes" do
      backend.add(process)

      backend.clear

      expect(backend.count).to eq(0)
    end
  end
end
