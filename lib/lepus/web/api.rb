# frozen_string_literal: true

module Lepus
  module Web
    class API
      def initialize(aggregator: nil, management_api: nil)
        @aggregator = aggregator
        @management_api = management_api
      end

      def call(env)
        req = Rack::Request.new(env)
        case req.path_info
        when "/health"
          Web::RespondWith.json(template: :health)
        when "/processes"
          processes_data
        when "/queues"
          queues_data
        when "/connections"
          connections_data
        when "/exchanges"
          exchanges_data
        else
          Web::RespondWith.json(template: :not_found)
        end
      end

      private

      def aggregator
        @aggregator || Web.aggregator
      end

      def management_api
        @management_api || Web.management_api
      end

      def processes_data
        if aggregator&.running?
          payload = aggregator.all_processes
          Web::RespondWith.json(template: :ok, body: payload)
        else
          Web::RespondWith.json(template: :ok, body: [])
        end
      end

      def queues_data
        if management_api
          raw_queues = management_api.queues
          payload = annotate_queues_with_apps(raw_queues)
          Web::RespondWith.json(template: :ok, body: payload)
        else
          Web::RespondWith.json(template: :ok, body: [])
        end
      rescue => e
        Lepus.logger.warn("[Web::API] Failed to fetch queues: #{e.message}")
        Web::RespondWith.json(template: :ok, body: [])
      end

      def connections_data
        if management_api
          payload = management_api.connections
          Web::RespondWith.json(template: :ok, body: payload)
        else
          Web::RespondWith.json(template: :ok, body: [])
        end
      rescue => e
        Lepus.logger.warn("[Web::API] Failed to fetch connections: #{e.message}")
        Web::RespondWith.json(template: :ok, body: [])
      end

      def exchanges_data
        if management_api
          raw_exchanges = management_api.exchanges
          payload = filter_exchanges(raw_exchanges)
          Web::RespondWith.json(template: :ok, body: payload)
        else
          Web::RespondWith.json(template: :ok, body: [])
        end
      rescue => e
        Lepus.logger.warn("[Web::API] Failed to fetch exchanges: #{e.message}")
        Web::RespondWith.json(template: :ok, body: [])
      end

      def annotate_queues_with_apps(queues)
        return queues unless aggregator&.running?

        queue_app_map = build_queue_app_map
        return queues if queue_app_map.empty?

        queues.map do |queue|
          app = queue_app_map[queue[:name]]
          app ? queue.merge(application: app) : queue
        end
      end

      def filter_exchanges(exchanges)
        return exchanges if Lepus.config.web_show_all_exchanges
        return exchanges unless aggregator&.running?

        known_exchanges = build_known_exchange_names
        return exchanges if known_exchanges.empty?

        exchanges.select { |e| known_exchanges.include?(e[:name]) }
      end

      def build_queue_app_map
        map = {}
        aggregator.all_processes.each do |process|
          app_name = process[:application]
          next unless app_name

          (process[:consumers] || []).each do |consumer|
            map[consumer[:queue]] = app_name if consumer[:queue]
          end
        end
        map
      end

      def build_known_exchange_names
        names = Set.new
        aggregator.all_processes.each do |process|
          (process[:consumers] || []).each do |consumer|
            names << consumer[:exchange] if consumer[:exchange]
          end
        end
        names
      end
    end
  end
end
