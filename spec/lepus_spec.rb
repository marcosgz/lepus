# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus do
  it "has a version number" do
    expect(Lepus::VERSION).not_to be_nil
  end

  describe ".with_connection" do
    let(:mock_connection) do
      instance_double(
        Bunny::Session,
        connected?: true,
        close: nil
      )
    end

    it "yields a bunny connection" do
      allow_any_instance_of(Lepus::ConnectionPool).to receive(:with_connection).and_yield(mock_connection)

      expect { |b| Lepus.with_connection(&b) }.to yield_control
    end
  end
end
