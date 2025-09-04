module ProcessHelper
  def lepus_root
    Pathname.new(File.expand_path("../../", __dir__))
  end

  def run_as_fork(process)
    fork { process.start }
  end

  def run_supervisor_as_fork_with_captured_io(supervisor)
    pid = nil

    out, err = capture_subprocess_io do
      pid = run_as_fork(supervisor)
      wait_for_registered_processes(1)
    end

    [pid, out, err]
  end

  def terminate_process(pid, timeout: 10, signal: :TERM)
    signal_process(pid, signal)
    wait_for_process_termination_with_timeout(pid, timeout: timeout, signaled: signal)
  end

  def wait_for_registered_processes(count, timeout: 2)
    wait_while_with_timeout(timeout) { Lepus::ProcessRegistry.count != count }
  end

  def wait_for_process_termination_with_timeout(pid, timeout: 10, exitstatus: 0, signaled: nil)
    Timeout.timeout(timeout) do
      if process_exists?(pid)
        begin
          status = Process.waitpid2(pid).last
          expect(status.exitstatus).to eq(exitstatus), "Expected pid #{pid} to exit with status #{exitstatus}" if status.exitstatus
          expect(Signal.list.key(status.termsig).to_sym).to eq(signaled), "Expected pid #{pid} to be terminated with signal #{signaled}" if status.termsig
        rescue Errno::ECHILD
          # Child pid already reaped
        end
      end
    end
  rescue Timeout::Error
    signal_process(pid, :KILL)
    raise
  end

  def signal_process(pid, signal, wait: nil)
    Thread.new do
      sleep(wait) if wait
      Process.kill(signal, pid)
    end
  end

  def process_exists?(pid)
    reap_processes
    Process.getpgid(pid)
    true
  rescue Errno::ESRCH
    false
  end

  def reap_processes
    Process.waitpid(-1, Process::WNOHANG)
  rescue Errno::ECHILD
  end

  protected

  def wait_while_with_timeout(timeout, &block)
    Timeout.timeout(timeout) do
      while yield
        sleep 0.05
      end
    end
  rescue Timeout::Error
  end

  def capture_subprocess_io
    old_stdout, old_stderr = $stdout, $stderr
    out_reader, out_writer = IO.pipe
    err_reader, err_writer = IO.pipe

    $stdout, $stderr = out_writer, err_writer

    yield

    out_writer.close
    err_writer.close

    out = out_reader.read
    err = err_reader.read

    out_reader.close
    err_reader.close

    [out, err]
  ensure
    $stdout = old_stdout
    $stderr = old_stderr
  end
end

RSpec.configure do |config|
  config.include ProcessHelper
end
