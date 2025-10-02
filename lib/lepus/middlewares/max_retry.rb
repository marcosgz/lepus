module Lepus
  module Middlewares
    # A middleware that automatically puts messages on an error queue when the specified number of retries are exceeded.
    class MaxRetry < Lepus::Middleware
      include Lepus::AppExecutor

      # @param app The next middleware to call or the actual consumer instance.
      # @param [Hash] opts The options for the middleware.
      # @option opts [Integer] :retries The number of retries before the message is sent to the error queue.
      # @option opts [String] :error_queue The name of the queue where messages should be sent to when the max retries are reached.
      def initialize(app, retries:, error_queue:)
        super(app, retries: retries, error_queue: error_queue)

        @retries = retries
        @error_queue = error_queue
      end

      def call(message)
        return handle_exceeded(message) if retries_exceeded?(message.metadata)

        app.call(message)
      end

      private

      attr_reader :retries, :error_queue

      def handle_exceeded(message)
        payload = message.payload
        payload = MultiJson.dump(payload) if payload.is_a?(Hash)
        ::Bunny::Exchange.default(message.delivery_info.channel).publish(
          payload,
          routing_key: error_queue
        )
        :ack
      rescue => err
        handle_thread_error(err)
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
