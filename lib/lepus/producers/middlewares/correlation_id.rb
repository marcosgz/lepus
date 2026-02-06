# frozen_string_literal: true

module Lepus
  module Producers
    module Middlewares
      # A middleware that auto-generates a correlation_id if missing.
      class CorrelationId < Lepus::Middleware
        # @param opts [Hash] The options for the middleware.
        # @option opts [Proc, nil] :generator A custom generator proc.
        #   Defaults to SecureRandom.uuid.
        def initialize(**opts)
          super
          @generator = opts.fetch(:generator, -> { SecureRandom.uuid })
        end

        def call(message, app)
          if message.metadata&.correlation_id.nil? || message.metadata.correlation_id.to_s.empty?
            correlation_id = generator.respond_to?(:call) ? generator.call : generator.to_s
            new_metadata = update_metadata(message.metadata, correlation_id: correlation_id)
            message = message.mutate(metadata: new_metadata)
          end

          app.call(message)
        end

        private

        attr_reader :generator

        def update_metadata(metadata, **attrs)
          current = metadata&.to_h || {}
          Message::Metadata.new(**current.merge(attrs))
        end
      end
    end
  end
end
