# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Lepus
  module Web
    # HTTP client for RabbitMQ Management API.
    # Fetches queue and connection statistics.
    class ManagementAPI
      DEFAULT_PORT = 15672

      attr_reader :base_url, :vhost

      def initialize(base_url: nil, vhost: "/")
        @base_url = base_url || derive_management_url
        @vhost = vhost
      end

      # Fetch all queues for the configured vhost
      # @return [Array<Hash>] array of queue data
      def queues
        data = get("/api/queues/#{encode_vhost}")
        return [] unless data.is_a?(Array)

        data.map { |q| normalize_queue(q) }
      end

      # Fetch all exchanges for the configured vhost
      # @return [Array<Hash>] array of exchange data
      def exchanges
        data = get("/api/exchanges/#{encode_vhost}")
        return [] unless data.is_a?(Array)

        data
          .reject { |e| e["name"].to_s.empty? || e["name"].to_s.start_with?("amq.") }
          .map { |e| normalize_exchange(e) }
      end

      # Fetch all connections
      # @return [Array<Hash>] array of connection data
      def connections
        data = get("/api/connections")
        return [] unless data.is_a?(Array)

        data.map { |c| normalize_connection(c) }
      end

      # Fetch a specific queue
      # @param name [String] queue name
      # @return [Hash, nil] queue data or nil if not found
      def queue(name)
        data = get("/api/queues/#{encode_vhost}/#{encode_name(name)}")
        normalize_queue(data) if data
      rescue NotFoundError
        nil
      end

      class Error < StandardError; end

      class ConnectionError < Error; end

      class AuthenticationError < Error; end

      class NotFoundError < Error; end

      private

      def parse_rabbitmq_uri
        URI.parse(Lepus.config.rabbitmq_url)
      rescue
        nil
      end

      def derive_management_url
        uri = parse_rabbitmq_uri
        return "http://localhost:#{DEFAULT_PORT}" unless uri

        "http://#{uri.host}:#{DEFAULT_PORT}"
      end

      def credentials
        uri = parse_rabbitmq_uri
        return unless uri&.user

        [uri.user, uri.password]
      end

      def encode_vhost
        URI.encode_www_form_component(@vhost)
      end

      def encode_name(name)
        URI.encode_www_form_component(name)
      end

      def get(path)
        uri = URI.parse("#{@base_url}#{path}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = 5
        http.read_timeout = 10

        request = Net::HTTP::Get.new(uri.request_uri)
        if (creds = credentials)
          request.basic_auth(*creds)
        end
        request["Accept"] = "application/json"

        response = http.request(request)

        case response.code.to_i
        when 200
          JSON.parse(response.body)
        when 401
          raise AuthenticationError, "Authentication failed for RabbitMQ Management API"
        when 404
          raise NotFoundError, "Resource not found: #{path}"
        else
          raise Error, "RabbitMQ Management API error: #{response.code} - #{response.body}"
        end
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::OpenTimeout, Net::ReadTimeout => e
        raise ConnectionError, "Failed to connect to RabbitMQ Management API: #{e.message}"
      end

      def normalize_queue(q)
        {
          name: q["name"],
          type: q["type"] || "classic",
          messages: q["messages"] || 0,
          messages_ready: q["messages_ready"] || 0,
          messages_unacknowledged: q["messages_unacknowledged"] || 0,
          consumers: q["consumers"] || 0,
          memory: q["memory"] || 0,
          message_stats: normalize_message_stats(q["message_stats"])
        }
      end

      def normalize_message_stats(stats)
        return {} unless stats

        {
          publish: stats["publish"] || 0,
          publish_rate: stats.dig("publish_details", "rate") || 0.0,
          deliver_get: stats["deliver_get"] || 0,
          deliver_get_rate: stats.dig("deliver_get_details", "rate") || 0.0,
          ack: stats["ack"] || 0,
          ack_rate: stats.dig("ack_details", "rate") || 0.0,
          redeliver: stats["redeliver"] || 0,
          redeliver_rate: stats.dig("redeliver_details", "rate") || 0.0
        }
      end

      def normalize_exchange(e)
        {
          name: e["name"],
          type: e["type"],
          durable: e["durable"],
          auto_delete: e["auto_delete"],
          message_stats: normalize_exchange_stats(e["message_stats"])
        }
      end

      def normalize_exchange_stats(stats)
        return {} unless stats

        {
          publish_in: stats["publish_in"] || 0,
          publish_in_rate: stats.dig("publish_in_details", "rate") || 0.0,
          publish_out: stats["publish_out"] || 0,
          publish_out_rate: stats.dig("publish_out_details", "rate") || 0.0
        }
      end

      def normalize_connection(c)
        {
          name: c["name"],
          state: c["state"],
          user: c["user"],
          vhost: c["vhost"],
          channels: c["channels"] || 0,
          connected_at: c["connected_at"],
          client_properties: {
            connection_name: c.dig("client_properties", "connection_name")
          }
        }
      end
    end
  end
end
