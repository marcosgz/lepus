# frozen_string_literal: true

module Lepus
  module Producers
    # Manages middleware registration and execution for producers.
    # Middlewares can modify the message (payload, headers, routing_key, etc.)
    # before it is published to RabbitMQ.
    class MiddlewareChain < Lepus::MiddlewareChain
      private

      def load_middleware(name, opts)
        require_relative "middlewares/#{name}"
        class_name = Primitive::String.new(name.to_s).classify
        class_name = "JSON" if class_name == "Json"
        klass = Lepus::Producers::Middlewares.const_get(class_name)
        klass.new(**opts)
      rescue LoadError, NameError => e
        raise ArgumentError, "Producer middleware '#{name}' not found: #{e.message}"
      end
    end
  end
end
