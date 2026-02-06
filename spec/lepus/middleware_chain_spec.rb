# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::MiddlewareChain do
  let(:chain) { described_class.new }

  def build_message(payload = "test", headers: nil, routing_key: nil)
    delivery_info = Lepus::Message::DeliveryInfo.new(
      exchange: "test_exchange",
      routing_key: routing_key
    )
    metadata = Lepus::Message::Metadata.new(headers: headers)
    Lepus::Message.new(delivery_info, metadata, payload)
  end

  describe "#use" do
    it "adds a middleware instance to the chain" do
      middleware = Class.new(Lepus::Middleware) do
        def call(message, app)
          app.call(message)
        end
      end

      chain.use(middleware)

      expect(chain.middlewares.size).to eq(1)
      expect(chain.middlewares.first).to be_a(middleware)
    end

    it "passes options to the middleware constructor" do
      middleware = Class.new(Lepus::Middleware) do
        attr_reader :options

        def initialize(**opts)
          @options = opts
        end

        def call(message, app)
          app.call(message)
        end
      end

      chain.use(middleware, foo: "bar")

      expect(chain.middlewares.first.options).to eq(foo: "bar")
    end

    it "raises NotImplementedError when subclass does not implement #load_middleware" do
      expect { chain.use(:json) }.to raise_error(NotImplementedError)
    end

    it "returns self for chaining" do
      middleware = Class.new(Lepus::Middleware) do
        def call(message, app)
          app.call(message)
        end
      end

      result = chain.use(middleware)

      expect(result).to be(chain)
    end
  end

  describe "#execute" do
    it "calls the final action with the message when chain is empty" do
      message = build_message("payload")
      result = nil

      chain.execute(message) do |msg|
        result = msg.payload
      end

      expect(result).to eq("payload")
    end

    it "executes middlewares in order" do
      order = []

      middleware1 = Class.new(Lepus::Middleware) do
        define_method(:call) do |message, app|
          order << 1
          app.call(message)
        end
      end

      middleware2 = Class.new(Lepus::Middleware) do
        define_method(:call) do |message, app|
          order << 2
          app.call(message)
        end
      end

      chain.use(middleware1)
      chain.use(middleware2)

      chain.execute(build_message) { |_| order << :final }

      expect(order).to eq([1, 2, :final])
    end

    it "allows middlewares to modify the message" do
      modifier = Class.new(Lepus::Middleware) do
        def call(message, app)
          app.call(message.mutate(payload: "modified"))
        end
      end

      chain.use(modifier)
      result = nil

      chain.execute(build_message("original")) do |msg|
        result = msg.payload
      end

      expect(result).to eq("modified")
    end

    it "allows middlewares to short-circuit the chain" do
      blocker = Class.new(Lepus::Middleware) do
        def call(message, app)
          :blocked
        end
      end

      chain.use(blocker)
      final_called = false

      result = chain.execute(build_message) do |_|
        final_called = true
        :ok
      end

      expect(result).to eq(:blocked)
      expect(final_called).to be false
    end

    it "returns the result of the final action" do
      result = chain.execute(build_message) { |_| :success }

      expect(result).to eq(:success)
    end
  end

  describe ".combine" do
    it "combines multiple chains into one" do
      chain1 = described_class.new
      chain2 = described_class.new

      middleware1 = Class.new(Lepus::Middleware) do
        def call(message, app)
          app.call(message)
        end
      end

      middleware2 = Class.new(Lepus::Middleware) do
        def call(message, app)
          app.call(message)
        end
      end

      chain1.use(middleware1)
      chain2.use(middleware2)

      combined = described_class.combine(chain1, chain2)

      expect(combined.middlewares.size).to eq(2)
    end

    it "preserves execution order across combined chains" do
      chain1 = described_class.new
      chain2 = described_class.new
      order = []

      middleware1 = Class.new(Lepus::Middleware) do
        define_method(:call) do |message, app|
          order << :global
          app.call(message)
        end
      end

      middleware2 = Class.new(Lepus::Middleware) do
        define_method(:call) do |message, app|
          order << :local
          app.call(message)
        end
      end

      chain1.use(middleware1)
      chain2.use(middleware2)

      combined = described_class.combine(chain1, chain2)
      combined.execute(build_message) { |_| order << :final }

      expect(order).to eq([:global, :local, :final])
    end
  end

  describe "#empty?" do
    it "returns true when no middlewares are registered" do
      expect(chain.empty?).to be true
    end

    it "returns false when middlewares are registered" do
      middleware = Class.new(Lepus::Middleware) do
        def call(message, app)
          app.call(message)
        end
      end

      chain.use(middleware)

      expect(chain.empty?).to be false
    end
  end

  describe "#size" do
    it "returns the number of middlewares" do
      middleware = Class.new(Lepus::Middleware) do
        def call(message, app)
          app.call(message)
        end
      end

      expect(chain.size).to eq(0)

      chain.use(middleware)
      expect(chain.size).to eq(1)

      chain.use(middleware)
      expect(chain.size).to eq(2)
    end
  end
end
