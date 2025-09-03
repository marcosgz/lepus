# frozen_string_literal: true

module Lepus
  class Supervisor < Processes::Base
    module ChildrenPipes
      def self.included(base)
        base.send :include, InstanceMethods
        base.class_eval do
          after_shutdown :close_pipes
        end
      end

      module InstanceMethods
        private

        def close_pipes
          pipes.each_value do |pipe|
            pipe.close if pipe && !pipe.closed?
          end
          @pipes = {}
        end
      end
    end
  end
end
