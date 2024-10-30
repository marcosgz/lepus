# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus do
  it "has a version number" do
    expect(Lepus::VERSION).not_to be_nil
  end
end
