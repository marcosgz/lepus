# frozen_string_literal: true

module Lepus
  module Producers
    module Middlewares
      # A middleware that adds default headers to messages.
      # Headers can be static values or dynamic procs.
      class Headers < Lepus::Middleware
        # @param opts [Hash] The options for the middleware.
        # @option opts [Hash] :defaults ({}) Default headers to add.
        #   Values can be Procs that will be called with the message.
        def initialize(**opts)
          super
          @defaults = opts.fetch(:defaults, {})
        end

        def call(message, app)
          new_headers = resolve_headers(message)
          existing_headers = message.metadata&.headers || {}
          merged_headers = new_headers.merge(existing_headers)

          new_metadata = update_metadata(message.metadata, headers: merged_headers)
          app.call(message.mutate(metadata: new_metadata))
        end

        private

        attr_reader :defaults

        def resolve_headers(message)
          defaults.each_with_object({}) do |(key, value), headers|
            headers[key.to_s] = if value.respond_to?(:call)
              (value.arity == 0) ? value.call : value.call(message)
            else
              value
            end
          end
        end

        def update_metadata(metadata, **attrs)
          current = metadata&.to_h || {}
          Message::Metadata.new(**current.merge(attrs))
        end
      end
    end
  end
end
