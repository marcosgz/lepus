# frozen_string_literal: true

require "pathname"
require "tmpdir"

module Lepus
  # we are storing the process registry in a file using Marshal serialization
  # but the plan is to move to a Rabbitmq or Redis based implementation in the future
  # to let it available to outside services like the web dashboard.
  # I'll refactor this class later when we have a better idea of the requirements.
  class ProcessRegistry
    class << self
      attr_reader :path

      def start
        @path ||= Pathname.new(Dir.tmpdir).join("lepus_process_registry.store")
      end

      def stop
        path.delete if path&.exist?
      end

      def reset!
        stop
        start
      end

      def add(process)
        transaction do |data|
          data[process.id] = process.to_h
        end
      end
      alias_method :update, :add

      def delete(process)
        transaction do |data|
          data.delete(process.id)
        end
      end

      def find(id)
        raw = read.fetch(id) { raise(Lepus::Process::NotFoundError.new(id)) }
        Lepus::Process.coerce(raw)
      end

      def exists?(id)
        read.key?(id)
      end

      def all
        read.keys.map { |id| find(id) }
      end

      def count
        return 0 unless path

        read.size
      end

      def clear
        return unless path

        write({})
      end

      private

      def transaction
        data = read
        yield data
        write(data)
      end

      def read
        with_lock(File::LOCK_SH) do |f|
          f.size.zero? ? {} : Marshal.load(f)
        end
      end

      def write(data)
        with_lock(File::LOCK_EX) do |f|
          f.rewind
          f.truncate(0)
          f.write(Marshal.dump(data))
          f.flush
        end
      end

      def with_lock(lock_type)
        unless path
          raise "ProcessRegistry not started. Call Lepus::ProcessRegistry.start first."
        end
        File.open(path, File::RDWR | File::CREAT, 0o644) do |f|
          f.flock(lock_type)
          result = yield f
          f.flock(File::LOCK_UN)
          result
        end
      end
    end
  end
end
