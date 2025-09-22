# frozen_string_literal: true

require "spec_helper"
require "lepus/testing"

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe Lepus::Testing::RSpecMatchers do
  let(:test_producer_for_matchers_class) do
    Class.new(Lepus::Producer) do
      configure(exchange: "test_exchange")
    end
  end

  before do
    Lepus::Testing.fake_publisher!
    Lepus::Testing.clear_all_messages!

    # Stub the producer class as a constant
    stub_const("TestProducerForMatchers", test_producer_for_matchers_class)

    # Enable the specific producer class
    Lepus::Producers.enable!(test_producer_for_matchers_class)
  end

  after do
    Lepus::Testing.disable!
  end

  describe "lepus_publish_message matcher" do
    before do
      Lepus::Testing.clear_all_messages!
    end

    it "matches when a message is published" do
      expect { TestProducerForMatchers.publish("test message") }.to lepus_publish_message
    end

    it "matches when a specific number of messages are published" do
      expect do
        TestProducerForMatchers.publish("message 1")
        TestProducerForMatchers.publish("message 2")
      end.to lepus_publish_message(2)
    end

    it "matches when publishing to a specific exchange" do
      expect { TestProducerForMatchers.publish("test") }.to lepus_publish_message.to_exchange("test_exchange")
    end

    it "matches when publishing with a specific routing key" do
      expect { TestProducerForMatchers.publish("test", routing_key: "test.key") }.to lepus_publish_message.with_routing_key("test.key")
    end

    it "matches when publishing with specific payload" do
      expect { TestProducerForMatchers.publish({user_id: 123}) }.to lepus_publish_message.with(a_hash_including(user_id: 123))
    end

    it "combines multiple expectations" do
      expect do
        TestProducerForMatchers.publish({user_id: 123}, routing_key: "user.created")
      end.to lepus_publish_message
        .to_exchange("test_exchange")
        .with_routing_key("user.created")
        .with(a_hash_including(user_id: 123))
    end

    it "fails when no message is published" do
      # Clear messages before this specific test
      Lepus::Testing.clear_all_messages!

      expect do
        # Do nothing
      end.not_to lepus_publish_message
    end

    it "fails when wrong number of messages are published" do
      expect do
        TestProducerForMatchers.publish("message 1")
        TestProducerForMatchers.publish("message 2")
      end.not_to lepus_publish_message(1)
    end

    it "fails when publishing to wrong exchange" do
      expect { TestProducerForMatchers.publish("test") }.not_to lepus_publish_message.to_exchange("wrong_exchange")
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
