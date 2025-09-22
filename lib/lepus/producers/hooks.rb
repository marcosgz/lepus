# frozen_string_literal: true

module Lepus
  module Producers
    module Hooks
      KEY = :lepus_producers

      def self.reset!
        Thread.current[KEY] = nil
      end

      # Global enable publishing callbacks. If no producer/exchange is specified, all producers will be enabled.
      # @param targets [Array<Lepus::Producer, String, Symbol>] Producer classes, exchange names, or both
      # @return [void]
      def enable!(*targets)
        if targets.empty?
          # Enable all producers
          all_producers.each { |producer| repo[:producers][producer] = true }
        else
          targets.each do |target|
            case target
            when Class
              ensure_producer_class(target)
              repo[:producers][target] = true
            when String, Symbol
              exchange_name = target.to_s
              repo[:exchanges][exchange_name] = true
            else
              raise ArgumentError, "Invalid producer or exchange name: #{target.inspect}"
            end
          end
        end
      end

      # Global disable publishing callbacks. If no producer/exchange is specified, all producers will be disabled.
      # @param targets [Array<Lepus::Producer, String, Symbol>] Producer classes, exchange names, or both
      # @return [void]
      def disable!(*targets)
        if targets.empty?
          # Disable all producers
          all_producers.each { |producer| repo[:producers][producer] = false }
        else
          targets.each do |target|
            case target
            when Class
              ensure_producer_class(target)
              repo[:producers][target] = false
            when String, Symbol
              exchange_name = target.to_s
              repo[:exchanges][exchange_name] = false
            else
              raise ArgumentError, "Invalid producer or exchange name: #{target.inspect}"
            end
          end
        end
      end

      # Check if the given producer is enabled for publishing. If no producer is specified, all producers will be checked.
      #
      # @param producers [Array<Lepus::Producer>]
      # @return [Boolean]
      def disabled?(*producers)
        if producers.empty?
          all_producers.all? { |producer| !producer_enabled?(producer) }
        else
          producers.all? { |producer| !producer_enabled?(producer) }
        end
      end

      # Check if the given producer is enabled for publishing. If no producer is specified, all producers will be checked.
      #
      # @param producers [Array<Lepus::Producer>]
      # @return [Boolean]
      def enabled?(*producers)
        if producers.empty?
          all_producers.all? { |producer| producer_enabled?(producer) }
        else
          producers.all? { |producer| producer_enabled?(producer) }
        end
      end

      # Check if the given exchange is enabled for publishing.
      #
      # @param exchange_name [String] The exchange name to check
      # @return [Boolean]
      def exchange_enabled?(exchange_name)
        # Check if exchange is explicitly configured
        if repo[:exchanges].key?(exchange_name)
          return repo[:exchanges][exchange_name]
        end

        # Find all producers that use this exchange
        matching_producers = all_producers.select do |producer|
          producer.definition&.exchange_name == exchange_name
        end

        # If no producers use this exchange, consider it enabled by default
        return true if matching_producers.empty?

        # Check if all matching producers are enabled
        matching_producers.all? { |producer| producer_enabled?(producer) }
      end

      # Disable publishing callbacks execution for the block execution.
      # Example:
      #  Lepus::Producers.without_publishing { User.create! }
      #  Lepus::Producers.without_publishing(UsersIndex, "exchange_name") { User.create! }
      def without_publishing(*targets)
        state_before_disable = deep_copy_repo
        disable!(*targets)

        yield
      ensure
        restore_repo(state_before_disable)
      end

      # Enable the publishing callbacks execution for the block execution.
      # Example:
      #  Lepus::Producers.with_publishing { User.create! }
      #  Lepus::Producers.with_publishing(UsersIndex, "exchange_name") { User.create! }
      def with_publishing(*targets)
        state_before_enable = deep_copy_repo
        enable!(*targets)

        yield
      ensure
        restore_repo(state_before_enable)
      end

      private

      def all_producers
        Lepus::Producer.descendants.reject(&:abstract_class?)
      end

      # Check if a specific producer is enabled
      def producer_enabled?(producer)
        repo[:producers][producer]
      end

      def ensure_producer_class(value)
        (value <= Lepus::Producer) ? value : raise(ArgumentError, "Invalid producer class: #{value.inspect}")
      end

      def deep_copy_repo
        {
          producers: repo[:producers].dup,
          exchanges: repo[:exchanges].dup
        }
      end

      def restore_repo(saved_state)
        Thread.current[KEY] = saved_state
      end

      # Data Structure:
      #
      # {
      #   producers: { <Lepus::Producer class> => <true|false>, ... },
      #   exchanges: { <String> => <true|false>, ... }
      # }
      def repo
        Thread.current[KEY] ||= {
          producers: all_producers.map { |k| [k, true] }.to_h,
          exchanges: {}
        }
      end
    end
  end
end
