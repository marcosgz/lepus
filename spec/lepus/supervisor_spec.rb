# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lepus::Supervisor do
  subject(:supervisor) { described_class.new(**options) }

  let(:pidfile) { lepus_root.join("tmp/pids/lepus_#{SecureRandom.hex}.pid") }
  let(:options) do
    {
      pidfile: pidfile
    }
  end

  after do
    reset_config!
    File.delete(pidfile) if File.exist?(pidfile)
  end

  describe "#initialize" do
    let(:options) { {} }

    it "returns the default pidfile" do
      expect(supervisor.send(:pidfile_path)).to eq("tmp/pids/lepus.pid")
    end

    it "sets a custom pidfile" do
      supervisor = described_class.new(pidfile: "custom/pidfile.pid")
      expect(supervisor.send(:pidfile_path)).to eq("custom/pidfile.pid")
    end

    it "sets the require_file" do
      expect(supervisor.send(:require_file)).to be_nil

      supervisor = described_class.new(require_file: "config/environment")
      expect(supervisor.send(:require_file)).to eq("config/environment")
    end

    it "sets the @consumer_class_names" do
      supervisor = described_class.new(consumers: ["MyConsumer"])
      expect(supervisor.instance_variable_get(:@consumer_class_names)).to eq(["MyConsumer"])
    end
  end

  describe "#start" do
    let(:consumer) do
      Class.new(Lepus::Consumer) do
        configure(queue: "test_queue", exchange: "test_exchange")
      end
    end
    let(:options) do
      {
        pidfile: pidfile,
        consumers: ["TestConsumer"]
      }
    end

    before do
      stub_const("TestConsumer", consumer)
    end

    it "start and stop supervisor process" do
      allow_any_instance_of(Lepus::Consumers::Worker).to receive(:setup_consumers!).and_return(true)
      pid = run_as_fork(supervisor)
      wait_for_registered_processes(2)

      workers = Lepus::ProcessRegistry.all.select { |p| p.kind == "Worker" }
      expect(workers.size).to eq(1)

      terminate_process(pid)
      expect(process_exists?(pid)).to be(false)
    end

    it "creates and removes the pidfile" do
      allow_any_instance_of(Lepus::Consumers::Worker).to receive(:setup_consumers!).and_return(true)

      pid = run_as_fork(supervisor)
      wait_for_registered_processes(1)
      expect(File.exist?(pidfile)).to be(true)
      terminate_process(pid)
      expect(File.exist?(pidfile)).to be(false)
    end

    it "aborts if pidfile exists" do
      allow_any_instance_of(Lepus::Consumers::Worker).to receive(:setup_consumers!).and_return(true)

      FileUtils.mkdir_p(pidfile.dirname)
      File.write(pidfile, ::Process.pid.to_s)
      expect(File.exist?(pidfile)).to be(true)

      pid, _out, err = run_supervisor_as_fork_with_captured_io(supervisor)
      expect(err).to include("A supervisor is already running")

      wait_for_process_termination_with_timeout(pid, exitstatus: 1)
    end

    it "aborts if require_file does not exist" do
      supervisor = described_class.new(require_file: "nonexistent_file.rb", pidfile: pidfile)
      pid, _out, err = run_supervisor_as_fork_with_captured_io(supervisor)
      expect(err).to include("cannot load such file")
      wait_for_process_termination_with_timeout(pid, exitstatus: 1)
    end

    it "terminate supervisor if Bunny connection fails" do
      allow_any_instance_of(Lepus::Consumers::Worker).to receive(:setup_consumers!).and_raise(Bunny::PreconditionFailed.new("Connection failed", double, double))

      pid, _, err = run_supervisor_as_fork_with_captured_io(supervisor)
      expect(err).to include("Connection failed")
      wait_for_process_termination_with_timeout(pid, exitstatus: 1)
    end

    it "terminate supervisor if some consumer is misconfigured" do
      allow_any_instance_of(Lepus::Consumers::Worker).to receive(:setup_consumers!).and_raise(Lepus::InvalidConsumerConfigError.new("misconfigured"))

      pid, _, err = run_supervisor_as_fork_with_captured_io(supervisor)
      expect(err).to include("misconfigured")
      wait_for_process_termination_with_timeout(pid, exitstatus: 1)
    end
  end

  describe "#set_procline" do
    it "sets $0 with supervisor kind and message" do
      supervisor.send(:set_procline)
      expect($0).to include("[lepus-supervisor: supervising ")
    end
  end

  describe "#supervised_processes" do
    it "returns the list of supervised pids" do
      supervisor.send(:forks)[111] = :dummy
      supervisor.send(:forks)[222] = :dummy

      expect(supervisor.send(:supervised_processes)).to contain_exactly(111, 222)
    end
  end

  describe "signal handling" do
    it "queues and processes TERM to terminate gracefully" do
      allow(supervisor).to receive(:stop).and_call_original
      allow(supervisor).to receive(:terminate_gracefully)

      supervisor.send(:handle_signal, :TERM)

      expect(supervisor).to have_received(:stop)
      expect(supervisor).to have_received(:terminate_gracefully)
    end

    it "queues and processes QUIT to terminate immediately" do
      allow(supervisor).to receive(:stop).and_call_original
      allow(supervisor).to receive(:terminate_immediately)

      supervisor.send(:handle_signal, :QUIT)

      expect(supervisor).to have_received(:stop)
      expect(supervisor).to have_received(:terminate_immediately)
    end
  end

  describe "#term_forks/#quit_forks" do
    it "signals all forks with correct signals" do
      supervisor.send(:forks)[333] = :dummy
      supervisor.send(:forks)[444] = :dummy

      expect(supervisor).to receive(:signal_processes).with([333, 444], :TERM)
      supervisor.send(:term_forks)

      expect(supervisor).to receive(:signal_processes).with([333, 444], :QUIT)
      supervisor.send(:quit_forks)
    end
  end

  describe "#check_for_shutdown_messages/#initiate_shutdown_sequence_from_child" do
    it "removes child and initiates shutdown when receiving shutdown message" do
      reader, writer = IO.pipe
      begin
        supervisor.send(:forks)[555] = :dummy
        supervisor.send(:pipes)[555] = reader
        supervisor.send(:configured_processes)[555] = :factory

        allow(supervisor).to receive(:quit_forks)
        allow(supervisor).to receive(:stop).and_call_original

        writer.puts(described_class::SHUTDOWN_MSG)
        writer.flush
        writer.close

        supervisor.send(:check_for_shutdown_messages)

        expect(supervisor.send(:forks)).not_to have_key(555)
        expect(supervisor.send(:pipes)).not_to have_key(555)
        expect(supervisor.send(:configured_processes)).not_to have_key(555)
        expect(supervisor).to have_received(:quit_forks)
        expect(supervisor.send(:send, :stopped?)).to be(true)
      ensure
        reader.close unless reader.closed?
        writer.close unless writer.closed?
      end
    end
  end

  describe "reaping and replacing forks" do
    it "reaps terminated forks without replacement" do
      supervisor.send(:forks)[666] = :dummy
      supervisor.send(:pipes)[666] = IO.pipe.first
      supervisor.send(:configured_processes)[666] = :factory

      allow(::Process).to receive(:waitpid2).and_return([666, double], nil)

      expect { supervisor.send(:reap_terminated_forks) }.not_to raise_error

      expect(supervisor.send(:forks)).to be_empty
      expect(supervisor.send(:pipes)).to be_empty
      expect(supervisor.send(:configured_processes)).to be_empty
    end

    it "replaces a terminated fork when it existed" do
      supervisor.send(:forks)[777] = :dummy
      supervisor.send(:pipes)[777] = IO.pipe.first
      supervisor.send(:configured_processes)[777] = :factory

      allow(supervisor).to receive(:start_process)

      status = double
      supervisor.send(:replace_fork, 777, status)

      expect(supervisor).to have_received(:start_process).with(:factory)
      expect(supervisor.send(:forks)).not_to have_key(777)
      expect(supervisor.send(:pipes)).not_to have_key(777)
      expect(supervisor.send(:configured_processes)).not_to have_key(777)
    end
  end

  describe "termination flows" do
    it "immediate termination signals QUIT" do
      expect(supervisor).to receive(:quit_forks)
      supervisor.send(:terminate_immediately)
    end

    it "graceful termination waits and escalates on timeout" do
      supervisor.send(:forks)[888] = :dummy

      allow(supervisor).to receive(:term_forks)
      allow(supervisor).to receive(:reap_terminated_forks)
      allow(supervisor).to receive(:all_forks_terminated?).and_return(false, false)
      allow(supervisor).to receive(:terminate_immediately)

      allow(Lepus::Timer).to receive(:wait_until).and_wrap_original do |m, *_args, &blk|
        # Call the block a couple of times to simulate waiting
        2.times { blk.call }
      end

      supervisor.send(:terminate_gracefully)

      expect(supervisor).to have_received(:term_forks)
      expect(supervisor).to have_received(:reap_terminated_forks).at_least(:once)
      expect(supervisor).to have_received(:terminate_immediately)
    end
  end

  describe "#build_and_start_workers" do
    after { reset_config! }

    it "groups consumers by worker name and starts processes" do
      stub_const("TestConsumerA", Class.new(Lepus::Consumer))
      stub_const("TestConsumerB", Class.new(Lepus::Consumer))

      TestConsumerA.configure(queue: "qa", exchange: "xa") { |c| c.instance_variable_set(:@worker_opts, {name: "wa"}) }
      TestConsumerB.configure(queue: "qb", exchange: "xb") { |c| c.instance_variable_set(:@worker_opts, {name: "wa"}) }

      allow(supervisor).to receive(:consumer_classes).and_return([TestConsumerA, TestConsumerB])

      factory = instance_double(Lepus::Consumers::WorkerFactory)
      allow(Lepus::Consumers::WorkerFactory).to receive(:immutate_with).and_return(factory)
      allow(supervisor).to receive(:start_process)

      supervisor.send(:build_and_start_workers)

      expect(Lepus::Consumers::WorkerFactory).to have_received(:immutate_with).with("wa", consumers: [TestConsumerA, TestConsumerB])
      expect(supervisor).to have_received(:start_process).with(factory)
    end
  end

  describe "#sync_std_streams" do
    it "sets stdout and stderr to sync mode" do
      $stdout.sync = false
      $stderr.sync = false
      supervisor.send(:sync_std_streams)
      expect($stdout.sync).to be(true)
      expect($stderr.sync).to be(true)
    end
  end

  describe "#consumer_classes" do
    after { reset_config! }

    it "returns all consumer classes that inherit from Lepus::Consumer" do
      my_consumer = Class.new(Lepus::Consumer)
      abstract_consumer = Class.new(Lepus::Consumer) { self.abstract_class = true }
      stub_const("MyConsumer", my_consumer)
      stub_const("AbstractConsumer", abstract_consumer)

      expect(supervisor.send(:consumer_classes)).to include(MyConsumer)
      expect(supervisor.send(:consumer_classes)).not_to include(AbstractConsumer)
    end
  end

  describe "#check_bunny_connection" do
    subject(:conn_test) { supervisor.send(:check_bunny_connection) }

    let(:supervisor) { described_class.new(consumers: %w[TestConsumer]) }

    context "when the connection is successful" do
      before do
        allow_any_instance_of(Bunny::Session).to receive(:start).and_return(:ok)
      end

      it "does not raise an error" do
        expect { conn_test }.not_to raise_error
      end
    end

    context "when the connection is not successful" do
      before do
        allow_any_instance_of(Bunny::Session).to receive(:start).and_raise(Bunny::Exception)
      end

      it "raises an error" do
        expect { conn_test }.to raise_error(Bunny::Exception)
      end
    end
  end
end
