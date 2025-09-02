# frozen_string_literal: true

module Lepus::Processes
  # Provides callback functionality for process lifecycle events.
  #
  # Usage:
  # class MyProcess
  #   extend Lepus::Processes::Callbacks[:boot, :shutdown]
  #
  #   before_boot :prepare_resources
  #   after_shutdown :cleanup_resources
  # class Callbacks < Module
  #   def self.[](*names)
  #     new(*names)
  #   end

  #   def initialize(*names)
  #     @names = names
  #   end

  #   def extended(base)
  #     @names.each do |name|
  #       base.instance_variable_set(:"@_callbacks_for_#{name}", { before: [], after: [] })
  #       base.class_eval <<-RUBY, __FILE__, __LINE__ + 1
  #         def self.before_#{name}(*methods, &block)
  #           _callbacks_for_#{name}[:before].concat(methods) if methods.any?
  #           _callbacks_for_#{name}[:before] << block if block
  #         end

  #         def self.after_#{name}(*methods, &block)
  #           _callbacks_for_#{name}[:after].concat(methods) if methods.any?
  #           _callbacks_for_#{name}[:after] << block if block
  #         end

  #         def self.callbacks_for_#{name}_type(type)
  #           _callbacks_for_#{name}[type] || []
  #         end

  #         def self._callbacks_for_#{name}
  #           @_callbacks_for_#{name} #||= { before: [], after: [] }
  #         end

  #         def self.inherited(subclass)
  #           if instance_variable_defined?(:"@_callbacks_for_#{name}")
  #             sub_value = instance_variable_get(:"@_callbacks_for_#{name}")
  #             subclass.instance_variable_set(:"@_callbacks_for_#{name}", { before: sub_value[:before].dup, after: sub_value[:after].dup })
  #           end
  #           super
  #         end

  #         private_class_method :_callbacks_for_#{name}

  #         def run_#{name}_callbacks
  #           self.class.send(:"callbacks_for_#{name}_type", :before).each do |method_or_proc|
  #             method_or_proc.is_a?(Proc) ? method_or_proc.call : send(method_or_proc)
  #           end
  #           result = yield if block_given?
  #           self.class.send(:"callbacks_for_#{name}_type", :after).each do |method_or_proc|
  #             method_or_proc.is_a?(Proc) ? method_or_proc.call : send(method_or_proc)
  #           end
  #           result
  #         end

  #       RUBY
  #     end
  #   end
  # end

  module Callbacks
    def self.included(base)
      base.extend(ClassMethods)
      base.send :include, InstanceMethods
    end

    module InstanceMethods
      def run_process_callbacks(name)
        self.class.send(:"before_#{name}_callbacks").each do |method|
          send(method)
        end

        result = yield if block_given?

        self.class.send(:"after_#{name}_callbacks").each do |method|
          send(method)
        end

        result
      end
    end

    module ClassMethods
      def inherited(base)
        base.instance_variable_set(:@before_boot_callbacks, before_boot_callbacks.dup)
        base.instance_variable_set(:@after_boot_callbacks, after_boot_callbacks.dup)
        base.instance_variable_set(:@before_shutdown_callbacks, before_shutdown_callbacks.dup)
        base.instance_variable_set(:@after_shutdown_callbacks, after_shutdown_callbacks.dup)
        super
      end

      def before_boot(*methods)
        @before_boot_callbacks ||= []
        @before_boot_callbacks.concat methods
      end

      def after_boot(*methods)
        @after_boot_callbacks ||= []
        @after_boot_callbacks.concat methods
      end

      def before_shutdown(*methods)
        @before_shutdown_callbacks ||= []
        @before_shutdown_callbacks.concat methods
      end

      def after_shutdown(*methods)
        @after_shutdown_callbacks ||= []
        @after_shutdown_callbacks.concat methods
      end

      private

      def before_boot_callbacks
        @before_boot_callbacks || []
      end

      def after_boot_callbacks
        @after_boot_callbacks || []
      end

      def before_shutdown_callbacks
        @before_shutdown_callbacks || []
      end

      def after_shutdown_callbacks
        @after_shutdown_callbacks || []
      end
    end
  end
end
