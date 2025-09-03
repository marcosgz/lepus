# frozen_string_literal: true

module Lepus
  class Supervisor < Processes::Base
    SHUTDOWN_MSG = "☠️".freeze

    include LifecycleHooks
    include ChildrenPipes
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
      @pipes = {}
      @configured_processes = {}
      ProcessRegistry.instance # Ensure the registry is initialized

      super
    end

    def start
      boot

      run_start_hooks

      build_and_start_workers
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

    # @return [Hash{Integer[pid] => Lepus::Consumers::Worker}] map of forked process IDs to their instances
    attr_reader :forks

    # @return [Hash{Integer[pid] => Lepus::Consumers::WorkerFactory}] map of forked process IDs to their immutable factory configurations
    attr_reader :configured_processes

    # @return [Hash{Integer[pid] => IO}] map of forked process IDs to their communication pipes
    attr_reader :pipes

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

    def build_and_start_workers
      consumer_classes.group_by { |klass| klass.config.worker_name }.map do |worker_name, classes|
        frozen_factory = Lepus::Consumers::WorkerFactory.immutate_with(worker_name, consumers: classes)
        start_process(frozen_factory)
      end
    end

    def supervise
      loop do
        break if stopped?

        set_procline
        process_signal_queue

        unless stopped?
          check_for_shutdown_messages
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

      reader, writer = IO.pipe
      process_instance.before_fork
      pid = fork do
        reader.close
        begin
          process_instance.after_fork
          process_instance.start
        rescue Lepus::ShutdownError
          writer.puts(SHUTDOWN_MSG)
          raise
        ensure
          writer.close
        end
      end

      configured_processes[pid] = factory
      forks[pid] = process_instance
      pipes[pid] = reader
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

    def check_for_shutdown_messages
      open_pipes = pipes.values.reject(&:closed?)
      return if open_pipes.empty?

      # Check if any pipe has data available to read without blocking
      ready_pipes, = IO.select(open_pipes, nil, nil, 0)
      return unless ready_pipes

      ready_pipes.each do |pipe|
        begin
          message = pipe.gets&.chomp
          initiate_shutdown_sequence_from_child(pipe) if message == SHUTDOWN_MSG
        rescue IOError, Errno::EPIPE
          # Pipe was closed or broken, clean it up
        end
      end
    rescue IOError
      # Handle any IO errors during select
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

        pipes.delete(pid)&.close
        forks.delete(pid)
        configured_processes.delete(pid)
      end
    rescue SystemCallError
      # All children already reaped
    end

    def replace_fork(pid, status)
      Lepus.instrument(:replace_fork, supervisor_pid: ::Process.pid, pid: pid, status: status) do |payload|

        pipes.delete(pid)&.close
        if (terminated_fork = forks.delete(pid))
          payload[:fork] = terminated_fork

          start_process(configured_processes.delete(pid))
        end
      end
    end

    def all_forks_terminated?
      forks.empty?
    end

    def initiate_shutdown_sequence_from_child(pipe)
      if (pid = pipes.key(pipe))
        pipes.delete(pid)
        forks.delete(pid)
        configured_processes.delete(pid)
      end
      pipe.close
      quit_forks
      stop
    end

  end
end
