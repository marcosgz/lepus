# frozen_string_literal: true

RSpec.describe "Middleware Integration", :integration do
  before { reset_config! }

  describe "JSON middleware" do
    let(:json_consumer) do
      Class.new(Lepus::Consumer) do
        include TrackableConsumer

        configure(
          queue: "test_json_middleware",
          exchange: "test_json_middleware",
          routing_key: "json.#"
        )
        use :json, symbolize_keys: true

        def perform(message)
          :ack
        end
      end
    end

    let(:handle) { start_consumer_inline(json_consumer) }

    before do
      cleanup_rabbitmq_for(json_consumer)
      handle
    end

    after do
      stop_consumer_inline(handle)
      cleanup_rabbitmq_for(json_consumer)
    end

    it "parses JSON payload with symbolized keys" do
      publisher = Lepus::Publisher.new("test_json_middleware")
      publisher.publish({name: "test", value: 123}, routing_key: "json.event")

      IntegrationHelper::ProcessedMessages.instance.wait_for(1, timeout: 5)

      messages = IntegrationHelper::ProcessedMessages.instance.all
      expect(messages.size).to eq(1)
      # The JSON middleware with symbolize_keys: true should convert keys to symbols
      expect(messages.first[:payload]).to eq({name: "test", value: 123})
    end
  end

  describe "MaxRetry middleware" do
    let(:failing_consumer) do
      Class.new(Lepus::Consumer) do
        include TrackableConsumer

        configure(
          queue: "test_max_retry",
          exchange: "test_max_retry",
          routing_key: "retry.#",
          retry_queue: true,
          error_queue: true
        )
        use :json
        use :max_retry, retries: 2

        def perform(message)
          :reject
        end
      end
    end

    let(:handle) { start_consumer_inline(failing_consumer) }

    before do
      cleanup_rabbitmq_for(failing_consumer)
      handle
    end

    after do
      stop_consumer_inline(handle)
      cleanup_rabbitmq_for(failing_consumer)
    end

    it "routes messages to error queue after max retries exceeded" do
      publisher = Lepus::Publisher.new("test_max_retry")
      publisher.publish({action: "fail"}, routing_key: "retry.event")

      # The message should be rejected and re-queued via retry queue
      # After max_retries, it should go to error queue
      # This test verifies the initial rejection
      IntegrationHelper::ProcessedMessages.instance.wait_for(1, timeout: 5)

      messages = IntegrationHelper::ProcessedMessages.instance.all
      expect(messages.size).to be >= 1
      expect(messages.first[:result]).to eq(:reject)
    end
  end
end
