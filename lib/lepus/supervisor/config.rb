# frozen_string_literal: true

require "yaml"
require "logger"

module Lepus
  class Supervisor < Processes::Base
    class Config
      class Process < Struct.new(:process_class, :attributes)
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
        @consumers ||= Dir[Lepus.config.consumers_directory.join("**/*.rb")].map { |path| Pathname.new(path) }.map do |path|
          next unless path.extname == ".rb"
          next if File.readlines(path.to_s).grep(/abstract_class\s*=\s*true/).any?

          path.relative_path_from(Lepus.config.consumers_directory).to_s.sub(/\.rb$/, "").split("/").map do |part|
            part.split("_").collect(&:capitalize).join
          end.join("::")
        end.compact
      end

      protected

      def consumer_processes
        @consumer_processes ||= consumers.map do |class_name|
          Process.new(Lepus::Processes::Consumer, {class_name: class_name})
        end
      end
    end
  end
end
