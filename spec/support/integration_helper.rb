# frozen_string_literal: true

require "singleton"
require "concurrent"
require "fileutils"
require "json"
require "timeout"

module IntegrationHelper
  # Thread-safe registry to track processed messages (for inline mode)
  class ProcessedMessages
    include Singleton

    def initialize
      @messages = Concurrent::Array.new
      @latch = nil
    end

    def record(consumer_class, message, result)
      @messages << {
        consumer: consumer_class,
        payload: message.payload,
        metadata: message.metadata,
        result: result,
        at: Time.now
      }
      @latch&.count_down
    end

    def wait_for(count, timeout: 5)
      @latch = Concurrent::CountDownLatch.new(count)
      @latch.wait(timeout)
    end

    def clear!
      @messages.clear
      @latch = nil
    end

    def all
      @messages.dup
    end

    def size
      @messages.size
    end

    def for_consumer(klass)
      @messages.select { |m| m[:consumer] == klass }
    end
  end

  # ConsumerHandle - returned by start_consumer_inline
  class ConsumerHandle
    attr_reader :consumer_class, :handler

    def initialize(connection:, channel:, handler:, consumer_class:)
      @connection = connection
      @channel = channel
      @handler = handler
      @consumer_class = consumer_class
    end

    def stop
      @handler.cancel
      @channel.close
      @connection.close
    end
  end

  # Start consumer inline (same process, threaded via Bunny)
  # Mirrors Worker#setup_consumers! logic from lib/lepus/consumers/worker.rb:86-126
  def start_consumer_inline(consumer_class)
    config = consumer_class.config

    connection = Bunny.new(Lepus.config.rabbitmq_url)
    connection.start

    channel = connection.create_channel(*config.channel_args)
    channel.basic_qos(config.prefetch_count) if config.prefetch_count

    exchange = channel.exchange(config.exchange_name, **config.exchange_options)

    # Declare retry queue if configured
    channel.queue(*config.retry_queue_args) if config.retry_queue_args
    # Declare error queue if configured
    channel.queue(*config.error_queue_args) if config.error_queue_args

    main_queue = channel.queue(*config.consumer_queue_args)
    config.binds_args.each { |opts| main_queue.bind(exchange, **opts) }

    handler = Lepus::Consumers::Handler.new(
      consumer_class, channel, main_queue, "test-#{consumer_class.object_id}"
    )
    handler.on_delivery do |delivery_info, metadata, payload|
      handler.process_delivery(delivery_info, metadata, payload)
    end
    main_queue.subscribe_with(handler)

    ConsumerHandle.new(
      connection: connection, channel: channel,
      handler: handler, consumer_class: consumer_class
    )
  end

  def stop_consumer_inline(handle)
    handle&.stop
  end

  # Cleanup RabbitMQ resources for a consumer
  def cleanup_rabbitmq_for(consumer_class)
    config = consumer_class.config
    with_rabbitmq_connection do |conn|
      ch = conn.create_channel
      ch.queue_delete(config.queue_name) rescue Bunny::NotFound
      if config.retry_queue_args
        ch.queue_delete(config.retry_queue_name) rescue Bunny::NotFound
      end
      if config.error_queue_args
        ch.queue_delete(config.error_queue_name) rescue Bunny::NotFound
      end
      ch.exchange_delete(config.exchange_name) rescue Bunny::NotFound
    end
  end

  def with_rabbitmq_connection
    conn = Bunny.new(Lepus.config.rabbitmq_url)
    conn.start
    yield conn
  ensure
    conn&.close
  end

  # Wait helper with timeout
  def wait_until(timeout: 5, interval: 0.05)
    deadline = Time.now + timeout
    until yield
      return false if Time.now > deadline
      sleep interval
    end
    true
  end

  # ============================================
  # FORKED MODE - For realistic process testing
  # ============================================

  # File-based message tracking for forked processes
  class FileBasedMessageTracker
    TRACKER_DIR = File.expand_path("../../tmp/integration", __dir__)

    class << self
      def tracker_file
        FileUtils.mkdir_p(TRACKER_DIR)
        File.join(TRACKER_DIR, "processed_messages.json")
      end

      def record(consumer_class, payload, result)
        # Use file locking to handle concurrent writes
        File.open(tracker_file, File::RDWR | File::CREAT) do |f|
          f.flock(File::LOCK_EX)
          data = begin
            content = f.read
            content.empty? ? [] : JSON.parse(content)
          rescue JSON::ParserError
            []
          end

          data << {
            consumer: consumer_class.to_s,
            payload: payload,
            result: result.to_s,
            at: Time.now.to_s
          }

          f.rewind
          f.truncate(0)
          f.write(JSON.generate(data))
        end
      end

      def read_all
        return [] unless File.exist?(tracker_file)
        JSON.parse(File.read(tracker_file))
      rescue JSON::ParserError
        []
      end

      def clear!
        File.delete(tracker_file) if File.exist?(tracker_file)
      end

      def wait_for(count, timeout: 10)
        deadline = Time.now + timeout
        loop do
          return true if read_all.size >= count
          return false if Time.now > deadline
          sleep 0.1
        end
      end
    end
  end

  # WorkerHandle - returned by start_worker_as_fork
  class WorkerHandle
    attr_reader :pid, :consumer_classes

    def initialize(pid:, consumer_classes:)
      @pid = pid
      @consumer_classes = consumer_classes
    end

    def stop(timeout: 5)
      Process.kill(:TERM, @pid)
      Timeout.timeout(timeout) { Process.waitpid(@pid) }
    rescue Errno::ESRCH, Errno::ECHILD
      # Process already gone
    rescue Timeout::Error
      Process.kill(:KILL, @pid) rescue nil
      Process.waitpid(@pid) rescue nil
    end
  end

  # Start a worker with specific consumers in a forked process
  # Uses WorkerFactory to create a proper worker like production
  def start_worker_as_fork(*consumer_classes, name: "integration-test")
    # Create an immutable factory with the specified consumers
    factory = Lepus::Consumers::WorkerFactory.immutate_with(name, consumers: consumer_classes)
    worker = factory.instantiate_process
    # Set mode to fork (like Supervisor does) - this makes run() execute synchronously
    worker.mode = :fork

    pid = fork do
      # In child process
      $0 = "lepus-integration-test-worker"
      # Start the ProcessRegistry (normally done by Supervisor)
      Lepus::ProcessRegistry.start
      begin
        worker.start
      rescue => e
        warn "[INTEGRATION TEST] Worker error: #{e.message}"
        warn e.backtrace.first(5).join("\n")
      ensure
        Lepus::ProcessRegistry.stop
      end
    end

    # Wait for worker to be ready (queue subscribed)
    sleep 1

    WorkerHandle.new(pid: pid, consumer_classes: consumer_classes)
  end

  def stop_worker_fork(handle, timeout: 5)
    handle&.stop(timeout: timeout)
  end
end
