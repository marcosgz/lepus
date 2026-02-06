# frozen_string_literal: true

# Mixin for consumers to record processed messages to in-memory ProcessedMessages registry.
# Use this for inline mode integration tests where the consumer runs in the same process.
#
# This module wraps the `perform` method to track messages AFTER middleware processing,
# so the recorded payload reflects any transformations (e.g., JSON parsing).
module TrackableConsumer
  def self.included(base)
    base.prepend(PerformWrapper)
  end

  module PerformWrapper
    def perform(message)
      result = super
      IntegrationHelper::ProcessedMessages.instance.record(self.class, message, result)
      result
    end
  end
end
