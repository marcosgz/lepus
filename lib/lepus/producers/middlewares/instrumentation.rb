# frozen_string_literal: true

module Lepus
  module Producers
    module Middlewares
      # A middleware that emits instrumentation events via Lepus.instrument.
      class Instrumentation < Lepus::Middleware
        # @param opts [Hash] The options for the middleware.
        # @option opts [String] :event_name ("publish") The event name suffix.
        def initialize(**opts)
          super
          @event_name = opts.fetch(:event_name, "publish")
        end

        def call(message, app)
          exchange = message.delivery_info&.exchange
          routing_key = message.delivery_info&.routing_key

          Lepus.instrument(event_name, exchange: exchange, routing_key: routing_key, message: message) do
            app.call(message)
          end
        end

        private

        attr_reader :event_name
      end
    end
  end
end
