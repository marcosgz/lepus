# frozen_string_literal: true

module Lepus
  class Supervisor < Processes::Base
    module Pidfiled
      def self.included(base)
        base.send :include, InstanceMethods
        base.class_eval do
          before_boot :setup_pidfile
          after_shutdown :delete_pidfile
        end
      end

      module InstanceMethods
        private

        def setup_pidfile
          if (path = pidfile_path)
            @pidfile = Pidfile.new(path).tap(&:setup)
          end
        end

        def delete_pidfile
          @pidfile&.delete
        end
      end
    end
  end
end
