# frozen_string_literal: true

module Lepus
  module Middlewares
    # A middleware that automatically wraps {Lepus::Consumer#perform]} in an Honeybadger transaction.
    class Honeybadger < Lepus::Middleware
      # @param [Hash] opts The options for the middleware.
      # @option opts [String] :class_name The name of the class you want to monitor.
      def initialize(class_name: nil, **)
        super

        @class_name = class_name
      end

      def call(message, app)
        app.call(message)
      rescue => err
        ::Honeybadger.notify(err, context: context)
        raise err
      end

      private

      def context
        return {} unless @class_name

        {class_name: @class_name}
      end
    end
  end
end
