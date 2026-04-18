# Producers

A producer publishes messages to an exchange. It's a subclass of `Lepus::Producer` with a `configure` call and whatever convenience methods you want on top.

## Minimal example

```ruby
class OrdersProducer < Lepus::Producer
  configure(
    exchange: { name: 'orders', type: :topic, durable: true },
    publish:  { persistent: true }
  )

  use :json
  use :correlation_id
end
```

Publish from anywhere in your app:

```ruby
OrdersProducer.publish(
  { order_id: 42, total: 99.99 },
  routing_key: 'order.created'
)
```

## `configure` DSL

```ruby
configure(
  exchange: { name: 'orders', type: :topic, durable: true },
  publish:  { persistent: true, mandatory: false }
)
```

| Key | Purpose |
|-----|---------|
| `exchange` | String (name only) or hash (`name`, `type`, `durable`, `auto_delete`). Auto-declared on first publish. |
| `publish` | Default publish options merged into every `publish` call: `persistent`, `mandatory`, `content_type`, `expiration`, etc. |

## Publishing

```ruby
OrdersProducer.publish(payload, routing_key: 'order.created')
OrdersProducer.publish(payload, routing_key: 'order.paid', headers: { tenant_id: 123 })
OrdersProducer.publish(payload, routing_key: 'order.created', expiration: 60_000)
```

All Bunny publish options are supported. Frequently useful:

| Option | Purpose |
|--------|---------|
| `routing_key` | Routing key. |
| `persistent` | Persist the message across RabbitMQ restarts. |
| `headers` | Custom headers. |
| `correlation_id` | RPC pattern correlation. Auto-set by `:correlation_id` middleware. |
| `content_type` | MIME type. Auto-set to `application/json` by `:json` middleware. |
| `expiration` | Per-message TTL in milliseconds. |
| `mandatory` | Return the message if it can't be routed. |

## Payload types

- A Hash — pair with `:json` middleware to serialize.
- A String — sent as-is.
- Anything else — pair with a middleware that turns it into bytes.

## Middleware

```ruby
class OrdersProducer < Lepus::Producer
  use :json
  use :correlation_id
  use :instrumentation
  use :header, 'X-Service', 'orders-api'
end
```

Built-in producer middlewares:

| Name | Purpose |
|------|---------|
| `:json` | Serialize a hash into JSON; sets `content_type`. |
| `:correlation_id` | Auto-generate a UUID `correlation_id` if absent. |
| `:header` | Add a static or dynamic header: `use :header, 'X-Foo', 'bar'`. |
| `:instrumentation` | Emit `ActiveSupport::Notifications` events around each publish. |
| `:unique` | Reject duplicate publishes (by correlation id — needs external storage). |

Write your own — see [middleware.md](middleware.md).

## Convenience class methods

Wrap `publish` with domain-specific signatures:

```ruby
class OrdersProducer < Lepus::Producer
  configure(exchange: { name: 'orders', type: :topic, durable: true })
  use :json
  use :correlation_id

  def self.order_created(order)
    publish(
      { order_id: order.id, total: order.total, created_at: order.created_at },
      routing_key: 'order.created'
    )
  end

  def self.order_shipped(order)
    publish(
      { order_id: order.id, shipped_at: order.shipped_at },
      routing_key: 'order.shipped'
    )
  end
end

# In your code:
OrdersProducer.order_created(order)
```

## Connection pooling

Producers share a single connection pool across the process:

```ruby
Lepus.configure do |config|
  config.producer do |p|
    p.pool_size    = 5
    p.pool_timeout = 5.0
  end
end
```

## Enable / disable publishing

Useful when you want to disable side effects in tests or a specific environment.

```ruby
# Globally
Lepus::Producers.disable!
Lepus::Producers.enabled?(OrdersProducer)  # => false

# By producer class
Lepus::Producers.disable!(OrdersProducer)

# By exchange name
Lepus::Producers.disable!('orders')

# Block-scoped
Lepus::Producers.without_publishing do
  OrdersProducer.publish(...)  # no-op
end

Lepus::Producers.with_publishing do
  OrdersProducer.publish(...)  # forced through even if disabled
end
```

## Error handling

A publish can fail for many reasons — connection down, channel closed, etc. By default, Bunny retries with exponential backoff within `recovery_attempts`. For anything beyond that, you catch and handle it:

```ruby
begin
  OrdersProducer.order_created(order)
rescue Bunny::Exception => e
  Rails.logger.error("publish failed: #{e.message}")
  # queue for later retry, fall back to a DB outbox, etc.
end
```

## Testing

See [testing.md](testing.md) — there's a `Lepus::Testing.producer_messages(ProducerClass)` helper that captures publishes in-memory.
