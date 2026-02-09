# frozen_string_literal: true

require "rack"
require "multi_json"
require "pathname"

module Lepus
  module Web
    class << self
      attr_accessor :aggregator
      attr_accessor :management_api
    end

    def self.assets_path
      @assets_path ||= Pathname.new(File.expand_path("../../", __dir__)).join("web")
    end

    def self.start_aggregator
      return if aggregator&.running?

      self.aggregator = Aggregator.new
      aggregator.start
    end

    def self.stop_aggregator
      aggregator&.stop
      self.aggregator = nil
    end

    def self.start_management_api
      self.management_api = Lepus.config.build_management_api
    end

    def self.stop_management_api
      self.management_api = nil
    end

    # Start all web services (aggregator and management API)
    def self.start
      start_aggregator
      start_management_api
    end

    # Stop all web services
    def self.stop
      stop_aggregator
      stop_management_api
    end

    def self.mime_for(path)
      case File.extname(path)
      when ".html" then "text/html"
      when ".css" then "text/css"
      when ".js" then "application/javascript"
      when ".png" then "image/png"
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".svg" then "image/svg+xml"
      when ".woff", ".woff2" then "font/woff"
      when ".ttf" then "font/ttf"
      when ".eot" then "application/vnd.ms-fontobject"
      else "application/octet-stream"
      end
    end

    # Make the Web module directly mountable as a Rack application
    def self.call(env)
      App.build.call(env)
    end
  end
end
