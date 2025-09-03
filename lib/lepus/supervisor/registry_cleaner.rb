# frozen_string_literal: true

module Lepus
  class Supervisor < Processes::Base
    module RegistryCleaner
      def self.included(base)
        base.send :include, InstanceMethods
        base.class_eval do
          after_shutdown :cleanup_registry
        end
      end

      module InstanceMethods
        private

        def cleanup_registry
          ProcessRegistry.stop
        end
      end
    end
  end
end
