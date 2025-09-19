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

      # Check if the given exchange is enabled for publishing.
      #
      # @param exchange_name [String] The exchange name to check
      # @return [Boolean]
      def exchange_enabled?(exchange_name)
        # Find all producers that use this exchange
        matching_producers = all_producers.select do |producer|
          producer.definition.exchange_name == exchange_name
        end

        # If no producers use this exchange, consider it enabled by default
        return true if matching_producers.empty?

        # Check if all matching producers are enabled
        matching_producers.all? { |producer| repo[producer] }
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

      # Returns a list of all producers for the given arguments
      # If no producer/exchange is specified, all producers will be returned.
      # @return [Array<*Lepus::Producer>] List of producers
      def filter_producers(*producers)
        return all_producers if producers.empty?

        expanded = expand_given_producers(*producers)
        # Separate Producer classes from exchange names
        producer_classes = expanded.select { |item| item.is_a?(Class) }
        exchange_names = expanded.select { |item| item.is_a?(String) }

        # For Producer classes, filter by actual descendants
        filtered_producers = producer_classes & all_producers

        # For exchange names, find matching producers
        matching_producers = all_producers.select do |producer|
          exchange_names.include?(producer.definition.exchange_name)
        end

        # Combine both lists and remove duplicates
        (filtered_producers + matching_producers).uniq
      end

      def expand_given_producers(*producers)
        producers.flat_map do |value|
          case value
          when Class
            ensure_producer_class(value)
          when String, Symbol
            value.to_s
          else
            raise ArgumentError, "Invalid producer or exchange name: #{value.inspect}"
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
