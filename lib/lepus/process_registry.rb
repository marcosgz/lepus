# frozen_string_literal: true

module Lepus
  # Process registry that delegates to a configurable backend.
  # Default backend is FileBackend for local file-based storage.
  # Use RabbitmqBackend to share process data across apps via web dashboard.
  class ProcessRegistry
    class << self
      def backend
        @backend ||= Lepus.config.build_process_registry_backend
      end

      def backend=(value)
        @backend = value
      end

      def reset_backend!
        @backend = nil
      end

      def start
        backend.start
      end

      def stop
        backend.stop
      end

      def reset!
        stop
        start
      end

      def add(process)
        backend.add(process)
      end

      def update(process)
        backend.update(process)
      end

      def delete(process)
        backend.delete(process)
      end

      def find(id)
        backend.find(id)
      end

      def exists?(id)
        backend.exists?(id)
      end

      def all
        backend.all
      end

      def count
        backend.count
      end

      def clear
        backend.clear
      end

      # For backward compatibility with tests that check @path
      def path
        backend.respond_to?(:path) ? backend.path : nil
      end
    end
  end
end
