# frozen_string_literal: true

module Lepus
  module Consumers
    module Middlewares
      # A middleware that releases deduplication locks after successful message processing.
      #
      # Works in tandem with Lepus::Producers::Middlewares::Unique. The producer
      # acquires a lock and embeds the lock info in message headers. This consumer
      # middleware reads those headers and releases the lock when the consumer
      # returns :ack.
      #
      # @example
      #   class StoryConsumer < Lepus::Consumer
      #     configure(queue: "stories", exchange: "story_created")
      #     use :unique
      #
      #     def perform(message)
      #       process(message.payload)
      #       ack!
      #     end
      #   end
      class Unique < Lepus::Middleware
        HEADER_LOCK_KEY = "x-dedupe-lock-key"
        HEADER_LOCK_ID = "x-dedupe-lock-id"

        def initialize(**)
          super
        end

        def call(message, app)
          result = app.call(message)

          if result == :ack
            release_lock(message)
          end

          result
        end

        private

        def release_lock(message)
          headers = message.metadata&.headers
          return unless headers

          lock_key = headers[HEADER_LOCK_KEY]
          lock_id = headers[HEADER_LOCK_ID]
          return unless lock_key && lock_id

          lock = DeDupe::Lock.new(lock_key: lock_key, lock_id: lock_id)
          lock.release
        end
      end
    end
  end
end
