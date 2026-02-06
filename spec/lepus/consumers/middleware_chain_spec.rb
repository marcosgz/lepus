# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Consumers::MiddlewareChain do
  let(:chain) { described_class.new }

  describe "#use" do
    it "loads middleware by symbol name" do
      require "lepus/consumers/middlewares/json"
      chain.use(:json)

      expect(chain.middlewares.size).to eq(1)
      expect(chain.middlewares.first).to be_a(Lepus::Consumers::Middlewares::JSON)
    end

    it "raises error for unknown middleware symbol" do
      expect { chain.use(:nonexistent) }.to raise_error(ArgumentError, /not found/)
    end
  end
end
