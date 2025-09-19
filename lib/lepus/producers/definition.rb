# frozen_string_literal: true

module Lepus
  module Producers
    # Definition class for producer-specific settings
    class Definition
      attr_reader :exchange_options, :publish_options

      def initialize(options = {})
        opts = Lepus::Primitive::Hash.new(options).deep_symbolize_keys

        # Handle exchange configuration
        exchange_config = opts.delete(:exchange) || {}
        @exchange_options = Lepus::Publisher::DEFAULT_EXCHANGE_OPTIONS.merge(declaration_config(exchange_config))

        # Handle default publish options
        @publish_options = Lepus::Publisher::DEFAULT_PUBLISH_OPTIONS.merge(opts.delete(:publish) || {})

        # Store any remaining options for future use
        @options = opts
      end

      def exchange_name
        @exchange_options[:name] || raise(InvalidProducerConfigError, "Exchange name is required")
      end

      def exchange_args
        [exchange_name, @exchange_options.reject { |k, v| k == :name }]
      end

      private

      # Normalizes a declaration config (for exchanges) into a configuration Hash.
      #
      # If the given `value` is a String, convert it to a Hash with the key `:name` and the value.
      # If the given `value` is a Hash, leave it as is.
      def declaration_config(value)
        case value
        when Hash then value
        when String then {name: value}
        when Symbol then {name: value.to_s}
        when NilClass then {}
        when TrueClass then {}
        end
      end
    end
  end
end
