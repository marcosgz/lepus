# frozen_string_literal: true

module Lepus
  # The abstract base class for middlewares.
  # @abstract Subclass and override {#call} (and maybe +#initialize+) to implement.
  class Middleware
    attr_accessor :app, :options

    def initialize(app, **options)
      @app = app
      @options = options
    end

    # Invokes the middleware.
    #
    # @param [Lepus::Message] message The message to process.
    def call(message)
      raise NotImplementedError
    end
  end
end
