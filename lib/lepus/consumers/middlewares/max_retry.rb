# frozen_string_literal: true

module Lepus
  module Consumers
    module Middlewares
      # A middleware that automatically puts messages on an error queue when the specified number of retries are exceeded.
      class MaxRetry < Lepus::Middleware
        include Lepus::AppExecutor

        # @param [Hash] opts The options for the middleware.
        # @option opts [Integer] :retries The number of retries before the message is sent to the error queue.
        # @option opts [String] :error_queue The name of the queue where messages should be sent to when the max retries are reached.
        #   If not provided, will fallback to the consumer's configured error queue name.
        def initialize(retries:, error_queue: nil)
          super

          @retries = retries
          @error_queue = error_queue
        end

        def call(message, app)
          return handle_exceeded(message) if retries_exceeded?(message.metadata)

          app.call(message)
        end

        private

        attr_reader :retries

        def handle_exceeded(message)
          payload = message.payload
          payload = MultiJson.dump(payload) if payload.is_a?(Hash)
          ::Bunny::Exchange.default(message.channel).publish(
            payload,
            routing_key: error_queue_name(message)
          )
          :ack
        rescue Lepus::InvalidConsumerConfigError => err
          raise err
        rescue => err
          handle_thread_error(err)
        end

        def error_queue_name(message)
          return @error_queue if @error_queue

          default_error_queue_name(message)
        end

        def default_error_queue_name(message)
          unless message.consumer_class&.config
            raise Lepus::InvalidConsumerConfigError, "Error queue name is required and consumer class is not available"
          end

          config = message.consumer_class.config
          unless config.error_queue_name
            raise Lepus::InvalidConsumerConfigError, "Error queue name is required. Configure error_queue in consumer config or provide error_queue option to middleware"
          end

          config.error_queue_name
        end

        def retries_exceeded?(metadata)
          return false if metadata.headers.nil?

          rejected_deaths =
            metadata
              .headers
              .fetch("x-death", [])
              .select { |death| death["reason"] == "rejected" }

          return false unless rejected_deaths.any?

          retry_count = rejected_deaths.map { |death| death["count"] }.compact.max
          return false unless retry_count

          retry_count > @retries
        end
      end
    end
  end
end
