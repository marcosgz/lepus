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
  publish:  { persistent: true, mandatory: false },
  connection: :default
)
```

| Key | Purpose |
|-----|---------|
| `exchange` | String (name only) or hash (`name`, `type`, `durable`, `auto_delete`). Auto-declared on first publish. |
| `publish` | Default publish options merged into every `publish` call: `persistent`, `mandatory`, `content_type`, `expiration`, etc. |
| `connection` | Named connection to publish through. Defaults to `:default` (`rabbitmq_url`). See [Named connections](#named-connections). |
| `delays` | Only delays (ms) accepted by `publish(..., delay:)`; anything else raises `Lepus::Error`. See [Delayed messages](#delayed-messages). |

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
| `delay` | Deliver the message after this many milliseconds (Integer, Float or anything responding to `in_milliseconds`). Lepus option, never sent to Bunny. See [Delayed messages](#delayed-messages). |

## Delayed messages

```ruby
OrdersProducer.publish(payload, routing_key: 'order.reminder', delay: 30_000)
OrdersProducer.publish(payload, routing_key: 'order.reminder', delay: 5.minutes) # ActiveSupport::Duration
Lepus::Publisher.new('orders').publish(payload, routing_key: 'order.reminder', delay: 30_000)
```

A default can be set with `configure(publish: { delay: 1_000 })`. Middlewares run as usual and don't see `delay` among the publish options.

### How it works

RabbitMQ has no delayed delivery without the `rabbitmq_delayed_message_exchange` plugin, so Lepus builds it from TTL queues and dead-lettering. For a target exchange `orders` and a delay of 30000 ms, Lepus declares on first use:

| Resource | Details |
|----------|---------|
| `orders.delayed` | Durable headers exchange. Delayed messages are published here with the original routing key plus the `lepus-delay: 30000` header. |
| `orders.delayed.30000` | Durable queue bound to `orders.delayed` with `x-match: all, lepus-delay: 30000`. Arguments: `x-message-ttl: 30000`, `x-dead-letter-exchange: orders`, `x-expires` (see below). |

When the TTL expires RabbitMQ dead-letters the message into `orders`. There's no `x-dead-letter-routing-key`, so it keeps its original routing key and headers, which works for topic, direct, fanout and headers exchanges. The delivered message also carries the `lepus-delay` header and RabbitMQ's `x-death` header.

The delay header has no `x-` prefix on purpose: with `x-match: all`, RabbitMQ ignores `x-` binding arguments, so every delay queue would receive every message.

Each delay value has its own queue with a per-queue TTL, so there's no head-of-line blocking: a 1 second delay published after a 1 hour delay still arrives after 1 second. Every distinct value creates a queue, so prefer a small set of fixed delays (e.g. 1s, 30s, 5min) over computed ones. Configure the producer with `delays: [1_000, 30_000, 300_000]` to reject any other value with `Lepus::Error` before publishing; Lepus also logs at info level the first time each process declares a delay queue.

Lepus doesn't use per-message `expiration` for delays, but one you pass is still applied inside the delay queue: RabbitMQ uses the lower of the two TTLs, so `expiration: 10_000, delay: 60_000` arrives after 10 seconds, and it drops `expiration` when dead-lettering, so the delivered message no longer has it.

### Queue expiry

Delay queues get `x-expires` set to the delay plus `config.delay_queue_expires` (default 1 hour), so queues for delays you no longer use are deleted by RabbitMQ, together with any message still in them. Publishing doesn't count as queue usage, so while a process keeps publishing a delay, Lepus re-declares its queue at least every `delay_queue_expires / 2` (and at least once a minute). A message published at any time therefore expires before its queue does. Set `config.delay_queue_expires = nil` to keep delay queues forever.

Queue arguments can't change once a queue exists. If you change `delay_queue_expires`, publishing to an existing delay queue raises `Lepus::Error` naming the queue. Keep the previous value, or delete the queue (it only holds messages still waiting) and restart every process that publishes delays in the same deploy: until a process re-declares a deleted queue (up to a minute later), its delayed messages for that queue are dropped.

### Declarations

Declarations are memoized per connection, delay queue and arguments, and run on a short-lived channel, so a failure doesn't close the channel used for publishing.

`mandatory` and publisher confirms only cover the publish into the delay exchange or queue. Dead-lettering into the target when the TTL expires is not subject to them: if the target exchange doesn't exist, or no binding matches the routing key at that moment, RabbitMQ drops the message without a return or nack. Publishing through the producer declares the exchange, but the bindings must also be in place when the delay ends.

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

Producers share one connection pool per named connection across the process:

```ruby
Lepus.configure do |config|
  config.producer do |p|
    p.pool_size    = 5
    p.pool_timeout = 5.0
  end
end
```

## Named connections

Register extra brokers in the configuration (see [configuration.md](configuration.md#named-connections)):

```ruby
Lepus.configure do |config|
  config.connection(:replica, url: ENV.fetch('REPLICA_RABBITMQ_URL'))
end
```

Then choose the connection per producer or per call. The per-call value wins, then the one in `configure`, then `:default`:

```ruby
class AuditProducer < Lepus::Producer
  configure(exchange: 'audit', connection: :replica)
end

OrdersProducer.publish(payload, routing_key: 'order.created')                       # :default
OrdersProducer.publish(payload, routing_key: 'order.created', connection: :replica) # :replica
AuditProducer.publish(payload)                                                      # :replica
```

`connection` is never sent to Bunny as a publish option. Each connection gets its own lazily created pool, so a broker that is down only affects the publishes routed to it. An unregistered name raises `Lepus::InvalidConnectionError`.

The low-level publisher takes the same option: `Lepus::Publisher.new('audit', connection: :replica)`.

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
