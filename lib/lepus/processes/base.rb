# frozen_string_literal: true

module Lepus
  module Processes
    class Base
      # extend Callbacks[:boot, :shutdown]
      include Callbacks
      include AppExecutor
      include Registrable
      include Interruptible
      include Procline

      attr_reader :name

      def initialize(*)
        @stopped = false
      end

      def kind
        self.class.name.split("::").last
      end

      def hostname
        @hostname ||= Socket.gethostname.force_encoding(Encoding::UTF_8)
      end

      def pid
        @pid ||= ::Process.pid
      end

      def metadata
        {}
      end

      def stop
        @stopped = true
      end

      private

      def stopped?
        @stopped
      end
    end
  end
end
