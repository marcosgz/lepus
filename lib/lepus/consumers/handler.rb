require "bunny"

module Lepus
  module Consumers
    # Wraps the user-defined consumer to provide the expected interface to Bunny.
    class Handler < Bunny::Consumer
      # @param [Lepus::Consumer] consumer_class The user-defined consumer implementation derived from {Lepus::Consumer}.
      # @param [Bunny::Channel] channel The channel used for the consumer.
      # @param [Bunny::Queue] queue The queue the consumer is subscribed to.
      # @param [String] consumer_tag A string identifying the consumer instance.
      # @param [Hash] arguments Arguments that are passed on to +Bunny::Consumer.new+.
      def initialize(consumer_class, channel, queue, consumer_tag, arguments = {})
        @consumer_class = consumer_class
        super(channel, queue, consumer_tag, _no_ack = false, _exclusive = false, arguments)
      end

      # Called when a message is received from the subscribed queue.
      #
      # @param [Bunny::DeliveryInfo] delivery_info The delivery info of the received message.
      # @param [Bunny::MessageProperties] metadata The metadata of the received message.
      # @param [String] payload The payload of the received message.
      def process_delivery(delivery_info, metadata, payload)
        consumer
          .process_delivery(delivery_info, metadata, payload)
          .tap { |result| process_result(result, delivery_info.delivery_tag) }
      end

      private

      def consumer
        @consumer ||= @consumer_class.new
      end

      def process_result(result, delivery_tag)
        case result
        when :ack
          channel.ack(delivery_tag, false)
        when :reject
          channel.reject(delivery_tag)
        when :requeue
          channel.reject(delivery_tag, true)
        when :nack
          channel.nack(delivery_tag, false, true)
        else
          raise Lepus::InvalidConsumerReturnError, result
        end
      end
    end
  end
end
