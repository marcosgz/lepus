require "puma/plugin"

Puma::Plugin.create do
  attr_reader :puma_pid, :lepus_pid, :log_writer, :lepus_supervisor

  def start(launcher)
    @log_writer = launcher.log_writer
    @puma_pid = $$

    in_background do
      monitor_lepus
    end

    launcher.events.on_booted do
      @lepus_pid = fork do
        Thread.new { monitor_puma }
        Lepus::Supervisor.start
      end
    end

    launcher.events.on_stopped { stop_lepus }
    launcher.events.on_restart { stop_lepus }
  end

  private

  def stop_lepus
    Process.waitpid(lepus_pid, Process::WNOHANG)
    log "Stopping Lepus..."
    Process.kill(:INT, lepus_pid) if lepus_pid
    Process.wait(lepus_pid)
  rescue Errno::ECHILD, Errno::ESRCH
  end

  def monitor_puma
    monitor(:puma_dead?, "Detected Puma has gone away, stopping Lepus...")
  end

  def monitor_lepus
    monitor(:lepus_dead?, "Detected Lepus has gone away, stopping Puma...")
  end

  def monitor(process_dead, message)
    loop do
      if send(process_dead)
        log message
        Process.kill(:INT, $$)
        break
      end
      sleep 2
    end
  end

  def lepus_dead?
    if lepus_started?
      Process.waitpid(lepus_pid, Process::WNOHANG)
    end
    false
  rescue Errno::ECHILD, Errno::ESRCH
    true
  end

  def lepus_started?
    !lepus_pid.nil?
  end

  def puma_dead?
    Process.ppid != puma_pid
  end

  def log(*args)
    log_writer.log(*args)
  end
end
