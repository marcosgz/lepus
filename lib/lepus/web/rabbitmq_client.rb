# frozen_string_literal: true

require "uri"

module Lepus
  module Web
    class RabbitMQClient
      class Error < StandardError; end
      class ConnectionError < Error; end
      class AuthenticationError < Error; end
      class NotFoundError < Error; end

      def initialize(configuration = Lepus.config)
        @configuration = configuration
        @http_client = build_http_client
      end

      # Get overview information about the RabbitMQ cluster
      def overview
        get("/api/overview")
      end

      # Get all nodes in the cluster
      def nodes
        get("/api/nodes")
      end

      # Get a specific node information
      def node(name)
        get("/api/nodes/#{URI.encode_www_form_component(name)}")
      end

      # Get all connections
      def connections
        get("/api/connections")
      end

      # Get connections for a specific virtual host
      def connections_for_vhost(vhost = "/")
        encoded_vhost = URI.encode_www_form_component(vhost)
        get("/api/vhosts/#{encoded_vhost}/connections")
      end

      # Get all channels
      def channels
        get("/api/channels")
      end

      # Get channels for a specific virtual host
      def channels_for_vhost(vhost = "/")
        encoded_vhost = URI.encode_www_form_component(vhost)
        get("/api/vhosts/#{encoded_vhost}/channels")
      end

      # Get all queues
      def queues
        get("/api/queues")
      end

      # Get queues for a specific virtual host
      def queues_for_vhost(vhost = "/")
        encoded_vhost = URI.encode_www_form_component(vhost)
        get("/api/queues/#{encoded_vhost}")
      end

      # Get a specific queue
      def queue(vhost, name)
        encoded_vhost = URI.encode_www_form_component(vhost)
        encoded_name = URI.encode_www_form_component(name)
        get("/api/queues/#{encoded_vhost}/#{encoded_name}")
      end

      # Get all exchanges
      def exchanges
        get("/api/exchanges")
      end

      # Get exchanges for a specific virtual host
      def exchanges_for_vhost(vhost = "/")
        encoded_vhost = URI.encode_www_form_component(vhost)
        get("/api/exchanges/#{encoded_vhost}")
      end

      # Get all consumers
      def consumers
        get("/api/consumers")
      end

      # Get consumers for a specific virtual host
      def consumers_for_vhost(vhost = "/")
        encoded_vhost = URI.encode_www_form_component(vhost)
        get("/api/consumers/#{encoded_vhost}")
      end

      # Get all virtual hosts
      def vhosts
        get("/api/vhosts")
      end

      private

      def build_http_client
        Lepus::Web::HTTP.new(
          base_url: rabbitmq_management_url,
          username: username,
          password: password,
          open_timeout: 5,
          read_timeout: 10
        )
      end

      def get(path)
        response = @http_client.get(path)
        handle_response(response)
      rescue Lepus::Web::HTTP::Error => e
        raise ConnectionError, "Failed to connect to RabbitMQ management API: #{e.message}"
      end

      def handle_response(response)
        code = response.code.to_i
        case code
        when 200..299
          parse_json_response(response.body.to_s)
        when 401
          raise AuthenticationError, "Authentication failed for RabbitMQ management API"
        when 404
          raise NotFoundError, "Resource not found"
        when 500..599
          raise Error, "RabbitMQ management API error: #{code}"
        else
          raise Error, "Unexpected response from RabbitMQ management API: #{code}"
        end
      end

      def parse_json_response(body)
        return {} if body.empty?

        MultiJson.load(body)
      rescue MultiJson::ParseError => e
        raise Error, "Failed to parse JSON response: #{e.message}"
      end

      def rabbitmq_management_url
        @rabbitmq_management_url ||= begin
          uri = URI.parse(@configuration.rabbitmq_url)
          # Convert AMQP URL to HTTP management URL
          # amqp://guest:guest@localhost:5672 -> http://guest:guest@localhost:15672
          scheme = uri.scheme == "amqps" ? "https" : "http"
          port = uri.scheme == "amqps" ? 15671 : 15672

          "#{scheme}://#{uri.host}:#{port}"
        end
      end

      def username
        @username ||= begin
          uri = URI.parse(@configuration.rabbitmq_url)
          uri.user || "guest"
        end
      end

      def password
        @password ||= begin
          uri = URI.parse(@configuration.rabbitmq_url)
          uri.password || "guest"
        end
      end
    end
  end
end
