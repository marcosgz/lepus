# frozen_string_literal: true

module Lepus
  class Process
    class NotFoundError < RuntimeError
      def initialize(id)
        super("Process with id #{id} not found")
      end
    end

    ATTRIBUTES = %i[id name pid hostname kind last_heartbeat_at supervisor_id].freeze

    class << self
      def register(**attributes)
        attributes[:id] ||= SecureRandom.uuid
        Lepus.instrument :register_process, **attributes do |payload|
          new(**attributes).tap do |process|
            ProcessRegistry.add(process)
            payload[:process_id] = process.id
          end
        rescue Exception => error # rubocop:disable Lint/RescueException
          payload[:error] = error
          raise
        end
      end

      def prune(excluding: nil)
        Lepus.instrument :prune_processes, size: 0 do |payload|
          arr = prunable
          arr.delete(excluding) if excluding
          payload[:size] = arr.size

          arr.each(&:prune)
        end
      end

      def prunable
        ProcessRegistry.all.select do |process|
          process.last_heartbeat_at && process.last_heartbeat_at < Time.now - Lepus.config.process_alive_threshold
        end
      end

      def coerce(raw)
        new(**raw.transform_keys(&:to_sym))
      end
    end

    attr_reader :attributes

    def initialize(**attributes)
      @attributes = attributes
      @attributes[:id] ||= SecureRandom.uuid
    end

    def to_h
      attributes
    end

    ATTRIBUTES.each do |attribute|
      define_method(attribute) { attributes[attribute] }
    end

    def last_heartbeat_at
      attributes[:last_heartbeat_at]
    end

    def rss_memory
      Processes::MEMORY_GRABBER.call(pid)
    end

    def heartbeat
      now = Time.now
      Lepus.instrument :heartbeat_process, process: self, rss_memory: 0, last_heartbeat_at: now do |payload|
        ProcessRegistry.find(id) # ensure process is still registered

        update_attributes(last_heartbeat_at: now)
        payload[:rss_memory] = rss_memory
      rescue Exception => error # rubocop:disable Lint/RescueException
        payload[:error] = error
        raise
      end
    end

    def update_attributes(new_attributes)
      @attributes = @attributes.merge(new_attributes)
      ProcessRegistry.update(self)
    end

    def destroy!
      Lepus.instrument :destroy_process, process: self do |payload|
        ProcessRegistry.delete(self)
      rescue Exception => error # rubocop:disable Lint/RescueException
        payload[:error] = error
        raise
      end
    end

    def deregister(pruned: false)
      Lepus.instrument :deregister_process, process: self, pruned: pruned do |payload|
        destroy!

        unless supervised? || pruned
          supervisees.each(&:deregister)
        end
      rescue Exception => error # rubocop:disable Lint/RescueException
        payload[:error] = error
        raise
      end
    end

    def prune
      deregister(pruned: true)
    end

    def supervised?
      !attributes[:supervisor_id].nil?
    end

    def eql?(other)
      other.is_a?(self.class) && other.id == id && other.pid == pid
    end
    alias_method :==, :eql?

    private

    def supervisees
      ProcessRegistry.all.select { |process| process.supervisor_id == id }
    end
  end
end
