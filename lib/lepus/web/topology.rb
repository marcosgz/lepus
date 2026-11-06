# frozen_string_literal: true

require "set"
require "time"

module Lepus
  module Web
    # Assembles the broker topology drawn by the dashboard map: exchanges, the
    # bindings that route them to queues, every queue classified by its role
    # (main, retry, error or delay) and the consumers reading each queue,
    # merged from the management API and worker heartbeats.
    #
    # Delay queues are the ones Lepus::Delay declares: "<queue>.delay.<ms>"
    # dead-letters into <queue> and "<exchange>.delayed.<ms>" into
    # <exchange>, each holding its messages for exactly <ms>. Messages
    # waiting in them are counted as delayed on the queue or exchange they
    # are released to.
    class Topology
      CONSUMER_TAG_INDEX = /-\d+\z/
      COUNTERS = %i[processed rejected errored delayed].freeze

      def initialize(management_api:, aggregator:, show_all_exchanges: false)
        @management_api = management_api
        @aggregator = aggregator
        @show_all_exchanges = show_all_exchanges
      end

      def to_h
        broker = fetch_broker
        processes = @aggregator&.running? ? @aggregator.all_processes : []
        heartbeat = heartbeat_consumers(processes)
        broker = broker.merge(declared_topology(heartbeat)) unless broker[:management]
        queues = count_delayed(classify_queues(broker[:queues], heartbeat, broker[:bindings]))
        exchanges = exchange_rows(broker[:exchanges], queues)
        bindings = group_bindings(broker[:bindings])
        exchanges, bindings, queues = filter(exchanges, bindings, queues, heartbeat) unless @show_all_exchanges

        {
          management: broker[:management],
          management_error: broker[:error],
          generated_at: Time.now.utc.iso8601(3),
          exchanges: exchanges,
          bindings: bindings,
          queues: queues,
          consumers: merge_consumers(heartbeat, broker[:consumers])
        }
      end

      private

      def fetch_broker
        empty = {queues: [], exchanges: [], bindings: [], consumers: []}
        return empty.merge(management: false, error: "The RabbitMQ management API is not configured") unless @management_api

        empty.merge(
          management: true,
          error: nil,
          queues: @management_api.queues,
          exchanges: @management_api.exchanges,
          bindings: @management_api.bindings,
          consumers: @management_api.consumers
        )
      rescue => e
        Lepus.logger.warn("[Web::Topology] Failed to fetch the topology: #{e.message}")
        empty.merge(management: false, error: ManagementAPI.client_message(e))
      end

      # Without the management API the map still draws what consumers
      # declared, from their heartbeats, with no counts or rates.
      def declared_topology(heartbeat)
        consumers = heartbeat.map(&:last).select { |c| c[:exchange] && c[:queue] }
        {
          exchanges: consumers.map { |c| {name: c[:exchange], type: nil, message_stats: {}} }.uniq,
          bindings: consumers.flat_map do |c|
            Array(c[:route] || "").map { |key| {source: c[:exchange], destination: c[:queue], destination_type: "queue", routing_key: key} }
          end.uniq,
          queues: consumers.map { |c| {name: c[:queue], arguments: {}, message_stats: {}} }.uniq
        }
      end

      def heartbeat_consumers(processes)
        processes.flat_map do |process|
          (process[:consumers] || []).map { |consumer| [process, consumer] }
        end
      end

      def classify_queues(raw, heartbeat, bindings)
        queues = raw.reject { |q| q[:exclusive] && q[:name].to_s.start_with?("amq.") }
        by_name = queues.to_h { |q| [q[:name], q] }
        context = {
          by_name: by_name,
          declared: declared_children(heartbeat),
          consumed: heartbeat.map { |(_process, consumer)| consumer[:queue] }.compact.to_set,
          anchored: bindings.select { |b| b[:destination_type] == "queue" && !b[:source].to_s.empty? }.map { |b| b[:destination] }.to_set
        }
        context[:dead_letter_targets] = dead_letter_targets(queues, by_name)
        applications = heartbeat.each_with_object({}) { |(process, c), map| map[c[:queue]] ||= process[:application] }

        queues.map do |queue|
          delay = delay_of(queue)
          role, parent, parent_exchange = delay ? delay_role(delay) : classify(queue, context)
          queue_row(queue, role, parent, parent_exchange, applications[queue[:name]], delay)
        end
      end

      # Where a queue declared by Lepus::Delay releases its messages, read
      # from its name and arguments, or nil for any other queue.
      def delay_of(queue)
        args = queue[:arguments] || {}
        ms = args["x-message-ttl"]
        exchange = args["x-dead-letter-exchange"]
        return unless ms.is_a?(Integer) && ms.positive? && exchange

        if exchange == Delay::DEFAULT_EXCHANGE
          target = args["x-dead-letter-routing-key"].to_s
          {ms: ms, target: target, target_type: "queue"} if queue[:name] == Delay.queue_delay_name_for(target, ms)
        elsif !args.key?("x-dead-letter-routing-key") && queue[:name] == Delay.exchange_queue_name_for(exchange, ms)
          {ms: ms, target: exchange, target_type: "exchange"}
        end
      end

      def delay_role(delay)
        (delay[:target_type] == "queue") ? ["delay", delay[:target], nil] : ["delay", nil, delay[:target]]
      end

      def count_delayed(queues)
        waiting = delayed_by_target(queues, "queue")
        queues.each do |queue|
          held = waiting[queue[:name]]
          queue[:delayed] = held ? held[:messages] : 0
          queue[:delays] = held ? held[:delays] : []
        end
      end

      def delayed_by_target(queues, type)
        queues.select { |q| q[:target_type] == type }.group_by { |q| q[:target] }.transform_values do |list|
          {messages: list.sum { |q| q[:messages] }, delays: list.map { |q| q[:delay_ms] }.uniq.sort}
        end
      end

      def declared_children(heartbeat)
        heartbeat.each_with_object({}) do |(_process, consumer), map|
          map[consumer[:retry_queue]] = ["retry", consumer[:queue]] if consumer[:retry_queue]
          map[consumer[:error_queue]] = ["error", consumer[:queue]] if consumer[:error_queue]
        end
      end

      def dead_letter_target(queue, by_name)
        args = queue[:arguments] || {}
        target = args["x-dead-letter-routing-key"]
        target if args["x-dead-letter-exchange"] == "" && target != queue[:name] && by_name.key?(target)
      end

      # A TTL queue that dead-letters into a queue which dead-letters back,
      # or one named "<queue>.retry", holds messages waiting to be retried.
      # Delay queues never reach here.
      def retry_loop?(queue, by_name)
        target = dead_letter_target(queue, by_name)
        return false if target.nil? || (queue[:arguments] || {})["x-message-ttl"].nil?

        queue[:name] == "#{target}.retry" || dead_letter_target(by_name[target], by_name) == queue[:name]
      end

      # Queues another queue dead-letters into, other than through a retry or
      # delay round trip, collect what was given up on: error queues.
      def dead_letter_targets(queues, by_name)
        queues.each_with_object({}) do |queue, map|
          target = dead_letter_target(queue, by_name)
          next unless target
          next if retry_loop?(queue, by_name) || delay_of(queue)

          map[target] ||= queue[:name]
        end
      end

      def classify(queue, context)
        name = queue[:name]

        return [*context[:declared][name], nil] if context[:declared][name]
        return ["main", nil, nil] if context[:consumed].include?(name) || context[:anchored].include?(name)
        return ["retry", dead_letter_target(queue, context[:by_name]), nil] if retry_loop?(queue, context[:by_name])
        return ["error", context[:dead_letter_targets][name], nil] if context[:dead_letter_targets].key?(name)

        suffix_role(name, context[:by_name])
      end

      def suffix_role(name, by_name)
        %w[retry error].each do |role|
          base = name.chomp(".#{role}")
          return [role, base, nil] if base != name && by_name.key?(base)
        end
        ["main", nil, nil]
      end

      def queue_row(queue, role, parent, parent_exchange, application, delay)
        stats = queue[:message_stats] || {}
        args = queue[:arguments] || {}
        {
          name: queue[:name],
          role: role,
          parent: parent,
          parent_exchange: parent_exchange,
          type: queue[:type],
          state: queue[:state],
          messages: queue[:messages] || 0,
          ready: queue[:messages_ready] || 0,
          unacked: queue[:messages_unacknowledged] || 0,
          consumers: queue[:consumers] || 0,
          utilisation: queue[:consumer_utilisation],
          publish_rate: rate(stats[:publish_rate]),
          deliver_rate: rate(stats[:deliver_get_rate]),
          ack_rate: rate(stats[:ack_rate]),
          redeliver_rate: rate(stats[:redeliver_rate]),
          backlog_rate: rate(queue[:messages_ready_rate]),
          ttl: args["x-message-ttl"],
          dead_letter_exchange: args["x-dead-letter-exchange"],
          dead_letter_routing_key: args["x-dead-letter-routing-key"],
          expires: args["x-expires"],
          delay_ms: delay&.dig(:ms),
          target: delay&.dig(:target),
          target_type: delay&.dig(:target_type),
          idle_since: queue[:idle_since],
          application: application
        }
      end

      # Each exchange with what waits in its delay queues, and the
      # "<exchange>.delayed" headers exchanges that feed them marked with the
      # exchange they release to.
      def exchange_rows(exchanges, queues)
        waiting = delayed_by_target(queues, "exchange")
        names = exchanges.map { |e| e[:name] }.to_set
        exchanges.map do |exchange|
          held = waiting[exchange[:name]]
          releases_to = delay_front_of(exchange, names, waiting)
          exchange_row(exchange).merge(
            role: releases_to ? "delay" : nil,
            releases_to: releases_to,
            delayed: held ? held[:messages] : 0,
            delays: held ? held[:delays] : []
          )
        end
      end

      def delay_front_of(exchange, names, waiting)
        base = exchange[:name].to_s.delete_suffix(".delayed")
        return if base == exchange[:name] || Delay.exchange_name_for(base) != exchange[:name]

        base if waiting.key?(base) || (exchange[:type] == "headers" && names.include?(base))
      end

      def exchange_row(exchange)
        stats = exchange[:message_stats] || {}
        {
          name: exchange[:name],
          type: exchange[:type],
          durable: exchange[:durable],
          publish_in_rate: rate(stats[:publish_in_rate]),
          publish_out_rate: rate(stats[:publish_out_rate])
        }
      end

      def group_bindings(bindings)
        grouped = bindings.group_by { |b| [b[:source], b[:destination], b[:destination_type]] }
        grouped.map do |(source, destination, type), list|
          {
            source: source,
            destination: destination,
            destination_type: type,
            routing_keys: list.map { |b| b[:routing_key] }.reject(&:empty?).uniq,
            delays: list.filter_map { |b| (b[:arguments] || {})[Delay::HEADER] }.uniq.sort
          }
        end
      end

      # Keeps what the running consumers declared: their exchanges (and the
      # delayed exchanges in front of them), the queues those route to and
      # the retry, error and delay queues hanging off them. Without consumer
      # heartbeats nothing is known, so everything stays.
      def filter(exchanges, bindings, queues, heartbeat)
        known = heartbeat.map { |(_process, consumer)| consumer[:exchange] }.compact.to_set
        return [exchanges, bindings, queues] if known.empty?

        kept_exchanges = exchanges.select { |e| known.include?(e[:name]) || known.include?(e[:releases_to]) }
        exchange_names = kept_exchanges.map { |e| e[:name] }.to_set
        kept_bindings = bindings.select { |b| exchange_names.include?(b[:source]) }
        queue_names = kept_bindings.select { |b| b[:destination_type] == "queue" }.map { |b| b[:destination] }.to_set
        heartbeat.each { |(_process, consumer)| queue_names << consumer[:queue] if consumer[:queue] }
        kept_queues = queues.select do |q|
          queue_names.include?(q[:name]) || queue_names.include?(q[:parent]) || exchange_names.include?(q[:parent_exchange])
        end
        [kept_exchanges, kept_bindings, kept_queues]
      end

      def merge_consumers(heartbeat, subscriptions)
        merged = {}
        heartbeat.each do |(process, consumer)|
          entry = merged[[consumer[:queue], consumer[:class_name]]] ||= consumer_entry(consumer[:queue], consumer[:class_name], nil)
          entry[:reporting] = true
          entry[:application] ||= process[:application]
          entry[:processes] << {id: process[:id], name: process[:name], hostname: process[:hostname], pid: process[:pid]}
          entry[:threads] += consumer[:threads].to_i
          entry[:delays] |= Array(consumer[:delays])
          COUNTERS.each { |counter| entry[counter] += consumer[counter].to_i }
        end
        subscriptions.each do |subscription|
          class_name = subscription[:consumer_tag].to_s.sub(CONSUMER_TAG_INDEX, "")
          key = [subscription[:queue], class_name]
          key = [subscription[:queue], subscription[:connection_name]] unless merged.key?(key) && merged[key][:reporting]
          entry = merged[key] ||= consumer_entry(subscription[:queue], nil, subscription[:connection_name])
          entry[:channels] += 1
          entry[:prefetch] = [entry[:prefetch], subscription[:prefetch_count].to_i].max
        end
        merged.values
      end

      def consumer_entry(queue, class_name, connection_name)
        {
          queue: queue,
          class_name: class_name,
          connection_name: connection_name,
          application: nil,
          reporting: false,
          processes: [],
          threads: 0,
          channels: 0,
          prefetch: 0,
          processed: 0,
          rejected: 0,
          errored: 0,
          delayed: 0,
          delays: []
        }
      end

      def rate(value)
        value.to_f.round(2)
      end
    end
  end
end
