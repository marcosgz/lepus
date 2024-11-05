# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Supervisor do
  after do
    Lepus::ProcessRegistry.instance.clear
  end

  # rubocop:disable RSpec/AnyInstance
  describe "#check_bunny_connection" do
    subject(:conn_test) { supervisor.send(:check_bunny_connection) }

    let(:config) { Lepus::Supervisor::Config.new(consumers: %w[TestConsumer]) }
    let(:supervisor) { described_class.new(config) }

    context "when the connection is successful" do
      before do
        allow_any_instance_of(Bunny::Session).to receive(:start).and_return(:ok)
      end

      it "does not raise an error" do
        expect { conn_test }.not_to raise_error
      end
    end

    context "when the connection is not successful" do
      before do
        allow_any_instance_of(Bunny::Session).to receive(:start).and_raise(Bunny::Exception)
      end

      it "raises an error" do
        expect { conn_test }.to raise_error(Bunny::Exception)
      end
    end
  end
  # rubocop:enable RSpec/AnyInstance
end
