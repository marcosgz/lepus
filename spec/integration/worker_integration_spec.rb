# frozen_string_literal: true

RSpec.describe "Worker Process Integration", :integration do
  before do
    reset_config!
    IntegrationHelper::FileBasedMessageTracker.clear!
  end

  describe "forked mode" do
    let(:forked_consumer) do
      Class.new(Lepus::Consumer) do
        include TrackableConsumerForked

        configure(
          queue: "test_forked_worker",
          exchange: "test_forked_worker",
          routing_key: "test.#"
        )
        use :json

        def perform(message)
          :ack
        end
      end
    end

    before { cleanup_rabbitmq_for(forked_consumer) }

    after do
      stop_worker_fork(@handle) if @handle
      cleanup_rabbitmq_for(forked_consumer)
      IntegrationHelper::FileBasedMessageTracker.clear!
    end

    it "processes messages in a forked worker process" do
      @handle = start_worker_as_fork(forked_consumer)

      publisher = Lepus::Publisher.new("test_forked_worker")
      publisher.publish({action: "test"}, routing_key: "test.event")

      expect(IntegrationHelper::FileBasedMessageTracker.wait_for(1, timeout: 10)).to be true

      messages = IntegrationHelper::FileBasedMessageTracker.read_all
      expect(messages.size).to eq(1)
      expect(messages.first["result"]).to eq("ack")
    end

    it "processes multiple messages in forked worker" do
      @handle = start_worker_as_fork(forked_consumer)

      publisher = Lepus::Publisher.new("test_forked_worker")
      publisher.publish({event: 1}, routing_key: "test.first")
      publisher.publish({event: 2}, routing_key: "test.second")

      expect(IntegrationHelper::FileBasedMessageTracker.wait_for(2, timeout: 10)).to be true

      messages = IntegrationHelper::FileBasedMessageTracker.read_all
      expect(messages.size).to eq(2)
      expect(messages.map { |m| m["result"] }).to all(eq("ack"))
    end

    it "handles worker shutdown gracefully" do
      @handle = start_worker_as_fork(forked_consumer)

      # Publish a message
      publisher = Lepus::Publisher.new("test_forked_worker")
      publisher.publish({action: "before_shutdown"}, routing_key: "test.event")

      expect(IntegrationHelper::FileBasedMessageTracker.wait_for(1, timeout: 10)).to be true

      # Stop the worker
      stop_worker_fork(@handle)
      @handle = nil

      messages = IntegrationHelper::FileBasedMessageTracker.read_all
      expect(messages.size).to eq(1)
      expect(messages.first["payload"]).to include("action" => "before_shutdown")
    end
  end
end
