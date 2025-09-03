# frozen_string_literal: true

module Lepus::Primitive
  class Hash < ::Hash
    def initialize(*args)
      args.each do |arg|
        arg.each do |key, value|
          self[key] = value
        end
      end
    end

    def deep_symbolize_keys
      each_with_object(self.class.new) do |(key, value), result|
        sym_key = key.is_a?(::String) ? key.to_sym : key
        sym_value = if value.is_a?(::Hash)
          self.class.new(value).deep_symbolize_keys
        elsif value.is_a?(::Array)
          value.map do |item|
            item.is_a?(::Hash) ? self.class.new(item).deep_symbolize_keys : item
          end
        else
          value
        end
        result[sym_key] = sym_value
      end
    end
  end
end
