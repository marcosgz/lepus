# Getting Started

## Install

```ruby
# Gemfile
gem 'lepus'
```

```bash
bundle install
```

You'll also need a running RabbitMQ instance. For local dev:

```bash
docker run -d --rm -p 5672:5672 -p 15672:15672 rabbitmq:3-management
```

## Configure

```ruby
# config/initializers/lepus.rb (Rails) or your bootstrap file
Lepus.configure do |config|
  config.rabbitmq_url    = ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')
  config.connection_name = 'my-service'
end
```

See [configuration.md](configuration.md) for the full DSL.

## Define a consumer

```ruby
# app/consumers/orders_consumer.rb
class OrdersConsumer < Lepus::Consumer
  configure(
    queue:       'orders',
    exchange:    { name: 'orders', type: :topic, durable: true },
    routing_key: ['order.*']
  )

  use :json, symbolize_keys: true

  def perform(message)
    # message.payload       => the decoded JSON body (a hash, due to the :json middleware)
    # message.delivery_info => exchange, routing_key, redelivered?
    # message.metadata      => headers, content_type, correlation_id, etc.
    Order.create!(message.payload)
    :ack
  end
end
```

The `perform` method returns a symbol indicating disposition:

- `:ack` — acknowledge; RabbitMQ removes the message.
- `:reject` — reject; message is dropped (or routed to a dead-letter exchange if configured).
- `:requeue` — reject and requeue for another delivery attempt.
- `:nack` — negative-ack without requeue (similar to `:reject`).

`ack!`, `reject!`, `requeue!`, `nack!` are also available as helper methods.

## Define a producer

```ruby
# app/producers/orders_producer.rb
class OrdersProducer < Lepus::Producer
  configure(
    exchange: { name: 'orders', type: :topic, durable: true },
    publish:  { persistent: true }
  )

  use :json
  use :correlation_id
end
```

Publish:

```ruby
OrdersProducer.publish(
  { order_id: 42, total: 99.99 },
  routing_key: 'order.created'
)
```

## Run

### One-off (development)

```bash
bundle exec lepus start OrdersConsumer
```

Flags worth knowing:

```bash
bundle exec lepus start OrdersConsumer PaymentsConsumer \
  --require_file config/environment.rb \
  --debug
```

See [cli.md](cli.md).

### As a long-running service

In production, run `lepus start` with all your consumer classes (or auto-load them — see below) under your favorite process supervisor (systemd, Foreman, Kamal, Kubernetes).

Auto-load consumers from a directory:

```ruby
Lepus.configure do |config|
  config.consumers_directory = 'app/consumers'
end
```

```bash
bundle exec lepus start   # with no class args, starts all consumers from consumers_directory
```

## Monitor

```bash
bundle exec lepus web --port 9292
```

Visit http://localhost:9292 to see consumer status, throughput, and recent activity. See [web.md](web.md).

## Next steps

- [Consumers](consumers.md) — full consumer DSL, retries, error handling
- [Producers](producers.md) — exchange config, publishing options, hooks
- [Middleware](middleware.md) — built-in middlewares and writing your own
- [Supervisor](supervisor.md) — process model, graceful shutdown, worker pools
- [Rails integration](rails.md) — Railtie, executor wrapping
