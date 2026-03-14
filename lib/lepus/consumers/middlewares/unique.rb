# frozen_string_literal: true

module Lepus
  module Consumers
    module Middlewares
      # A middleware that releases deduplication locks after message processing.
      #
      # Works in tandem with Lepus::Producers::Middlewares::Unique. The producer
      # acquires a lock and embeds the lock info in message headers. This consumer
      # middleware reads those headers and releases the lock based on the configured
      # +release_on+ conditions.
      #
      # @example Release on ack (default)
      #   use :unique
      #
      # @example Release on ack or reject
      #   use :unique, release_on: [:ack, :reject]
      #
      # @example Release on error (e.g., dead-letter scenarios)
      #   use :unique, release_on: [:ack, :error]
      class Unique < Lepus::Middleware
        HEADER_LOCK_KEY = "x-dedupe-lock-key"
        HEADER_LOCK_ID = "x-dedupe-lock-id"
        HEADER_LOCK_TTL = "x-dedupe-lock-ttl"

        # @param release_on [Array<Symbol>] Conditions that trigger lock release.
        #   Valid values: +:ack+, +:reject+, +:requeue+, +:nack+, +:error+.
        #   Defaults to +[:ack]+.
        def initialize(release_on: [:ack])
          super()
          @release_on = Array(release_on)
        end

        def call(message, app)
          result = app.call(message)

          if @release_on.include?(result)
            release_lock(message)
          end

          result
        rescue => e
          release_lock(message) if @release_on.include?(:error)
          raise
        end

        private

        def release_lock(message)
          headers = message.metadata&.headers
          return unless headers

          lock_key = headers[HEADER_LOCK_KEY]
          lock_id = headers[HEADER_LOCK_ID]
          return unless lock_key && lock_id

          lock_opts = {}
          lock_opts[:ttl] = headers[HEADER_LOCK_TTL] if headers[HEADER_LOCK_TTL]
          lock = DeDupe::Lock.new(lock_key: lock_key, lock_id: lock_id, **lock_opts)
          lock.release
        end
      end
    end
  end
end
