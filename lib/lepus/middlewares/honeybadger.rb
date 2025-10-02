# frozen_string_literal: true

module Lepus
  module Middlewares
    # A middleware that automatically wraps {Lepus::Consumer#perform]} in an Honeybadger transaction.
    class Honeybadger < Lepus::Middleware
      # @param app The next middleware to call or the actual consumer instance.
      # @param [Hash] opts The options for the middleware.
      # @option opts [String] :class_name The name of the class you want to monitor.
      def initialize(app, class_name: nil, **opts)
        super(app, **opts)

        @class_name = class_name
      end

      def call(message)
        app.call(message)
      rescue => err
        ::Honeybadger.notify(err, context: context(message))
        raise err
      end

      private

      def context(message)
        return {class_name: @class_name} if @class_name
        return {class_name: message.consumer_class.name} if message.consumer_class

        {}
      end
    end
  end
end
