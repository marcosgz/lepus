# frozen_string_literal: true

module Lepus
  class ProcessRegistry
    # Abstract backend interface for process registry storage.
    # Implementations must provide all methods defined here.
    module Backend
      def start
        raise NotImplementedError, "#{self.class}#start must be implemented"
      end

      def stop
        raise NotImplementedError, "#{self.class}#stop must be implemented"
      end

      def add(process)
        raise NotImplementedError, "#{self.class}#add must be implemented"
      end

      def update(process, metrics: {})
        add(process, metrics: metrics)
      end

      def delete(process)
        raise NotImplementedError, "#{self.class}#delete must be implemented"
      end

      def find(id)
        raise NotImplementedError, "#{self.class}#find must be implemented"
      end

      def exists?(id)
        raise NotImplementedError, "#{self.class}#exists? must be implemented"
      end

      def all
        raise NotImplementedError, "#{self.class}#all must be implemented"
      end

      def count
        raise NotImplementedError, "#{self.class}#count must be implemented"
      end

      def clear
        raise NotImplementedError, "#{self.class}#clear must be implemented"
      end
    end
  end
end
