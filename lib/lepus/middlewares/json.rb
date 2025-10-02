# frozen_string_literal: true

require "multi_json"

module Lepus
  module Middlewares
    # A middleware that automatically parses your JSON payload.
    class JSON < Lepus::Middleware
      # @param app The next middleware to call or the actual consumer instance.
      # @param [Hash] opts The options for the middleware.
      # @option opts [Proc] :on_error (Proc.new { :reject }) A Proc to be called when an error occurs during processing.
      # @option opts [Boolean] :symbolize_keys (false) Whether to symbolize the keys of your payload.
      def initialize(app, **opts)
        super(app, **opts)

        @on_error = opts.fetch(:on_error, proc { :reject })
        @symbolize_keys = opts.fetch(:symbolize_keys, false)
      end

      def call(message)
        begin
          parsed_payload =
            MultiJson.load(message.payload, symbolize_keys: symbolize_keys)
        rescue => e
          return on_error.call(e)
        end

        app.call(message.mutate(payload: parsed_payload))
      end

      private

      attr_reader :symbolize_keys, :on_error
    end
  end
end
