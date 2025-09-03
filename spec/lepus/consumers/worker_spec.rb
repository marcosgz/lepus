# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Consumers::Worker do
  subject(:worker) { faktory.instantiate_process }

  let(:faktory) do
    Lepus::Consumers::WorkerFactory.immutate_with("test-worker", consumers: [consumer_class])
  end
  let(:consumer_class) do
    Class.new(Lepus::Consumer)
  end

  before do
    reset_config!
  end

  it "sets the name" do
    expect(worker.name).to eq("test-worker")
  end

  it "sets the consumers" do
    expect(worker.consumers).to eq([consumer_class])
  end

  describe "#metadata" do
    it "includes name and consumers" do
      metadata = worker.metadata
      expect(metadata[:name]).to eq("test-worker")
      expect(metadata[:consumers]).to eq([consumer_class.to_s])
    end
  end

  describe "#before_fork" do
    it "calls before_fork on each consumer if defined" do
      called = false
      Lepus::Consumers::WorkerFactory["test-worker"].before_fork do
        called = true
      end
      expect { worker.before_fork }.to change { called }.from(false).to(true)
    end

    it "calls before_fork on consumer class if defined" do
      called = false
      consumer_class.define_singleton_method(:before_fork) do
        called = true
      end
      expect { worker.before_fork }.to change { called }.from(false).to(true)
    end
  end

  describe "#after_fork" do
    it "calls after_fork on each consumer if defined" do
      called = false
      Lepus::Consumers::WorkerFactory["test-worker"].after_fork do
        called = true
      end
      expect { worker.after_fork }.to change { called }.from(false).to(true)
    end

    it "calls after_fork on consumer class if defined" do
      called = false
      consumer_class.define_singleton_method(:after_fork) do
        called = true
      end
      expect { worker.after_fork }.to change { called }.from(false).to(true)
    end
  end
end
