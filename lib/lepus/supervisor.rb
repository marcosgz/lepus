# frozen_string_literal: true

module Lepus
  class Supervisor < Processes::Base
    include LifecycleHooks
    include Maintenance
    include Signals
    include Pidfiled

    class << self
      def start(**options)
        # Lepus.config.supervisor = true
        config = Config.new(**options)
        new(config).tap(&:start)
      end
    end

    def initialize(configuration)
      @configuration = configuration
      @forks = {}
      @configured_processes = {}
      ProcessRegistry.instance # Ensure the registry is initialized
    end

    def start
      boot

      run_start_hooks

      start_processes
      launch_maintenance_task

      supervise
    end

    def stop
      super
      run_stop_hooks
    end

    private

    attr_reader :configuration, :forks, :configured_processes

    def boot
      Lepus.instrument(:start_process, process: self) do
        if configuration.require_file
          Kernel.require configuration.require_file
        else
          begin
            require "rails"
            require_relative "rails"
            require File.expand_path("config/environment", Dir.pwd)
          rescue LoadError
            # Rails not found
          end
        end

        setup_consumers
        check_bunny_connection

        run_process_callbacks(:boot) do
          sync_std_streams
        end
      end
    end

    def setup_consumers
      Lepus.eager_load_consumers!

      if configuration.consumers.empty?
        abort "No consumers found. Exiting..."
      end
    end

    def check_bunny_connection
      temp_bunny = Lepus.config.create_connection(suffix: "(boot-check)")
      temp_bunny.close
    end

    def start_processes
      configuration.configured_processes.each do |configured_process|
        start_process(configured_process)
      end
    end

    def supervise
      loop do
        break if stopped?

        set_procline
        process_signal_queue

        unless stopped?
          reap_and_replace_terminated_forks
          interruptible_sleep(1)
        end
      end
    ensure
      shutdown
    end

    def start_process(configured_process)
      process_instance = configured_process.instantiate.tap do |instance|
        instance.supervised_by process
        instance.mode = :fork
      end

      process_instance.before_fork
      pid = fork do
        process_instance.after_fork
        process_instance.start
      end

      configured_processes[pid] = configured_process
      forks[pid] = process_instance
    end

    def set_procline
      procline "supervising #{supervised_processes.join(", ")}"
    end

    def terminate_gracefully
      Lepus.instrument(:graceful_termination, process_id: process_id, supervisor_pid: ::Process.pid, supervised_processes: supervised_processes) do |payload|
        term_forks

        shutdown_timeout = 5
        puts "\nWaiting up to #{shutdown_timeout} seconds for processes to terminate gracefully..."
        Timer.wait_until(shutdown_timeout, -> { all_forks_terminated? }) do
          reap_terminated_forks
        end

        unless all_forks_terminated?
          payload[:shutdown_timeout_exceeded] = true
          terminate_immediately
        end
      end
    end

    def terminate_immediately
      Lepus.instrument(:immediate_termination, process_id: process_id, supervisor_pid: ::Process.pid, supervised_processes: supervised_processes) do
        quit_forks
      end
    end

    def shutdown
      Lepus.instrument(:shutdown_process, process: self) do
        run_process_callbacks(:shutdown) do
          stop_maintenance_task
        end
      end
    end

    def sync_std_streams
      $stdout.sync = $stderr.sync = true
    end

    def supervised_processes
      forks.keys
    end

    def term_forks
      signal_processes(forks.keys, :TERM)
    end

    def quit_forks
      signal_processes(forks.keys, :QUIT)
    end

    def reap_and_replace_terminated_forks
      loop do
        pid, status = ::Process.waitpid2(-1, ::Process::WNOHANG)
        break unless pid

        replace_fork(pid, status)
      end
    end

    def reap_terminated_forks
      loop do
        pid, _ = ::Process.waitpid2(-1, ::Process::WNOHANG)
        break unless pid

        configured_processes.delete(pid)
      end
    rescue SystemCallError
      # All children already reaped
    end

    def replace_fork(pid, status)
      Lepus.instrument(:replace_fork, supervisor_pid: ::Process.pid, pid: pid, status: status) do |payload|
        if (terminated_fork = forks.delete(pid))
          payload[:fork] = terminated_fork

          start_process(configured_processes.delete(pid))
        end
      end
    end

    def all_forks_terminated?
      forks.empty?
    end
  end
end
