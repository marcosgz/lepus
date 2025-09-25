# frozen_string_literal: true

module Lepus
  module Web
    class API
      def initialize
        @rabbitmq_client = RabbitMQClient.new
      end

      def call(env)
        req = Rack::Request.new(env)
        case req.path_info
        when "/health"
          Web::RespondWith.json(template: :health)
        when "/processes"
          demo_processes
        when "/queues/grouped"
          grouped_queues
        when "/connections"
          real_connections
        when "/overview"
          real_overview
        when "/nodes"
          real_nodes
        when "/channels"
          real_channels
        when "/consumers"
          real_consumers
        else
          Web::RespondWith.json(template: :not_found)
        end
      rescue RabbitMQClient::Error => e
        Web::RespondWith.json(
          status: 500,
          body: { error: "rabbitmq_error", message: e.message }
        )
      end

      private

      def demo_processes
        now = (Time.now.to_f * 1000).to_i
        payload = [
          {
            id: 1,
            name: "Supervisor A",
            pid: 1001,
            hostname: Socket.gethostname,
            kind: "supervisor",
            last_heartbeat_at: now,
            rss_memory: 120_000_000,
            heap_memory: 85_000_000,
            application: "OrdersApp"
          },
          {
            id: 2,
            name: "Worker A1",
            pid: 1002,
            hostname: Socket.gethostname,
            kind: "worker",
            supervisor_id: 1,
            last_heartbeat_at: now,
            rss_memory: 80_000_000,
            heap_memory: 55_000_000,
            connections: 2,
            consumers: [
              {
                class_name: "OrdersConsumer",
                exchange: "orders.exchange",
                queue: "orders.main",
                route: "order.created",
                threads: 3,
                processed: 1250,
                rejected: 12,
                errored: 3
              },
              {
                class_name: "NotificationsConsumer",
                exchange: "notifications.exchange",
                queue: "notifications.main",
                route: nil,
                threads: 2,
                processed: 890,
                rejected: 5,
                errored: 1
              }
            ]
          },
          {
            id: 3,
            name: "Worker A2",
            pid: 1003,
            hostname: Socket.gethostname,
            kind: "worker",
            supervisor_id: 1,
            last_heartbeat_at: now - 65_000,
            rss_memory: 90_000_000,
            heap_memory: 62_000_000,
            connections: 1,
            consumers: [
              {
                class_name: "RetryConsumer",
                exchange: "orders.exchange",
                queue: "orders.retry",
                route: "order.retry",
                threads: 1,
                processed: 45,
                rejected: 2,
                errored: 0
              }
            ]
          },
          {
            id: 4,
            name: "Supervisor B",
            pid: 1004,
            hostname: Socket.gethostname,
            kind: "supervisor",
            last_heartbeat_at: now,
            rss_memory: 110_000_000,
            heap_memory: 78_000_000,
            application: "InvoicesApp"
          },
          {
            id: 5,
            name: "Worker B1",
            pid: 1005,
            hostname: Socket.gethostname,
            kind: "worker",
            supervisor_id: 4,
            last_heartbeat_at: now,
            rss_memory: 75_000_000,
            heap_memory: 52_000_000,
            connections: 1,
            consumers: [
              {
                class_name: "InvoicesConsumer",
                exchange: "invoices.exchange",
                queue: "invoices.main",
                route: "invoice.generated",
                threads: 2,
                processed: 340,
                rejected: 8,
                errored: 2
              }
            ]
          }
        ]
        Web::RespondWith.json(template: :ok, body: payload)
      end

      def demo_queues
        payload = [
          {name: "orders.main", type: "classic", messages: 42, messages_ready: 21, messages_unacknowledged: 2, consumers: 3, memory: 8 * 1024 * 1024},
          {name: "orders.retry", type: "classic", messages: 5, messages_ready: 5, messages_unacknowledged: 0, consumers: 0, memory: 1 * 1024 * 1024},
          {name: "orders.error", type: "classic", messages: 2, messages_ready: 2, messages_unacknowledged: 0, consumers: 0, memory: 512 * 1024},
          {name: "invoices", type: "quorum", messages: 12, messages_ready: 12, messages_unacknowledged: 0, consumers: 2, memory: 2 * 1024 * 1024}
        ]
        Web::RespondWith.json(template: :ok, body: payload)
      end

      def demo_connections
        payload = [
          {name: "conn-1", state: "running", user: "guest", vhost: "/", channels: 2},
          {name: "conn-2", state: "idle", user: "guest", vhost: "/", channels: 1},
          {name: "conn-3", state: "running", user: "admin", vhost: "/", channels: 3}
        ]
        Web::RespondWith.json(template: :ok, body: payload)
      end

      def real_overview
        data = @rabbitmq_client.overview
        Web::RespondWith.json(template: :ok, body: data)
      end

      def real_nodes
        data = @rabbitmq_client.nodes
        Web::RespondWith.json(template: :ok, body: data)
      end

      def real_connections
        data = @rabbitmq_client.connections
        Web::RespondWith.json(template: :ok, body: data)
      end

      def real_channels
        data = @rabbitmq_client.channels
        Web::RespondWith.json(template: :ok, body: data)
      end


      def real_consumers
        data = @rabbitmq_client.consumers
        Web::RespondWith.json(template: :ok, body: data)
      end

      # Group queues by base name: base, with optional .retry and .error children
      # Returns: [{name: base, queues: {main: q|nil, retry: q|nil, error: q|nil}}]
      def grouped_queues
        data = @rabbitmq_client.queues
        simplified = data.map do |queue|
          {
            name: queue["name"],
            type: queue["type"] || "classic",
            messages: queue["messages"] || 0,
            messages_ready: queue["messages_ready"] || 0,
            messages_unacknowledged: queue["messages_unacknowledged"] || 0,
            consumers: queue["consumers"] || 0,
            memory: queue["memory"] || 0
          }
        end

        buckets = {}
        simplified.each do |q|
          name = q[:name]
          base, queue_type = case name
                            when /\.retry\z/ then [name.sub(/\.retry\z/, ""), :retry]
                            when /\.error\z/ then [name.sub(/\.error\z/, ""), :error]
                            else [name.sub(/\.main\z/, ""), :main]
                            end

          bucket = buckets[base] ||= {name: base, queues: {main: nil, retry: nil, error: nil}}
          bucket[:queues][queue_type] = q
        end

        grouped = buckets.values.sort_by { |g| g[:name] }
        Web::RespondWith.json(template: :ok, body: grouped)
      end
    end
  end
end
