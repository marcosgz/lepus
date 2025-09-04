# frozen_string_literal: true

require "rack"
require "multi_json"
require "pathname"

module Lepus
  module Web
    def self.assets_path
      @assets_path ||= Pathname.new(File.expand_path("../../", __dir__)).join("web")
    end

    def self.mime_for(path)
      case File.extname(path)
      when ".html" then "text/html"
      when ".css" then "text/css"
      when ".js" then "application/javascript"
      when ".png" then "image/png"
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".svg" then "image/svg+xml"
      else "application/octet-stream"
      end
    end

    # Make the Web module directly mountable as a Rack application
    def self.call(env)
      App.build.call(env)
    end
  end
end
