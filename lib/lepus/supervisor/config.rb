# frozen_string_literal: true

require "yaml"
require "logger"

module Lepus
  class Supervisor < Processes::Base
    class Config
      class ProcessStruct < Struct.new(:process_class, :attributes)
        def instantiate
          process_class.new(**attributes)
        end
      end

      attr_accessor :pidfile, :require_file

      def initialize(require_file: nil, pidfile: "tmp/pids/lepus.pid", **kwargs)
        @pidfile = pidfile
        @require_file = require_file
        self.consumers = kwargs[:consumers] if kwargs.key?(:consumers)
      end

      def configured_processes
        consumer_processes
      end

      def consumers=(vals)
        @consumer_processes = nil
        @consumers = Array(vals).map(&:to_s)
      end

      def consumers
        @consumers ||= Lepus::Consumer.descendants.reject(&:abstract_class?).map(&:name).compact
      end

      protected

      def consumer_processes
        @consumer_processes ||= consumers.map do |class_name|
          ProcessStruct.new(Lepus::Processes::ChildrenProcess, {class_name: class_name})
        end
      end
    end
  end
end
