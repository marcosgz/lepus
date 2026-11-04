# frozen_string_literal: true

RSpec.describe "Delayed messages", :integration do
  let(:exchange_name) { "test_delay_integration" }
  let(:processed) { IntegrationHelper::ProcessedMessages.instance }

  before do
    reset_config!
    Lepus::Delay.reset!
  end

  after { Lepus::Delay.reset! }

  def delete_delay_resources(exchange, queues)
    with_rabbitmq_connection do |conn|
      ch = conn.create_channel
      queues.each { |queue| ch.queue_delete(queue) }
      ch.exchange_delete(exchange)
    end
  end

  describe "producer delay" do
    let(:producer) do
      Class.new(Lepus::Producer) do
        configure(exchange: "test_delay_integration")
        use :json
      end
    end

    let(:consumer) do
      Class.new(Lepus::Consumer) do
        include TrackableConsumer

        configure(
          queue: "test_delay_integration",
          exchange: "test_delay_integration",
          routing_key: "delay.#"
        )
        use :json

        def perform(_message)
          ack!
        end
      end
    end

    let(:handle) { start_consumer_inline(consumer) }
    let(:delay_queues) { %w[test_delay_integration.delayed.200 test_delay_integration.delayed.500 test_delay_integration.delayed.1000] }

    before do
      stub_const("DelayIntegrationProducer", producer)
      cleanup_rabbitmq_for(consumer)
      delete_delay_resources("test_delay_integration.delayed", delay_queues)
      handle
    end

    after do
      stop_consumer_inline(handle)
      cleanup_rabbitmq_for(consumer)
      delete_delay_resources("test_delay_integration.delayed", delay_queues)
    end

    it "delivers the message after the delay with its routing key and headers" do
      published_at = Time.now
      producer.publish({id: 1}, routing_key: "delay.created", headers: {"tenant" => "acme"}, delay: 500)

      expect(processed.wait_for(1, timeout: 5)).to be(true)

      message = processed.all.first
      expect(message[:at] - published_at).to be >= 0.5
      expect(message[:payload]).to eq("id" => 1)
      expect(message[:routing_key]).to eq("delay.created")
      expect(message[:metadata].headers).to include("tenant" => "acme", "lepus-delay" => 500)
    end

    it "delivers each delay from its own queue in TTL order" do
      producer.publish({id: "slow"}, routing_key: "delay.slow", delay: 1000)
      producer.publish({id: "fast"}, routing_key: "delay.fast", delay: 200)

      expect(processed.wait_for(2, timeout: 5)).to be(true)

      expect(processed.all.map { |m| m[:payload]["id"] }).to eq(%w[fast slow])
      expect(processed.all.map { |m| m[:routing_key] }).to eq(%w[delay.fast delay.slow])
    end

    it "raises a clear error when a delay queue exists with other arguments" do
      producer.publish({id: 1}, routing_key: "delay.created", delay: 500)
      Lepus::Delay.reset!
      Lepus.config.delay_queue_expires = 120_000

      expect {
        producer.publish({id: 2}, routing_key: "delay.created", delay: 500)
      }.to raise_error(Lepus::Error, /test_delay_integration\.delayed\.500.*inequivalent arg 'x-expires'/)
    end
  end

  describe "consumer delay!" do
    let(:delaying_consumer) do
      Class.new(Lepus::Consumer) do
        include TrackableConsumer

        configure(
          queue: "test_delay_integration_delaying",
          exchange: "test_delay_integration",
          routing_key: "job.#"
        )
        use :json

        def perform(message)
          return ack! if message.metadata.headers&.key?(Lepus::Delay::COUNT_HEADER)

          delay!(300)
        end
      end
    end

    let(:sibling_consumer) do
      Class.new(Lepus::Consumer) do
        include TrackableConsumer

        configure(
          queue: "test_delay_integration_sibling",
          exchange: "test_delay_integration",
          routing_key: "job.#"
        )
        use :json

        def perform(_message)
          ack!
        end
      end
    end

    let(:handles) { [start_consumer_inline(delaying_consumer), start_consumer_inline(sibling_consumer)] }

    before do
      [delaying_consumer, sibling_consumer].each { |c| cleanup_rabbitmq_for(c) }
      delete_delay_resources("test_delay_integration.delayed", %w[test_delay_integration_delaying.delay.300])
      handles
    end

    after do
      handles.each { |h| stop_consumer_inline(h) }
      [delaying_consumer, sibling_consumer].each { |c| cleanup_rabbitmq_for(c) }
      delete_delay_resources("test_delay_integration.delayed", %w[test_delay_integration_delaying.delay.300])
    end

    it "redelivers the message only to its own queue after the delay" do
      Lepus::Publisher.new("test_delay_integration").publish({id: 7}, routing_key: "job.run", headers: {"tenant" => "acme"})

      expect(processed.wait_for(3, timeout: 5)).to be(true)
      sleep 0.5

      delayed = processed.for_consumer(delaying_consumer)
      expect(delayed.size).to eq(2)
      expect(processed.for_consumer(sibling_consumer).size).to eq(1)

      first, second = delayed
      expect(second[:at] - first[:at]).to be >= 0.3
      expect(second[:payload]).to eq("id" => 7)
      expect(second[:metadata].headers).to include("tenant" => "acme", "x-lepus-delayed-count" => 1)
      expect(second[:routing_key]).to eq("test_delay_integration_delaying")
    end
  end

  describe "producer delay and delay! on a queue named like its exchange" do
    let(:producer) do
      Class.new(Lepus::Producer) do
        configure(exchange: "test_delay_integration")
        use :json
      end
    end

    let(:consumer) do
      Class.new(Lepus::Consumer) do
        include TrackableConsumer

        configure(
          queue: "test_delay_integration",
          exchange: "test_delay_integration",
          routing_key: "delay.#"
        )
        use :json

        def perform(message)
          return ack! if message.metadata.headers&.key?(Lepus::Delay::COUNT_HEADER)

          delay!(300)
        end
      end
    end

    let(:handle) { start_consumer_inline(consumer) }
    let(:delay_queues) { %w[test_delay_integration.delayed.300 test_delay_integration.delay.300] }

    before do
      stub_const("DelayIntegrationProducer", producer)
      cleanup_rabbitmq_for(consumer)
      delete_delay_resources("test_delay_integration.delayed", delay_queues)
      handle
    end

    after do
      stop_consumer_inline(handle)
      cleanup_rabbitmq_for(consumer)
      delete_delay_resources("test_delay_integration.delayed", delay_queues)
    end

    it "keeps the exchange and queue delay queues apart" do
      producer.publish({id: 9}, routing_key: "delay.created", delay: 300)

      expect(processed.wait_for(2, timeout: 5)).to be(true)

      first, second = processed.all
      expect(first[:routing_key]).to eq("delay.created")
      expect(second[:routing_key]).to eq("test_delay_integration")
      expect(second[:payload]).to eq("id" => 9)
      expect(second[:at] - first[:at]).to be >= 0.3
    end
  end
end
