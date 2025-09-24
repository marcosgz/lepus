# frozen_string_literal: true

module Lepus
  module Middlewares
    # A middleware that logs exceptions raised by downstream middleware/consumers.
    # Default logger is Lepus.logger.
    class ExceptionLogger < Lepus::Middleware
      # @param [Hash] opts The options for the middleware.
      # @option opts [Logger] :logger The logger to use. Defaults to Lepus.logger.
      def initialize(logger: Lepus.logger, **)
        super

        @logger = logger
      end

      def call(message, app)
        app.call(message)
      rescue => err
        # Log error message; let outer layers decide how to handle the exception
        @logger.error(err.message)
        raise err
      end
    end
  end
end
