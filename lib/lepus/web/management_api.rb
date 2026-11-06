# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "time"

module Lepus
  module Web
    # HTTP client for RabbitMQ Management API.
    # Fetches queue and connection statistics.
    class ManagementAPI
      DEFAULT_PORT = 15672
      OVERVIEW_RATES = {
        publish: "publish",
        deliver: "deliver_get",
        ack: "ack",
        redeliver: "redeliver"
      }.freeze

      attr_reader :base_url, :vhost

      def initialize(base_url: nil, vhost: nil)
        @base_url = base_url || derive_management_url
        @vhost = vhost || derive_vhost
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

      # Fetch the bindings of the configured vhost, without the default exchange's implicit ones
      # @return [Array<Hash>] array of binding data
      def bindings
        data = get("/api/bindings/#{encode_vhost}")
        return [] unless data.is_a?(Array)

        data
          .reject { |b| b["source"].to_s.empty? }
          .map { |b| normalize_binding(b) }
      end

      # Fetch the consumers subscribed to queues of the configured vhost
      # @return [Array<Hash>] array of consumer data
      def consumers
        data = get("/api/consumers/#{encode_vhost}")
        return [] unless data.is_a?(Array)

        data.map { |c| normalize_consumer(c) }
      end

      # Fetch the broker overview, with message rate history when asked
      # @param age [Integer, nil] seconds of history to include
      # @param increment [Integer] seconds between history samples
      # @return [Hash] overview data
      def overview(age: nil, increment: 10)
        path = "/api/overview"
        path += "?msg_rates_age=#{Integer(age)}&msg_rates_incr=#{Integer(increment)}" if age
        normalize_overview(get(path) || {})
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

      UNREACHABLE = [ConnectionError, SocketError, SystemCallError, IOError, Timeout::Error].freeze

      # What the dashboard may show about a failure: never the broker's
      # host names, ports or response bodies, which stay in the log.
      def self.client_message(error)
        case error
        when AuthenticationError then "The RabbitMQ management API rejected the credentials"
        when *UNREACHABLE then "The RabbitMQ management API could not be reached"
        else "The RabbitMQ management API returned an error"
        end
      end

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

      def derive_vhost
        path = parse_rabbitmq_uri&.path.to_s.delete_prefix("/")
        path.empty? ? "/" : URI.decode_www_form_component(path)
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
          state: q["state"],
          durable: q["durable"],
          exclusive: q["exclusive"] || false,
          auto_delete: q["auto_delete"] || false,
          arguments: q["arguments"] || {},
          idle_since: q["idle_since"],
          consumer_utilisation: q["consumer_utilisation"],
          messages_rate: q.dig("messages_details", "rate") || 0.0,
          messages_ready_rate: q.dig("messages_ready_details", "rate") || 0.0,
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

      def normalize_binding(b)
        {
          source: b["source"],
          destination: b["destination"],
          destination_type: b["destination_type"],
          routing_key: b["routing_key"].to_s,
          arguments: b["arguments"] || {}
        }
      end

      def normalize_consumer(c)
        channel = c["channel_details"] || {}
        {
          queue: c.dig("queue", "name"),
          consumer_tag: c["consumer_tag"],
          connection_name: channel["connection_name"],
          channel: channel["name"],
          prefetch_count: c["prefetch_count"] || 0,
          ack_required: c["ack_required"],
          active: c.fetch("active", true)
        }
      end

      def normalize_overview(o)
        stats = o["message_stats"] || {}
        totals = o["queue_totals"] || {}
        {
          rabbitmq_version: o["rabbitmq_version"],
          cluster_name: o["cluster_name"],
          rates: OVERVIEW_RATES.transform_values { |key| stats.dig("#{key}_details", "rate") || 0.0 },
          queue_totals: {
            messages: totals["messages"] || 0,
            messages_ready: totals["messages_ready"] || 0,
            messages_unacknowledged: totals["messages_unacknowledged"] || 0
          },
          object_totals: (o["object_totals"] || {}).transform_keys(&:to_sym),
          history: rate_history(stats)
        }
      end

      # Turns the cumulative samples RabbitMQ keeps per counter into
      # per-second rates, one row per sample interval, oldest first.
      def rate_history(stats)
        series = OVERVIEW_RATES.transform_values do |key|
          (stats.dig("#{key}_details", "samples") || []).map { |s| [s["timestamp"], s["sample"]] }.sort_by(&:first)
        end
        times = series.values.flat_map { |samples| samples.map(&:first) }.uniq.sort
        return [] if times.size < 2

        counts = series.transform_values(&:to_h)
        times.each_cons(2).map do |from, to|
          seconds = (to - from) / 1000.0
          row = {t: Time.at(to / 1000.0).utc.iso8601}
          counts.each do |name, by_time|
            row[name] = (by_time[from] && by_time[to]) ? [(by_time[to] - by_time[from]) / seconds, 0].max.round(2) : 0.0
          end
          row
        end
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
