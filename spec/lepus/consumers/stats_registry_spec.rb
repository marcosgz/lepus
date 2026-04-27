# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Consumers::StatsRegistry do
  subject(:registry) { described_class.new }

  let(:consumer_class_a) do
    Class.new(Lepus::Consumer) do
      configure(queue: "queue_a", exchange: "exchange_a")
      def self.name
        "ConsumerA"
      end

      def perform(message)
        :ack
      end
    end
  end

  let(:consumer_class_b) do
    Class.new(Lepus::Consumer) do
      configure(queue: "queue_b", exchange: "exchange_b")
      def self.name
        "ConsumerB"
      end

      def perform(message)
        :ack
      end
    end
  end

  describe "#for" do
    it "returns a Stats instance for the consumer class" do
      stats = registry.for(consumer_class_a)

      expect(stats).to be_a(Lepus::Consumers::Stats)
      expect(stats.consumer_class).to eq(consumer_class_a)
    end

    it "returns the same Stats instance on subsequent calls" do
      stats1 = registry.for(consumer_class_a)
      stats2 = registry.for(consumer_class_a)

      expect(stats1).to be(stats2)
    end

    it "returns different Stats instances for different consumer classes" do
      stats_a = registry.for(consumer_class_a)
      stats_b = registry.for(consumer_class_b)

      expect(stats_a).not_to be(stats_b)
    end
  end

  describe "#all" do
    it "returns empty array when no stats exist" do
      expect(registry.all).to eq([])
    end

    it "returns array of stats hashes" do
      registry.for(consumer_class_a).record_processed
      registry.for(consumer_class_b).record_rejected

      result = registry.all

      expect(result.size).to eq(2)
      expect(result.map { |h| h[:class_name] }).to contain_exactly("ConsumerA", "ConsumerB")
    end
  end

  describe "#connection_count" do
    it "returns 0 when no stats exist" do
      expect(registry.connection_count).to eq(0)
    end

    it "returns the number of tracked consumer classes" do
      registry.for(consumer_class_a)
      registry.for(consumer_class_b)

      expect(registry.connection_count).to eq(2)
    end
  end
end
