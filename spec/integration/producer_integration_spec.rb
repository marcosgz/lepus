# frozen_string_literal: true

RSpec.describe "Producer Integration", :integration do
  before { reset_config! }

  describe "Producer with middleware" do
    let(:test_producer) do
      Class.new(Lepus::Producer) do
        configure(
          exchange: "test_producer_integration"
        )
        use :json
        use :correlation_id
      end
    end

    let(:test_consumer) do
      Class.new(Lepus::Consumer) do
        include TrackableConsumer

        configure(
          queue: "test_producer_consumer",
          exchange: "test_producer_integration",
          routing_key: "producer.#"
        )
        use :json

        def perform(message)
          :ack
        end
      end
    end

    let(:handle) { start_consumer_inline(test_consumer) }

    before do
      cleanup_rabbitmq_for(test_consumer)
      handle
    end

    after do
      stop_consumer_inline(handle)
      cleanup_rabbitmq_for(test_consumer)
    end

    it "publishes messages through producer middleware chain" do
      test_producer.publish({event: "test"}, routing_key: "producer.event")

      IntegrationHelper::ProcessedMessages.instance.wait_for(1, timeout: 5)

      messages = IntegrationHelper::ProcessedMessages.instance.all
      expect(messages.size).to eq(1)
      expect(messages.first[:result]).to eq(:ack)
      expect(messages.first[:payload]).to eq({"event" => "test"})
      # Correlation ID should have been added by the middleware
      expect(messages.first[:metadata].correlation_id).not_to be_nil
    end

    it "respects producer disable hooks" do
      Lepus::Producers.disable!(test_producer)

      test_producer.publish({event: "disabled"}, routing_key: "producer.disabled")

      # No message should be received since producer is disabled
      sleep 0.5
      messages = IntegrationHelper::ProcessedMessages.instance.all
      expect(messages.size).to eq(0)
    ensure
      Lepus::Producers.enable!(test_producer)
    end
  end
end
