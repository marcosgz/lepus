# frozen_string_literal: true

require "spec_helper"
require "lepus/producers/middlewares/unique"

RSpec.describe Lepus::Producers::Middlewares::Unique do
  describe "#call" do
    let(:lock_class) do
      stub_const("DeDupe::Lock", Class.new do
        attr_reader :lock_key, :lock_id, :ttl

        def initialize(lock_key:, lock_id:, **opts)
          @lock_key = lock_key
          @lock_id = lock_id
          @ttl = opts[:ttl]
          @acquired = true
        end

        def acquire
          @acquired
        end

        def release
          true
        end

        # Test helper to simulate already-locked state
        def self.make_locked
          @locked = true
        end

        def self.locked?
          @locked == true
        end

        def self.reset!
          @locked = false
        end
      end)
    end

    let(:middleware) do
      described_class.new(
        lock_key: "story",
        lock_id: lock_id_proc,
        **middleware_opts
      )
    end

    let(:lock_id_proc) { ->(msg) { msg.payload[:story_id]&.to_s } }
    let(:middleware_opts) { {} }

    def build_message(payload = nil, opts = {})
      payload ||= {story_id: 123}
      routing_key = opts.fetch(:routing_key, "story.created")
      headers = opts[:headers]
      delivery_info = Lepus::Message::DeliveryInfo.new(
        exchange: "test_exchange",
        routing_key: routing_key
      )
      metadata = Lepus::Message::Metadata.new(headers: headers)
      Lepus::Message.new(delivery_info, metadata, payload)
    end

    before { lock_class }

    it "acquires lock and publishes when lock is available" do
      message = build_message
      downstream_called = false
      result_message = nil

      middleware.call(message, proc { |msg|
        downstream_called = true
        result_message = msg
        :ok
      })

      expect(downstream_called).to be true
    end

    it "adds x-dedupe-lock-key header" do
      message = build_message
      result_headers = nil

      middleware.call(message, proc { |msg|
        result_headers = msg.metadata.headers
        :ok
      })

      expect(result_headers).to include("x-dedupe-lock-key" => "story")
    end

    it "adds x-dedupe-lock-id header" do
      message = build_message
      result_headers = nil

      middleware.call(message, proc { |msg|
        result_headers = msg.metadata.headers
        :ok
      })

      expect(result_headers).to include("x-dedupe-lock-id" => "123")
    end

    it "skips publishing when lock is NOT acquired (duplicate)" do
      allow_any_instance_of(lock_class).to receive(:acquire).and_return(false)

      message = build_message
      downstream_called = false

      result = middleware.call(message, proc { |_msg|
        downstream_called = true
        :ok
      })

      expect(downstream_called).to be false
      expect(result).to be_nil
    end

    it "passes through when lock_id returns nil" do
      middleware_with_nil = described_class.new(
        lock_key: "story",
        lock_id: ->(_msg) {}
      )

      message = build_message
      downstream_called = false
      result_message = nil

      middleware_with_nil.call(message, proc { |msg|
        downstream_called = true
        result_message = msg
        :ok
      })

      expect(downstream_called).to be true
      # Should NOT add dedupe headers when skipping dedup
      expect(result_message.metadata.headers).to be_nil
    end

    it "returns the result of the next middleware" do
      message = build_message
      result = middleware.call(message, proc { |_| :success })

      expect(result).to eq(:success)
    end

    context "with custom TTL" do
      let(:middleware_opts) { {ttl: 3600} }

      it "passes ttl to DeDupe::Lock" do
        message = build_message
        lock_instance = nil

        allow(lock_class).to receive(:new).and_wrap_original do |original, **args|
          lock_instance = original.call(**args)
        end

        middleware.call(message, proc { |_| :ok })

        expect(lock_instance.ttl).to eq(3600)
      end

      it "adds x-dedupe-lock-ttl header" do
        message = build_message
        result_headers = nil

        middleware.call(message, proc { |msg|
          result_headers = msg.metadata.headers
          :ok
        })

        expect(result_headers).to include("x-dedupe-lock-ttl" => 3600)
      end
    end

    it "preserves existing headers" do
      message = build_message(nil, headers: {"x-custom" => "value"})
      result_headers = nil

      middleware.call(message, proc { |msg|
        result_headers = msg.metadata.headers
        :ok
      })

      expect(result_headers).to include(
        "x-custom" => "value",
        "x-dedupe-lock-key" => "story",
        "x-dedupe-lock-id" => "123"
      )
    end

    it "preserves other metadata fields" do
      delivery_info = Lepus::Message::DeliveryInfo.new(
        exchange: "test_exchange",
        routing_key: "test.key"
      )
      metadata = Lepus::Message::Metadata.new(
        content_type: "application/json",
        correlation_id: "abc-123"
      )
      message = Lepus::Message.new(delivery_info, metadata, {story_id: 1})

      result_metadata = nil

      middleware.call(message, proc { |msg|
        result_metadata = msg.metadata
        :ok
      })

      expect(result_metadata.content_type).to eq("application/json")
      expect(result_metadata.correlation_id).to eq("abc-123")
    end

    it "creates lock with correct lock_key and lock_id" do
      payload = {story_id: 456}
      message = build_message(payload)

      expect(lock_class).to receive(:new).with(
        lock_key: "story",
        lock_id: "456"
      ).and_call_original

      middleware.call(message, proc { |_| :ok })
    end
  end
end
