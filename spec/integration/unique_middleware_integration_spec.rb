# frozen_string_literal: true

require "de_dupe"

DeDupe.configure do |config|
  config.redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
  config.namespace = "lepus-test"
end

require "lepus/unique"

RSpec.describe "Unique Middleware Integration", :integration do
  before do
    reset_config!
    DeDupe.flush_all
  end

  after do
    DeDupe.flush_all
  end

  describe "producer acquires lock, consumer releases on ack" do
    let(:unique_producer) do
      Class.new(Lepus::Producer) do
        configure(exchange: "test_unique_producer")
        use :json
        use :unique, lock_key: "unique_test", lock_id: ->(msg) { msg.payload[:id].to_s }
      end
    end

    let(:unique_consumer) do
      Class.new(Lepus::Consumer) do
        include TrackableConsumer

        configure(
          queue: "test_unique_consumer",
          exchange: "test_unique_producer",
          routing_key: "#"
        )
        use :json, symbolize_keys: true
        use :unique

        def perform(message)
          :ack
        end
      end
    end

    let(:handle) { start_consumer_inline(unique_consumer) }

    before do
      cleanup_rabbitmq_for(unique_consumer)
      handle
    end

    after do
      stop_consumer_inline(handle)
      cleanup_rabbitmq_for(unique_consumer)
    end

    it "publishes message and lock is released after consumer acks" do
      unique_producer.publish({id: 1, name: "test"}, routing_key: "story.created")

      IntegrationHelper::ProcessedMessages.instance.wait_for(1, timeout: 5)

      messages = IntegrationHelper::ProcessedMessages.instance.all
      expect(messages.size).to eq(1)
      expect(messages.first[:result]).to eq(:ack)

      # Lock should be released after ack
      lock = DeDupe::Lock.new(lock_key: "unique_test", lock_id: "1")
      expect(lock.locked?).to be false
    end
  end

  describe "duplicate publish is silently skipped" do
    let(:unique_producer) do
      Class.new(Lepus::Producer) do
        configure(exchange: "test_unique_dup")
        use :json
        use :unique, lock_key: "dup_test", lock_id: ->(msg) { msg.payload[:id].to_s }, ttl: 30
      end
    end

    let(:unique_consumer) do
      Class.new(Lepus::Consumer) do
        include TrackableConsumer

        configure(
          queue: "test_unique_dup_consumer",
          exchange: "test_unique_dup",
          routing_key: "#"
        )
        use :json, symbolize_keys: true
        use :unique

        def perform(message)
          :ack
        end
      end
    end

    let(:handle) { start_consumer_inline(unique_consumer) }

    before do
      cleanup_rabbitmq_for(unique_consumer)
      handle
    end

    after do
      stop_consumer_inline(handle)
      cleanup_rabbitmq_for(unique_consumer)
    end

    it "only delivers one message when publishing the same id twice" do
      # First publish — should acquire lock and publish
      unique_producer.publish({id: 42, name: "first"}, routing_key: "event")

      IntegrationHelper::ProcessedMessages.instance.wait_for(1, timeout: 5)

      # Second publish with same id — should be silently skipped (lock still held before ack releases it)
      # We need the lock to still be held, so we acquire it again manually
      lock = DeDupe::Lock.new(lock_key: "dup_test", lock_id: "42", ttl: 30)
      lock.acquire

      unique_producer.publish({id: 42, name: "second"}, routing_key: "event")

      # Wait a bit to ensure the second message would have been delivered if published
      sleep 0.5

      messages = IntegrationHelper::ProcessedMessages.instance.all
      expect(messages.size).to eq(1)
      expect(messages.first[:payload][:name]).to eq("first")
    end
  end

  describe "consumer reject does NOT release lock" do
    let(:unique_producer) do
      Class.new(Lepus::Producer) do
        configure(exchange: "test_unique_reject")
        use :json
        use :unique, lock_key: "reject_test", lock_id: ->(msg) { msg.payload[:id].to_s }, ttl: 30
      end
    end

    let(:rejecting_consumer) do
      Class.new(Lepus::Consumer) do
        include TrackableConsumer

        configure(
          queue: "test_unique_reject_consumer",
          exchange: "test_unique_reject",
          routing_key: "#"
        )
        use :json, symbolize_keys: true
        use :unique

        def perform(message)
          :reject
        end
      end
    end

    let(:handle) { start_consumer_inline(rejecting_consumer) }

    before do
      cleanup_rabbitmq_for(rejecting_consumer)
      handle
    end

    after do
      stop_consumer_inline(handle)
      cleanup_rabbitmq_for(rejecting_consumer)
    end

    it "keeps lock held when consumer rejects" do
      unique_producer.publish({id: 99, name: "reject_me"}, routing_key: "event")

      IntegrationHelper::ProcessedMessages.instance.wait_for(1, timeout: 5)

      messages = IntegrationHelper::ProcessedMessages.instance.all
      expect(messages.size).to eq(1)
      expect(messages.first[:result]).to eq(:reject)

      # Lock should still be held after reject
      lock = DeDupe::Lock.new(lock_key: "reject_test", lock_id: "99")
      expect(lock.locked?).to be true
    end
  end

  describe "shared lock_key across producers" do
    let(:producer_a) do
      Class.new(Lepus::Producer) do
        configure(exchange: "test_shared_a")
        use :json
        use :unique, lock_key: "shared_key", lock_id: ->(msg) { msg.payload[:id].to_s }, ttl: 30
      end
    end

    let(:producer_b) do
      Class.new(Lepus::Producer) do
        configure(exchange: "test_shared_b")
        use :json
        use :unique, lock_key: "shared_key", lock_id: ->(msg) { msg.payload[:id].to_s }, ttl: 30
      end
    end

    let(:consumer_a) do
      Class.new(Lepus::Consumer) do
        include TrackableConsumer

        configure(
          queue: "test_shared_a_consumer",
          exchange: "test_shared_a",
          routing_key: "#"
        )
        use :json, symbolize_keys: true
        use :unique

        def perform(message)
          :ack
        end
      end
    end

    let(:consumer_b) do
      Class.new(Lepus::Consumer) do
        include TrackableConsumer

        configure(
          queue: "test_shared_b_consumer",
          exchange: "test_shared_b",
          routing_key: "#"
        )
        use :json, symbolize_keys: true
        use :unique

        def perform(message)
          :ack
        end
      end
    end

    let(:handle_a) { start_consumer_inline(consumer_a) }
    let(:handle_b) { start_consumer_inline(consumer_b) }

    before do
      cleanup_rabbitmq_for(consumer_a)
      cleanup_rabbitmq_for(consumer_b)
      handle_a
      handle_b
    end

    after do
      stop_consumer_inline(handle_a)
      stop_consumer_inline(handle_b)
      cleanup_rabbitmq_for(consumer_a)
      cleanup_rabbitmq_for(consumer_b)
    end

    it "blocks second producer when first holds the lock with same lock_key and lock_id" do
      # Producer A publishes first — acquires lock
      producer_a.publish({id: 7, source: "a"}, routing_key: "event")

      IntegrationHelper::ProcessedMessages.instance.wait_for(1, timeout: 5)

      # Lock is released by consumer_a ack, so re-acquire to simulate held lock
      lock = DeDupe::Lock.new(lock_key: "shared_key", lock_id: "7", ttl: 30)
      lock.acquire

      # Producer B tries with same id — should be blocked
      producer_b.publish({id: 7, source: "b"}, routing_key: "event")

      sleep 0.5

      # Only message from producer A should have been delivered
      messages = IntegrationHelper::ProcessedMessages.instance.all
      expect(messages.size).to eq(1)
      expect(messages.first[:payload][:source]).to eq("a")
    end
  end

  describe "race condition — concurrent publishes" do
    let(:race_producer) do
      Class.new(Lepus::Producer) do
        configure(exchange: "test_race")
        use :json
        use :unique, lock_key: "race_test", lock_id: ->(msg) { msg.payload[:id].to_s }, ttl: 30
      end
    end

    let(:race_consumer) do
      Class.new(Lepus::Consumer) do
        include TrackableConsumer

        configure(
          queue: "test_race_consumer",
          exchange: "test_race",
          routing_key: "#"
        )
        use :json, symbolize_keys: true
        use :unique

        def perform(message)
          :ack
        end
      end
    end

    let(:handle) { start_consumer_inline(race_consumer) }

    before do
      cleanup_rabbitmq_for(race_consumer)
      handle
    end

    after do
      stop_consumer_inline(handle)
      cleanup_rabbitmq_for(race_consumer)
    end

    it "allows exactly 1 publish when 10 threads race with the same lock_id" do
      thread_count = 10
      barrier = Concurrent::CyclicBarrier.new(thread_count)
      results = Concurrent::Array.new

      threads = Array.new(thread_count) do |i|
        Thread.new do
          barrier.wait # Ensure all threads start simultaneously
          result = race_producer.publish({id: 1, thread: i}, routing_key: "event")
          results << result
        end
      end

      threads.each(&:join)

      # Wait for any messages that made it through
      IntegrationHelper::ProcessedMessages.instance.wait_for(1, timeout: 5)

      # Give a little extra time for any other messages (there should be none)
      sleep 0.5

      messages = IntegrationHelper::ProcessedMessages.instance.all
      expect(messages.size).to eq(1)
    end
  end

  describe "lock TTL expiration" do
    let(:ttl_producer) do
      Class.new(Lepus::Producer) do
        configure(exchange: "test_ttl")
        use :json
        use :unique, lock_key: "ttl_test", lock_id: ->(msg) { msg.payload[:id].to_s }, ttl: 1
      end
    end

    let(:ttl_consumer) do
      Class.new(Lepus::Consumer) do
        include TrackableConsumer

        configure(
          queue: "test_ttl_consumer",
          exchange: "test_ttl",
          routing_key: "#"
        )
        use :json, symbolize_keys: true
        use :unique

        def perform(message)
          :ack
        end
      end
    end

    let(:handle) { start_consumer_inline(ttl_consumer) }

    before do
      cleanup_rabbitmq_for(ttl_consumer)
      handle
    end

    after do
      stop_consumer_inline(handle)
      cleanup_rabbitmq_for(ttl_consumer)
    end

    it "allows republishing after TTL expires" do
      # First publish
      ttl_producer.publish({id: 1, attempt: "first"}, routing_key: "event")

      IntegrationHelper::ProcessedMessages.instance.wait_for(1, timeout: 5)

      # Lock is released by consumer ack, but let's test TTL directly:
      # Acquire lock manually with short TTL
      lock = DeDupe::Lock.new(lock_key: "ttl_test", lock_id: "1", ttl: 1)
      lock.acquire
      expect(lock.locked?).to be true

      # Wait for TTL to expire
      sleep 1.5

      # Lock should be expired
      expect(lock.locked?).to be false

      # Should be able to publish again
      ttl_producer.publish({id: 1, attempt: "second"}, routing_key: "event")

      IntegrationHelper::ProcessedMessages.instance.wait_for(2, timeout: 5)

      messages = IntegrationHelper::ProcessedMessages.instance.all
      expect(messages.size).to eq(2)
    end
  end
end
