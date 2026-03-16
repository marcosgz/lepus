# frozen_string_literal: true

require "spec_helper"
require "lepus/web"

RSpec.describe Lepus::Web do
  describe "ConfigExtensions" do
    it "adds web_show_all_exchanges to Configuration" do
      expect(Lepus.config).to respond_to(:web_show_all_exchanges)
      expect(Lepus.config).to respond_to(:web_show_all_exchanges=)
    end

    it "defaults web_show_all_exchanges to false" do
      config = Lepus::Configuration.new
      expect(config.web_show_all_exchanges).to be(false)
    end

    it "allows setting web_show_all_exchanges" do
      config = Lepus::Configuration.new
      config.web_show_all_exchanges = true
      expect(config.web_show_all_exchanges).to be(true)
    end
  end

  describe "ConsumerExtensions" do
    let(:consumer_class) do
      Class.new(Lepus::Consumer) do
        configure(queue: "test", exchange: "test")

        def self.name
          "WebTestConsumer"
        end

        def perform(message)
          :ack
        end
      end
    end

    it "defaults last_delivery_errored? to false" do
      consumer = consumer_class.new
      expect(consumer.last_delivery_errored?).to be(false)
    end

    it "tracks error state on delivery error" do
      consumer = consumer_class.new
      # Simulate what happens during an exception in process_delivery
      consumer.send(:on_delivery_error)
      expect(consumer.last_delivery_errored?).to be(true)
    end

    it "resets error state on each new delivery" do
      consumer = consumer_class.new
      consumer.send(:on_delivery_error)
      expect(consumer.last_delivery_errored?).to be(true)

      # The prepend wrapper resets @_last_delivery_errored = false before calling super.
      # Verify this by calling the wrapper method and checking flag before any exception.
      allow(consumer).to receive(:perform).and_return(:ack)

      # Use a real-enough delivery info to go through process_delivery
      delivery_info = instance_double(Bunny::DeliveryInfo, routing_key: "test")
      metadata = instance_double(Bunny::MessageProperties, headers: nil, content_type: nil)

      # Stub Message.coerce to avoid needing real Bunny objects
      message = instance_double(Lepus::Message)
      allow(message).to receive(:consumer_class=)
      allow(Lepus::Message).to receive(:coerce).and_return(message)

      consumer.process_delivery(delivery_info, metadata, "payload")
      expect(consumer.last_delivery_errored?).to be(false)
    end
  end

  describe "HandlerExtensions" do
    let(:channel) { instance_double(Bunny::Channel) }
    let(:queue) { instance_double(Bunny::Queue) }
    let(:consumer_class) do
      Class.new(Lepus::Consumer) do
        configure(queue: "test", exchange: "test")

        def self.name
          "HandlerTestConsumer"
        end

        def perform(message)
          :ack
        end
      end
    end
    let(:consumer) { instance_double(consumer_class) }
    let(:delivery_info) { instance_double(Bunny::DeliveryInfo, delivery_tag: 1) }
    let(:metadata) { instance_double(Bunny::MessageProperties) }
    let(:stats) { Lepus::Consumers::Stats.new(consumer_class) }
    let(:handler) do
      Lepus::Consumers::Handler.new(consumer_class, channel, queue, "tag").tap do |h|
        h.stats = stats
      end
    end

    before do
      allow(channel).to receive(:generate_consumer_tag)
      allow(channel).to receive(:ack)
      allow(channel).to receive(:reject)
      allow(channel).to receive(:nack)
      handler.instance_variable_set(:@consumer, consumer)
    end

    it "exposes stats accessor" do
      expect(handler).to respond_to(:stats)
      expect(handler).to respond_to(:stats=)
    end

    it "records processed on :ack" do
      allow(consumer).to receive_messages(process_delivery: :ack, last_delivery_errored?: false)

      handler.process_delivery(delivery_info, metadata, "payload")

      expect(stats.processed).to eq(1)
    end

    it "records rejected on :reject without error" do
      allow(consumer).to receive_messages(process_delivery: :reject, last_delivery_errored?: false)

      handler.process_delivery(delivery_info, metadata, "payload")

      expect(stats.rejected).to eq(1)
      expect(stats.errored).to eq(0)
    end

    it "records errored on :reject with error" do
      allow(consumer).to receive_messages(process_delivery: :reject, last_delivery_errored?: true)

      handler.process_delivery(delivery_info, metadata, "payload")

      expect(stats.errored).to eq(1)
      expect(stats.rejected).to eq(0)
    end

    it "records rejected on :requeue without error" do
      allow(consumer).to receive_messages(process_delivery: :requeue, last_delivery_errored?: false)

      handler.process_delivery(delivery_info, metadata, "payload")

      expect(stats.rejected).to eq(1)
    end

    it "records rejected on :nack without error" do
      allow(consumer).to receive_messages(process_delivery: :nack, last_delivery_errored?: false)

      handler.process_delivery(delivery_info, metadata, "payload")

      expect(stats.rejected).to eq(1)
    end

    it "does not record stats when stats is nil" do
      handler.stats = nil
      allow(consumer).to receive_messages(process_delivery: :ack, last_delivery_errored?: false)

      expect { handler.process_delivery(delivery_info, metadata, "payload") }.not_to raise_error
    end
  end

  describe ".assets_path" do
    it "returns a Pathname instance" do
      expect(described_class.assets_path).to be_a(Pathname)
    end

    it "returns the application root directory" do
      expected_root = Pathname.new(File.expand_path("../../web", __dir__))
      expect(described_class.assets_path).to eq(expected_root)
    end

    it "memoizes the result" do
      first_call = described_class.assets_path
      second_call = described_class.assets_path
      expect(first_call).to be(second_call)
    end
  end

  describe ".mime_for" do
    it "returns correct MIME type for HTML files" do
      expect(described_class.mime_for("index.html")).to eq("text/html")
      expect(described_class.mime_for("/path/to/file.html")).to eq("text/html")
    end

    it "returns correct MIME type for CSS files" do
      expect(described_class.mime_for("styles.css")).to eq("text/css")
      expect(described_class.mime_for("/assets/css/styles.css")).to eq("text/css")
    end

    it "returns correct MIME type for JavaScript files" do
      expect(described_class.mime_for("app.js")).to eq("application/javascript")
      expect(described_class.mime_for("/assets/js/app.js")).to eq("application/javascript")
    end

    it "returns correct MIME type for PNG images" do
      expect(described_class.mime_for("image.png")).to eq("image/png")
      expect(described_class.mime_for("/assets/images/logo.png")).to eq("image/png")
    end

    it "returns correct MIME type for JPEG images" do
      expect(described_class.mime_for("photo.jpg")).to eq("image/jpeg")
      expect(described_class.mime_for("photo.jpeg")).to eq("image/jpeg")
      expect(described_class.mime_for("/assets/images/photo.jpg")).to eq("image/jpeg")
    end

    it "returns correct MIME type for SVG images" do
      expect(described_class.mime_for("icon.svg")).to eq("image/svg+xml")
      expect(described_class.mime_for("/assets/icons/icon.svg")).to eq("image/svg+xml")
    end

    it "returns default MIME type for unknown file extensions" do
      expect(described_class.mime_for("file.txt")).to eq("application/octet-stream")
      expect(described_class.mime_for("file")).to eq("application/octet-stream")
      expect(described_class.mime_for("file.unknown")).to eq("application/octet-stream")
    end

    it "handles files without extensions" do
      expect(described_class.mime_for("README")).to eq("application/octet-stream")
    end

    it "handles empty string" do
      expect(described_class.mime_for("")).to eq("application/octet-stream")
    end
  end
end
