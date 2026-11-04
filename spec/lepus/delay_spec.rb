# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Delay do
  let(:connection) { instance_double(Bunny::Session) }
  let(:channel) { instance_double(Bunny::Channel, connection: connection) }

  before do
    reset_config!
    described_class.reset!
    allow(channel).to receive(:exchange_declare)
    allow(channel).to receive(:queue_declare)
    allow(channel).to receive(:queue_bind)
    allow(connection).to receive(:with_channel).and_yield(channel)
  end

  after do
    described_class.reset!
    reset_config!
  end

  describe ".normalize" do
    it "accepts integer milliseconds" do
      expect(described_class.normalize(500)).to eq(500)
    end

    it "rounds float milliseconds" do
      expect(described_class.normalize(1500.4)).to eq(1500)
    end

    it "accepts objects responding to in_milliseconds" do
      duration = Struct.new(:in_milliseconds).new(2000.0)

      expect(described_class.normalize(duration)).to eq(2000)
    end

    context "when numbers respond to in_milliseconds (as with ActiveSupport)" do
      let(:duration_class) do
        Class.new do
          def is_a?(klass)
            klass == Integer || super
          end

          def in_milliseconds
            300_000
          end
        end
      end

      before do
        Integer.send(:define_method, :in_milliseconds) { self * 1000 }
        Float.send(:define_method, :in_milliseconds) { self * 1000 }
      end

      after do
        Integer.send(:remove_method, :in_milliseconds)
        Float.send(:remove_method, :in_milliseconds)
      end

      it "keeps plain numbers as milliseconds" do
        expect(described_class.normalize(30_000)).to eq(30_000)
        expect(described_class.normalize(1500.4)).to eq(1500)
      end

      it "converts durations that claim to be integers" do
        expect(described_class.normalize(duration_class.new)).to eq(300_000)
      end
    end

    it "raises for zero or negative values" do
      expect { described_class.normalize(0) }.to raise_error(ArgumentError, /greater than zero/)
      expect { described_class.normalize(-10) }.to raise_error(ArgumentError, /greater than zero/)
      expect { described_class.normalize(0.2) }.to raise_error(ArgumentError, /greater than zero/)
    end

    it "raises for non numeric values" do
      expect { described_class.normalize("500") }.to raise_error(ArgumentError, /Invalid delay/)
      expect { described_class.normalize(nil) }.to raise_error(ArgumentError, /Invalid delay/)
      expect { described_class.normalize(Float::INFINITY) }.to raise_error(ArgumentError, /Invalid delay/)
    end
  end

  describe ".resolve" do
    it "accepts any delay when delay_values is not set" do
      expect(described_class.resolve(1234)).to eq(1234)
    end

    it "accepts allowed delays" do
      Lepus.config.delay_values = [500, 30_000]

      expect(described_class.resolve(30_000.2)).to eq(30_000)
    end

    it "raises for delays outside delay_values" do
      Lepus.config.delay_values = [500, 30_000]

      expect { described_class.resolve(1000) }.to raise_error(Lepus::Error, /1000ms is not allowed, expected one of \[500, 30000\]/)
    end

    it "still validates the value" do
      expect { described_class.resolve(0) }.to raise_error(ArgumentError, /greater than zero/)
    end
  end

  describe "names" do
    it "builds the delayed exchange name" do
      expect(described_class.exchange_name_for("events")).to eq("events.delayed")
    end

    it "builds the exchange delay queue name" do
      expect(described_class.exchange_queue_name_for("events", 500)).to eq("events.delayed.500")
    end

    it "builds the queue delay name apart from the exchange delay queue name" do
      expect(described_class.queue_delay_name_for("events", 500)).to eq("events.delay.500")
    end
  end

  describe ".queue_args_for_exchange" do
    it "dead-letters into the target exchange without overriding the routing key" do
      expect(described_class.queue_args_for_exchange("events", 500)).to eq(
        "x-message-ttl" => 500,
        "x-dead-letter-exchange" => "events",
        "x-expires" => 500 + Lepus::Configuration::DEFAULT_DELAY_QUEUE_EXPIRES
      )
    end

    it "omits x-expires when disabled" do
      Lepus.config.delay_queue_expires = nil

      expect(described_class.queue_args_for_exchange("events", 500)).not_to have_key("x-expires")
    end
  end

  describe ".queue_args_for_queue" do
    it "dead-letters into the target queue through the default exchange" do
      Lepus.config.delay_queue_expires = 1000

      expect(described_class.queue_args_for_queue("jobs", 500)).to eq(
        "x-message-ttl" => 500,
        "x-dead-letter-exchange" => "",
        "x-dead-letter-routing-key" => "jobs",
        "x-expires" => 1500
      )
    end
  end

  describe ".declare_for_exchange!" do
    it "declares the headers exchange, the delay queue and its binding" do
      expect(described_class.declare_for_exchange!(channel, "events", 500)).to eq("events.delayed")

      expect(channel).to have_received(:exchange_declare).with("events.delayed", :headers, durable: true)
      expect(channel).to have_received(:queue_declare).with(
        "events.delayed.500",
        durable: true,
        arguments: described_class.queue_args_for_exchange("events", 500)
      )
      expect(channel).to have_received(:queue_bind).with(
        "events.delayed.500",
        "events.delayed",
        arguments: {"x-match" => "all", "lepus-delay" => 500}
      )
    end

    it "declares once per connection and delay" do
      2.times { described_class.declare_for_exchange!(channel, "events", 500) }
      described_class.declare_for_exchange!(channel, "events", 1000)

      expect(channel).to have_received(:queue_declare).twice
    end

    it "logs only the first declaration of each delay queue" do
      logger = Logger.new(nil)
      allow(logger).to receive(:info)
      allow(Lepus).to receive(:logger).and_return(logger)
      other_connection = instance_double(Bunny::Session)
      other_channel = instance_double(Bunny::Channel, connection: other_connection, queue_declare: nil)
      allow(other_connection).to receive(:with_channel).and_yield(other_channel)

      described_class.declare_for_queue!(channel, "jobs", 500)
      described_class.declare_for_queue!(other_channel, "jobs", 500)
      described_class.declare_for_queue!(channel, "jobs", 1000)

      expect(logger).to have_received(:info).with(/Declared delay queue "jobs.delay.500" \(1 in this process\)/).once
      expect(logger).to have_received(:info).with(/Declared delay queue "jobs.delay.1000" \(2 in this process\)/).once
    end

    it "declares again on another connection" do
      other_connection = instance_double(Bunny::Session)
      other_channel = instance_double(Bunny::Channel, connection: other_connection)
      allow(other_connection).to receive(:with_channel).and_yield(other_channel)
      allow(other_channel).to receive(:exchange_declare)
      allow(other_channel).to receive(:queue_declare)
      allow(other_channel).to receive(:queue_bind)

      described_class.declare_for_exchange!(channel, "events", 500)
      described_class.declare_for_exchange!(other_channel, "events", 500)

      expect(other_channel).to have_received(:queue_declare).once
    end

    context "when re-declaring" do
      let(:now) { [100.0] }

      before do
        allow(::Process).to receive(:clock_gettime).with(::Process::CLOCK_MONOTONIC) { now[0] }
      end

      it "declares again once half of delay_queue_expires has elapsed" do
        Lepus.config.delay_queue_expires = 1000

        described_class.declare_for_exchange!(channel, "events", 1000)
        now[0] += 0.4
        described_class.declare_for_exchange!(channel, "events", 1000)
        now[0] += 0.2
        described_class.declare_for_exchange!(channel, "events", 1000)

        expect(channel).to have_received(:queue_declare).twice
      end

      it "declares again before delay_queue_expires elapses when the delay is longer" do
        Lepus.config.delay_queue_expires = 1000

        described_class.declare_for_exchange!(channel, "events", 4000)
        now[0] += 0.6
        described_class.declare_for_exchange!(channel, "events", 4000)

        expect(channel).to have_received(:queue_declare).twice
      end

      it "declares again at least every REDECLARE_INTERVAL seconds" do
        described_class.declare_for_exchange!(channel, "events", 86_400_000)
        now[0] += described_class::REDECLARE_INTERVAL - 1
        described_class.declare_for_exchange!(channel, "events", 86_400_000)
        now[0] += 2
        described_class.declare_for_exchange!(channel, "events", 86_400_000)

        expect(channel).to have_received(:queue_declare).twice
      end

      it "declares again when x-expires is disabled" do
        Lepus.config.delay_queue_expires = nil

        described_class.declare_for_exchange!(channel, "events", 500)
        now[0] += described_class::REDECLARE_INTERVAL + 1
        described_class.declare_for_exchange!(channel, "events", 500)

        expect(channel).to have_received(:queue_declare).twice
      end

      it "declares again when the queue arguments change" do
        described_class.declare_for_exchange!(channel, "events", 500)
        Lepus.config.delay_queue_expires = 120_000
        described_class.declare_for_exchange!(channel, "events", 500)

        expect(channel).to have_received(:queue_declare).twice
      end
    end

    it "declares on a separate channel of the same connection" do
      declare_channel = instance_double(Bunny::Channel, exchange_declare: nil, queue_declare: nil, queue_bind: nil)
      allow(connection).to receive(:with_channel).and_yield(declare_channel)

      described_class.declare_for_exchange!(channel, "events", 500)

      expect(declare_channel).to have_received(:queue_declare)
      expect(channel).not_to have_received(:queue_declare)
    end

    it "raises a Lepus::Error when the queue exists with other arguments" do
      allow(channel).to receive(:queue_declare).and_raise(Bunny::PreconditionFailed.new("inequivalent arg 'x-expires'", channel, true))

      expect {
        described_class.declare_for_exchange!(channel, "events", 500)
      }.to raise_error(Lepus::Error, /Cannot declare delay queue "events.delayed.500".*inequivalent arg/)
    end
  end

  describe ".declare_for_queue!" do
    it "declares the delay queue for the target queue" do
      expect(described_class.declare_for_queue!(channel, "jobs", 300)).to eq("jobs.delay.300")

      expect(channel).to have_received(:queue_declare).with(
        "jobs.delay.300",
        durable: true,
        arguments: described_class.queue_args_for_queue("jobs", 300)
      )
      expect(channel).not_to have_received(:exchange_declare)
    end

    it "does not share a queue or memo with an exchange delay of the same name" do
      described_class.declare_for_exchange!(channel, "orders", 500)
      described_class.declare_for_queue!(channel, "orders", 500)

      expect(channel).to have_received(:queue_declare).with(
        "orders.delayed.500", durable: true, arguments: described_class.queue_args_for_exchange("orders", 500)
      )
      expect(channel).to have_received(:queue_declare).with(
        "orders.delay.500", durable: true, arguments: described_class.queue_args_for_queue("orders", 500)
      )
    end
  end
end
