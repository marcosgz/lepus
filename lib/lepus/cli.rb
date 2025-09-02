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
      consumers.flat_map { |c| c.split(",") }.map(&:strip).uniq.sort

      if (logfile = opts.delete(:logfile))
        Lepus.logger = Logger.new(logfile)
      end
      if opts.delete(:debug)
        Lepus.logger.level = Logger::DEBUG
      end

      Lepus::Supervisor.start(**opts)
    end
  end
end
