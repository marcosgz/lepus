# frozen_string_literal: true

module Lepus
  class Supervisor < Processes::Base
    include LifecycleHooks
    include Maintenance
    include Signals
    include Pidfiled

    class << self
      def start(**options)
        new(**options).tap(&:start)
      end
    end

    # @param require_file [String, nil] The file to require before loading consumers, typically the Rails environment file or similar.
    # @param pidfile [String] The path to the pidfile where the supervisor's PID will be stored. Default is "tmp/pids/lepus.pid".
    # @param shutdown_timeout [Integer] The timeout in seconds to wait for child processes to terminate gracefully before forcing termination. Default is 5 seconds.
    # @param consumers [Array<String, Class>] An optional list of consumer class names (as strings or constants) to be run by this supervisor. If not provided, all discovered consumer classes will be used.
    def initialize(require_file: nil, pidfile: "tmp/pids/lepus.pid", shutdown_timeout: 5, **kwargs)
      @pidfile_path = pidfile
      @require_file = require_file
      @shutdown_timeout = shutdown_timeout.to_i
      @consumer_class_names = Array(kwargs[:consumers]).map(&:to_s) if kwargs.key?(:consumers)

      @forks = {}
      @configured_processes = {}
      ProcessRegistry.instance # Ensure the registry is initialized

      super
    end

    def start
      boot

      run_start_hooks

      build_and_start_processes
      launch_maintenance_task

      supervise
    end

    def stop
      super

      run_stop_hooks
    end

    private

    # @return [String] The raw location of the pidfile used to store the supervisor's `#pidfile`.
    attr_reader :pidfile_path

    # @return [String] The file to require before loading consumers, typically the Rails environment file or similar.
    attr_reader :require_file

    # @return [Integer] The timeout in seconds to wait for child processes to terminate gracefully before forcing termination.
    attr_reader :shutdown_timeout

    # @return [Hash{Integer[pid] => Lepus::ConsumersProcess}] map of forked process IDs to their instances
    attr_reader :forks

    # @return [Hash{Integer[pid] => Lepus::Consumers::ProcessFactory}] map of forked process IDs to their immutable factory configurations
    attr_reader :configured_processes

    # @return [Array<Lepus::Consumer>] the full list of consumer classes to be run by this supervisor and its child processes.
    def consumer_classes
      @consumer_classes ||= if @consumer_class_names
        @consumer_class_names.map { |name| Lepus::Primitive::String.new(name).constantize }
      else
        Lepus::Consumer.descendants
      end.reject(&:abstract_class?)
    end

    def boot
      Lepus.instrument(:start_process, process: self) do
        if require_file
          Kernel.require(require_file)
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

      if consumer_classes.empty?
        abort "No consumers found. Exiting..."
      end

      consumer_classes.each do |consumer_class|
        if consumer_class.config.nil?
          abort <<~MSG
            Consumer class #{klass} is not configured. Please use the `configure' class method
            to set at least the queue name.

            Example:

              class MyConsumer < Lepus::Consumer
                configure queue: "my_queue"
              end
          MSG
        end
      end
    end

    def check_bunny_connection
      temp_bunny = Lepus.config.create_connection(suffix: "(boot-check)")
      temp_bunny.close
    end

    def build_and_start_processes
      consumer_classes.group_by { |klass| klass.config.process_name }.map do |process_name, classes|
        frozen_factory = Lepus::Consumers::ProcessFactory.immutate_with(process_name, consumers: classes)
        start_process(frozen_factory)
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

    def start_process(factory)
      process_instance = factory.instantiate_process
      process_instance.supervised_by(process)
      process_instance.mode = :fork

      # process_instance.before_fork
      pid = fork do
        # process_instance.after_fork
        process_instance.start
      end

      configured_processes[pid] = factory
      forks[pid] = process_instance
    end

    def set_procline
      procline "supervising #{supervised_processes.join(", ")}"
    end

    def terminate_gracefully
      Lepus.instrument(:graceful_termination, process_id: process_id, supervisor_pid: ::Process.pid, supervised_processes: supervised_processes) do |payload|
        term_forks

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
        pid, status = ::Process.waitpid2(-1, ::Process::WNOHANG)
        break unless pid

        if (terminated_fork = forks.delete(pid))
          puts "Process #{pid} (#{terminated_fork.name}) terminated with status #{status.exitstatus}"
        end

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
