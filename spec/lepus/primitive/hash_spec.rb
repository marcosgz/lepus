# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Primitive::Hash do
  describe "#deep_symbolize_keys" do
    it "converts string keys to symbol keys" do
      hash = described_class.new("key1" => "value1", "key2" => "value2")
      result = hash.deep_symbolize_keys
      expect(result).to eq(key1: "value1", key2: "value2")
    end

    it "recursively converts nested hash keys to symbol keys" do
      hash = described_class.new(
        "key1" => "value1",
        "key2" => {
          "nested_key1" => "nested_value1",
          "nested_key2" => {
            "deeply_nested_key" => "deeply_nested_value"
          }
        }
      )
      result = hash.deep_symbolize_keys
      expect(result).to eq(
        key1: "value1",
        key2: {
          nested_key1: "nested_value1",
          nested_key2: {
            deeply_nested_key: "deeply_nested_value"
          }
        }
      )
    end

    it "handles mixed key types" do
      hash = described_class.new(
        "key1" => "value1",
        :key2 => {
          "nested_key1" => "nested_value1",
          :nested_key2 => {
            "deeply_nested_key" => "deeply_nested_value"
          }
        }
      )
      result = hash.deep_symbolize_keys
      expect(result).to eq(
        key1: "value1",
        key2: {
          nested_key1: "nested_value1",
          nested_key2: {
            deeply_nested_key: "deeply_nested_value"
          }
        }
      )
    end

    it "returns an empty hash when called on an empty hash" do
      hash = described_class.new
      result = hash.deep_symbolize_keys
      expect(result).to eq({})
    end

    it "handles arrays containing hashes" do
      hash = described_class.new(
        "key1" => [
          {"array_key1" => "array_value1"},
          {"array_key2" => "array_value2"}
        ]
      )
      result = hash.deep_symbolize_keys
      expect(result).to eq(
        key1: [
          {array_key1: "array_value1"},
          {array_key2: "array_value2"}
        ]
      )
    end
  end
end
