# frozen_string_literal: true

require "net/http"
require "uri"

module Lepus
  module Web
    # Minimal HTTP wrapper using Ruby's Net::HTTP
    class HTTP
      class Error < StandardError; end
      DEFAULT_OPEN_TIMEOUT = 5
      DEFAULT_READ_TIMEOUT = 10

      def initialize(base_url:, username: nil, password: nil, open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT)
        @base_url = base_url
        @username = username
        @password = password
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def get(path)
        uri = URI.join(@base_url, path)
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
        request["Content-Type"] = "application/json"
        request.basic_auth(@username, @password) if @username || @password

        perform(uri, request)
      end

      private

      def perform(uri, request)
        http = Net::HTTP.new(uri.host, uri.port)
        if uri.scheme == "https"
          http.use_ssl = true
        end
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout

        http.request(request)
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError, EOFError => e
        raise Error, e.message
      end
    end
  end
end


