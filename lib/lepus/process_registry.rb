# frozen_string_literal: true

require "singleton"

module Lepus
  class ProcessRegistry
    include Singleton

    def initialize
      @processes = ::Concurrent::Map.new
    end

    def add(process)
      @processes[process.id] = process
    end

    def delete(process)
      @processes.delete(process.id)
    end

    def find(id)
      @processes[id] || raise(Lepus::Process::NotFoundError.new(id))
    end

    def exists?(id)
      @processes.key?(id)
    end

    def all
      @processes.values
    end

    def clear
      @processes.clear
    end
  end
end
