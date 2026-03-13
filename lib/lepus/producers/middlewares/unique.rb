# frozen_string_literal: true

module Lepus
  module Producers
    module Middlewares
      # A middleware that prevents duplicate messages from being published
      # using the de-dupe gem for Redis-based distributed locking.
      #
      # When a lock is acquired, the middleware adds x-dedupe-lock-key and
      # x-dedupe-lock-id headers to the message so that a consumer middleware
      # can release the lock after successful processing.
      #
      # @example
      #   class StoryCreatedProducer < Lepus::Producer
      #     configure(exchange: "story_created")
      #     use :unique, lock_key: "story", lock_id: ->(msg) { msg.payload[:story_id].to_s }
      #   end
      class Unique < Lepus::Middleware
        HEADER_LOCK_KEY = "x-dedupe-lock-key"
        HEADER_LOCK_ID = "x-dedupe-lock-id"

        # @param lock_key [String] Shared lock namespace (e.g., "story").
        # @param lock_id [Proc] Callable that extracts a unique ID from the message.
        # @param ttl [Integer, nil] Lock TTL in seconds. Defaults to DeDupe configuration.
        def initialize(lock_key:, lock_id:, ttl: nil)
          super()
          @lock_key = lock_key
          @lock_id = lock_id
          @ttl = ttl
        end

        def call(message, app)
          id = @lock_id.call(message)
          return app.call(message) if id.nil?

          lock_opts = {}
          lock_opts[:ttl] = @ttl if @ttl
          lock = DeDupe::Lock.new(lock_key: @lock_key, lock_id: id.to_s, **lock_opts)
          return unless lock.acquire

          message = add_dedupe_headers(message, id)
          app.call(message)
        end

        private

        def add_dedupe_headers(message, lock_id)
          existing_headers = message.metadata&.headers || {}
          new_headers = existing_headers.merge(
            HEADER_LOCK_KEY => @lock_key,
            HEADER_LOCK_ID => lock_id.to_s
          )

          new_metadata = update_metadata(message.metadata, headers: new_headers)
          message.mutate(metadata: new_metadata)
        end

        def update_metadata(metadata, **attrs)
          current = metadata&.to_h || {}
          Message::Metadata.new(**current.merge(attrs))
        end
      end
    end
  end
end
