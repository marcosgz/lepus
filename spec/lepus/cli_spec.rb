# frozen_string_literal: true

require "lepus/cli"

RSpec.describe Lepus::CLI do
  describe "#health_check" do
    let(:now) { Time.now }
    let(:recent_process) { instance_double(Lepus::Process, last_heartbeat_at: now) }
    let(:stale_process) { instance_double(Lepus::Process, last_heartbeat_at: now - 9999) }

    before do
      allow(Lepus::ProcessRegistry).to receive(:start)
    end

    context "when a worker has a recent heartbeat" do
      before { allow(Lepus::ProcessRegistry).to receive(:all).and_return([recent_process]) }

      it "exits 0 and prints ok" do
        expect { described_class.start(["health_check"]) }
          .to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
          .and output("ok\n").to_stdout
      end
    end

    context "when no workers have a recent heartbeat" do
      before { allow(Lepus::ProcessRegistry).to receive(:all).and_return([stale_process]) }

      it "exits 1" do
        expect { described_class.start(["health_check"]) }
          .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      end
    end

    context "when the registry is empty" do
      before { allow(Lepus::ProcessRegistry).to receive(:all).and_return([]) }

      it "exits 1" do
        expect { described_class.start(["health_check"]) }
          .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      end
    end

    context "when the registry raises" do
      before { allow(Lepus::ProcessRegistry).to receive(:all).and_raise(RuntimeError, "backend unavailable") }

      it "exits 1 without crashing" do
        expect { described_class.start(["health_check"]) }
          .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      end
    end

    context "with a custom --threshold" do
      before { allow(Lepus::ProcessRegistry).to receive(:all).and_return([recent_process]) }

      it "exits 0 when heartbeat is within the custom threshold" do
        expect { described_class.start(["health_check", "--threshold", "120"]) }
          .to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
      end
    end
  end
end
