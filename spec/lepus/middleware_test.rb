# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Middleware do
  let(:middleware) { described_class.new }

  describe "#initialize" do
    it "can be initialized with no arguments" do
      expect { described_class.new }.not_to raise_error
    end

    it "accepts keyword arguments" do
      expect { described_class.new(custom_arg: "value") }.not_to raise_error
    end
  end

  describe "#call" do
    let(:message) { double("Lepus::Message") }
    let(:app) { double("NextMiddlewareOrConsumer") }

    it "raises NotImplementedError when called directly" do
      expect { middleware.call(message, app) }.to raise_error(NotImplementedError)
    end
  end
end
