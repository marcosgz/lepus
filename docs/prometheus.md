# Prometheus metrics

Lepus ships an optional integration with [`prometheus_exporter`](https://github.com/discourse/prometheus_exporter). Consumer and producer processes forward metric payloads over TCP to a collector server; Prometheus scrapes the collector's `/metrics` endpoint.

## Requirements

- `prometheus_exporter` in your Gemfile.
- A collector server reachable from every process that calls `require "lepus/prometheus"`. Typically this is the Lepus supervisor process itself, listening on `localhost:9394` (so forked workers can reach it without networking changes).

## Enabling instrumentation

In each process that runs Lepus (supervisor + workers), load:

```ruby
require "lepus/prometheus"
```

This prepends instrumentation onto `Lepus::Consumers::Handler` and `Lepus::Consumers::Worker` and subscribes to the `publish.lepus` `ActiveSupport::Notifications` event. Requiring must happen before the supervisor forks workers so every child inherits the instrumentation.

## Starting the collector server

Run the collector inside the supervisor so forked workers can send metrics to `localhost:9394`:

```ruby
# config/initializers/lepus.rb
require "lepus/web"

if Rails.application.config.prometheus_enabled
  require "lepus/prometheus"
  require "lepus/prometheus/collector"
end

Lepus.configure do |config|
  # …
end

if Rails.application.config.prometheus_enabled
  Lepus::Supervisor.on_start do
    require "prometheus_exporter/server"

    collector = PrometheusExporter::Server::Collector.new
    collector.register_collector(Lepus::Prometheus::Collector.new)

    server = PrometheusExporter::Server::WebServer.new(
      port: 9394,
      bind: "0.0.0.0",
      collector: collector
    )
    server.start
  end
end
```

Point Prometheus at `<lepus-host>:9394` in your scrape config.

## Polling RabbitMQ queue stats

Queue depth is not published by the workers — it's pulled from the RabbitMQ Management API by a poller thread. Start it from `on_start`:

```ruby
Lepus::Supervisor.on_start do
  Lepus::Prometheus.watch_queues(interval: 30)
end
```

The poller emits a `lepus_queue_poll_last_success_timestamp_seconds` gauge after each successful API round-trip and a `lepus_queue_poll_errors_total` counter on failure — alert on stale timestamps to catch a silently broken poller.

## Metrics

| Metric | Type | Labels |
| --- | --- | --- |
| `lepus_messages_processed_total` | counter | `consumer`, `queue`, `result` (`ack`/`reject`/`requeue`/`nack`/`error`), `error` (exception class, empty on success) |
| `lepus_delivery_duration_seconds` | histogram | `consumer`, `queue` |
| `lepus_messages_published_total` | counter | `exchange`, `routing_key` |
| `lepus_publish_duration_seconds` | histogram | `exchange`, `routing_key` |
| `lepus_process_rss_memory_bytes` | gauge | `kind`, `name` |
| `lepus_process_info` | gauge (always `1`) | `kind`, `name`, `pid`, `hostname` |
| `lepus_queue_messages` | gauge | `name` |
| `lepus_queue_messages_ready` | gauge | `name` |
| `lepus_queue_messages_unacknowledged` | gauge | `name` |
| `lepus_queue_consumers` | gauge | `name` |
| `lepus_queue_memory_bytes` | gauge | `name` |
| `lepus_queue_poll_last_success_timestamp_seconds` | gauge | — |
| `lepus_queue_poll_errors_total` | counter | `error` |

`result="error"` is recorded for every delivery that raises out of the consumer, alongside the exception class — queryable as `rate(lepus_messages_processed_total{result="error"}[5m])`.

## Configuration

```ruby
Lepus.configure do |config|
  # Histogram buckets (in seconds) used for delivery and publish latency.
  config.prometheus_buckets = [0.01, 0.05, 0.1, 0.5, 1, 5]
end
```

To send metrics to a collector on a different host:

```ruby
require "prometheus_exporter/client"
Lepus::Prometheus.client = PrometheusExporter::Client.new(host: "collector.internal", port: 9394)
```

## Standalone collector mode

You can also run `prometheus_exporter` as a separate process and load just the collector:

```sh
prometheus_exporter -a lepus/prometheus/collector
```

`lib/lepus/prometheus/collector.rb` deliberately does not require the rest of the gem, so this works without a full Lepus boot.
