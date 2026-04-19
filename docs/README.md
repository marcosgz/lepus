# lepus

RabbitMQ-backed producer/consumer framework for Ruby — with a supervisor, middleware chains, a CLI, and a live web dashboard.

Think Sidekiq or SolidQueue, but on top of RabbitMQ rather than Redis or a database. Lepus handles the operational concerns (process supervision, graceful shutdown, connection pooling, signal handling, per-worker pools) so your application code can stay focused on "what does this message do".

## Contents

- [Getting started](getting-started.md) — install, define your first consumer and producer, run them
- [Configuration](configuration.md) — the full `Lepus.configure` DSL
- [Consumers](consumers.md) — queue bindings, lifecycle, result codes, retries
- [Producers](producers.md) — exchanges, publishing, enable/disable hooks
- [Middleware](middleware.md) — built-in middlewares and how to write your own
- [CLI](cli.md) — `lepus start`, `lepus web`
- [Supervisor](supervisor.md) — process model, signals, graceful shutdown
- [Web dashboard](web.md) — the monitoring UI
- [Testing](testing.md) — testing consumers and producers
- [Rails integration](rails.md) — Railtie, executor wrapping, Puma plugin

## Install

```ruby
# Gemfile
gem 'lepus'
```

## One-minute tour

```ruby
# config/initializers/lepus.rb
Lepus.configure do |config|
  config.rabbitmq_url   = ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')
  config.connection_name = 'my-service'
end

# app/consumers/orders_consumer.rb
class OrdersConsumer < Lepus::Consumer
  configure(
    queue:       'orders',
    exchange:    { name: 'orders', type: :topic, durable: true },
    routing_key: ['order.*']
  )

  use :json, symbolize_keys: true
  use :max_retry, retries: 5

  def perform(message)
    Order.create!(message.payload)
    :ack
  end
end

# app/producers/orders_producer.rb
class OrdersProducer < Lepus::Producer
  configure(exchange: { name: 'orders', type: :topic, durable: true })
  use :json
  use :correlation_id
end
```

Run the consumer:

```bash
bundle exec lepus start OrdersConsumer
```

Publish from anywhere in your app:

```ruby
OrdersProducer.publish({ order_id: 42, total: 99.99 }, routing_key: 'order.created')
```

## Version & dependencies

- Ruby: `>= 2.7.0`
- Runtime: `bunny`, `thor`, `zeitwerk`, `concurrent-ruby`, `multi_json`

## License

MIT.
