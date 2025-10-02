# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Middleware do
  let(:app) { proc { :result } }
  let(:middleware) { described_class.new(app) }

  describe "#initialize" do
    it "requires an app argument" do
      expect { described_class.new }.to raise_error(ArgumentError)
    end

    it "accepts an app and keyword arguments" do
      expect { described_class.new(app, custom_arg: "value") }.not_to raise_error
    end

    it "sets the app attribute" do
      expect(middleware.app).to eq(app)
    end
  end

  describe "#call" do
    let(:message) { instance_double(Lepus::Message) }

    it "raises NotImplementedError when called directly" do
      expect { middleware.call(message) }.to raise_error(NotImplementedError)
    end
  end
end
