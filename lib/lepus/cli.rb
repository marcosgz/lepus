require "thor"

module Lepus
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    method_option :debug, type: :boolean, default: false
    method_option :logfile, type: :string, default: nil
    method_option :pidfile, type: :string, default: nil
    method_option :require_file, type: :string, aliases: "-r", default: nil

    desc "start FirstConsumer SecondConsumer ... NthConsumer", "Run Consumer"
    default_command :start

    def start(*consumers)
      opts = (@options || {}).transform_keys(&:to_sym)

      if (list = consumers.flat_map { |c| c.split(",") }.map(&:strip).uniq.sort).any?
        opts[:consumers] = list
      end

      if (logfile = opts.delete(:logfile))
        Lepus.logger = Logger.new(logfile)
      end
      if opts.delete(:debug)
        Lepus.logger.level = Logger::DEBUG
      end

      Lepus::Supervisor.start(**opts)
    end

    desc "health_check", "Exit 0 if Lepus workers are alive, 1 if unhealthy (for ECS/K8s probes)"
    method_option :threshold, type: :numeric, default: nil,
                              desc: "Max seconds since last heartbeat (default: process_alive_threshold)"
    def health_check
      require "lepus"

      threshold = options[:threshold] || Lepus.config.process_alive_threshold
      cutoff    = Time.now - threshold

      Lepus::ProcessRegistry.start
      alive = Lepus::ProcessRegistry.all.any? { |p| p.last_heartbeat_at.to_i >= cutoff.to_i }

      if alive
        puts "ok"
        exit 0
      else
        warn "unhealthy: no workers with heartbeat since #{cutoff}"
        exit 1
      end
    rescue => e
      warn "health_check error: #{e.message}"
      exit 1
    end

    desc "web", "Run Lepus Web dashboard"
    method_option :port, type: :numeric, aliases: "-p", default: 9292, desc: "Port to listen on"
    method_option :host, type: :string, aliases: "-o", default: "0.0.0.0", desc: "Host to bind"
    def web
      port = (options[:port] || 9292).to_i
      host = options[:host] || "0.0.0.0"

      puts "Starting Lepus Web dashboard on http://#{host}:#{port}"
      puts "Press Ctrl+C to stop"

      if system("which rackup > /dev/null 2>&1")

        exec "rackup -p #{port} -o #{host} #{__dir__}/../../config.ru"
      else
        puts <<~MSG
          Rack is not installed. Please install it using the following command:

              gem install rack

          Then run the web dashboard again.
        MSG
      end
    end
  end
end
