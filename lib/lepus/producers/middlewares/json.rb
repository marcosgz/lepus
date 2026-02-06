# frozen_string_literal: true

require "multi_json"

module Lepus
  module Producers
    module Middlewares
      # A middleware that serializes Hash payloads to JSON and sets the content_type.
      class JSON < Lepus::Middleware
        # @param opts [Hash] The options for the middleware.
        # @option opts [Boolean] :only_hash (true) Only serialize Hash payloads.
        def initialize(**opts)
          super
          @only_hash = opts.fetch(:only_hash, true)
        end

        def call(message, app)
          payload = message.payload

          if should_serialize?(payload)
            serialized_payload = MultiJson.dump(payload)
            new_metadata = update_metadata(message.metadata, content_type: "application/json")
            message = message.mutate(payload: serialized_payload, metadata: new_metadata)
          end

          app.call(message)
        end

        private

        attr_reader :only_hash

        def should_serialize?(payload)
          return false if payload.is_a?(String)
          return payload.is_a?(Hash) if only_hash

          true
        end

        def update_metadata(metadata, **attrs)
          current = metadata&.to_h || {}
          Message::Metadata.new(**current.merge(attrs))
        end
      end
    end
  end
end
