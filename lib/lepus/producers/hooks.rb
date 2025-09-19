# frozen_string_literal: true

module Lepus
  module Producers
    module Hooks
      KEY = :lepus_producers

      def self.reset!
        Thread.current[KEY] = nil
      end

      # Global enable publishing callbacks. If no producer is specified, all producers will be enabled.
      # @param producers [Array<Lepus::Producer>]
      # @return [void]
      def enable!(*producers)
        filter_producers(*producers).each do |producer|
          repo[producer] = true
        end
      end

      # Global disable publishing callbacks. If no producer is specified, all producers will be disabled.
      # @param producers [Array<Lepus::Producer>]
      # @return [void]
      def disable!(*producers)
        filter_producers(*producers).each do |producer|
          repo[producer] = false
        end
      end

      # Check if the given producer is enabled for publishing. If no producer is specified, all producers will be checked.
      #
      # @param producers [Array<Lepus::Producer>]
      # @return [Boolean]
      def disabled?(*producers)
        filter_producers(*producers).all? { |producer| !repo[producer] }
      end

      # Check if the given producer is enabled for publishing. If no producer is specified, all producers will be checked.
      #
      # @param producers [Array<Lepus::Producer>]
      # @return [Boolean]
      def enabled?(*producers)
        filter_producers(*producers).all? { |producer| repo[producer] }
      end

      # Disable publishing callbacks execution for the block execution.
      # Example:
      #  Lepus::Producers.without_publishing { User.create! }
      #  Lepus::Producers.without_publishing(UsersIndex, AccountsIndex.producer(:user)) { User.create! }
      def without_publishing(*producers)
        state_before_disable = repo.dup
        disable!(*producers)

        yield
      ensure
        repo.replace(state_before_disable)
      end

      # Enable the publishing callbacks execution for the block execution.
      # Example:
      #  Lepus::Producers.with_publishing { User.create! }
      #  Lepus::Producers.with_publishing(UsersIndex, AccountsIndex.producer(:user)) { User.create! }
      def with_publishing(*producers)
        state_before_enable = repo.dup
        enable!(*producers)

        yield
      ensure
        repo.replace(state_before_enable)
      end

      private

      def all_producers
        Lepus::Producer.descendants.reject(&:abstract_class?)
      end

      # Returns a list of all producers for the given model
      # If no producer is specified, all producers will be returned.
      # @return [Array<*Lepus::Producer>] List of producers
      def filter_producers(*producers)
        return all_producers if producers.empty?

        expand_given_producers(*producers) & all_producers
      end

      def expand_given_producers(*producers)
        producers.flat_map do |value|
          case value
          when Class
            ensure_producer_class(value)
          when String, Symbol
            constant = Primitive::String.new(value.to_s).classify.constantize
            ensure_producer_class(constant)
          else
            raise ArgumentError, "Invalid producer name: #{value.inspect}"
          end
        end
      end

      def ensure_producer_class(value)
        value <= Lepus::Producer ? value : raise(ArgumentError, "Invalid producer class: #{value.inspect}")
      end

      # Data Structure:
      #
      # { <Lepus::Producer class> => <true|false>, ... }
      def repo
        Thread.current[KEY] ||= all_producers.map { |k| [k, true] }.to_h
      end
    end
  end
end
