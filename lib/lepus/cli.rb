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

    desc "web", "Run Lepus Web dashboard"
    method_option :port, type: :numeric, aliases: "-p", default: 9292, desc: "Port to listen on"
    method_option :host, type: :string, aliases: "-o", default: "0.0.0.0", desc: "Host to bind"
    def web
      port = (options[:port] || 9292).to_i
      host = options[:host] || '0.0.0.0'

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
