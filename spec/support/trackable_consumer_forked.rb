# frozen_string_literal: true

# Mixin for consumers to record processed messages to file-based FileBasedMessageTracker.
# Use this for forked mode integration tests where the consumer runs in a separate process.
#
# This module wraps the `perform` method to track messages AFTER middleware processing,
# so the recorded payload reflects any transformations (e.g., JSON parsing).
module TrackableConsumerForked
  def self.included(base)
    base.prepend(PerformWrapper)
  end

  module PerformWrapper
    def perform(message)
      result = super
      IntegrationHelper::FileBasedMessageTracker.record(self.class, message.payload, result)
      result
    end
  end
end
