# frozen_string_literal: true

RSpec.describe "Consumer Integration", :integration do
  before { reset_config! }

  describe "inline mode" do
    let(:test_consumer) do
      Class.new(Lepus::Consumer) do
        include TrackableConsumer

        configure(
          queue: "test_consumer_integration",
          exchange: "test_consumer_integration",
          routing_key: "test.#"
        )
        use :json

        def perform(message)
          :ack
        end
      end
    end

    # Use regular let (lazy) instead of let! so it evaluates AFTER before block
    let(:handle) { start_consumer_inline(test_consumer) }

    before do
      cleanup_rabbitmq_for(test_consumer)
      # Force handle to be created after cleanup
      handle
    end

    after do
      stop_consumer_inline(handle)
      cleanup_rabbitmq_for(test_consumer)
    end

    it "processes a message and acknowledges it" do
      publisher = Lepus::Publisher.new("test_consumer_integration")
      publisher.publish({key: "value"}, routing_key: "test.event")

      IntegrationHelper::ProcessedMessages.instance.wait_for(1, timeout: 5)

      messages = IntegrationHelper::ProcessedMessages.instance.all
      expect(messages.size).to eq(1)
      expect(messages.first[:result]).to eq(:ack)
      expect(messages.first[:payload]).to eq({"key" => "value"})
    end

    it "processes multiple messages" do
      publisher = Lepus::Publisher.new("test_consumer_integration")
      publisher.publish({event: "first"}, routing_key: "test.event.one")
      publisher.publish({event: "second"}, routing_key: "test.event.two")

      IntegrationHelper::ProcessedMessages.instance.wait_for(2, timeout: 5)

      messages = IntegrationHelper::ProcessedMessages.instance.all
      expect(messages.size).to eq(2)
      payloads = messages.map { |m| m[:payload]["event"] }
      expect(payloads).to contain_exactly("first", "second")
    end

    context "with rejection" do
      let(:rejecting_consumer) do
        Class.new(Lepus::Consumer) do
          include TrackableConsumer

          configure(
            queue: "test_rejecting_consumer",
            exchange: "test_rejecting_consumer",
            routing_key: "reject.#"
          )
          use :json

          def perform(message)
            :reject
          end
        end
      end

      let(:reject_handle) { start_consumer_inline(rejecting_consumer) }

      before do
        cleanup_rabbitmq_for(rejecting_consumer)
        reject_handle
      end

      after do
        stop_consumer_inline(reject_handle)
        cleanup_rabbitmq_for(rejecting_consumer)
      end

      it "rejects messages" do
        publisher = Lepus::Publisher.new("test_rejecting_consumer")
        publisher.publish({action: "reject_me"}, routing_key: "reject.event")

        IntegrationHelper::ProcessedMessages.instance.wait_for(1, timeout: 5)

        messages = IntegrationHelper::ProcessedMessages.instance.all
        expect(messages.size).to eq(1)
        expect(messages.first[:result]).to eq(:reject)
      end
    end

    context "with routing key patterns" do
      let(:pattern_consumer) do
        Class.new(Lepus::Consumer) do
          include TrackableConsumer

          configure(
            queue: "test_pattern_consumer",
            exchange: "test_pattern_consumer",
            routing_key: "user.created.*"
          )
          use :json

          def perform(message)
            :ack
          end
        end
      end

      let(:pattern_handle) { start_consumer_inline(pattern_consumer) }

      before do
        cleanup_rabbitmq_for(pattern_consumer)
        pattern_handle
      end

      after do
        stop_consumer_inline(pattern_handle)
        cleanup_rabbitmq_for(pattern_consumer)
      end

      it "receives messages matching the routing key pattern" do
        publisher = Lepus::Publisher.new("test_pattern_consumer")
        publisher.publish({user_id: 1}, routing_key: "user.created.admin")
        publisher.publish({user_id: 2}, routing_key: "user.created.guest")
        publisher.publish({user_id: 3}, routing_key: "user.deleted.admin") # Should NOT match

        IntegrationHelper::ProcessedMessages.instance.wait_for(2, timeout: 5)

        messages = IntegrationHelper::ProcessedMessages.instance.all
        expect(messages.size).to eq(2)
        user_ids = messages.map { |m| m[:payload]["user_id"] }
        expect(user_ids).to contain_exactly(1, 2)
      end
    end
  end
end
