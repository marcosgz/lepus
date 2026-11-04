# Consumers

Consumers subscribe to a queue, receive messages, and process them. A consumer is a subclass of `Lepus::Consumer` with a `configure` call and a `perform` method.

## Minimal example

```ruby
class OrdersConsumer < Lepus::Consumer
  configure(
    queue:    'orders',
    exchange: { name: 'orders', type: :topic, durable: true },
    routing_key: ['order.*']
  )

  use :json, symbolize_keys: true

  def perform(message)
    Order.create!(message.payload)
    :ack
  end
end
```

## `configure` DSL

```ruby
configure(
  queue:       'orders',                                    # string or hash
  exchange:    { name: 'orders', type: :topic, durable: true },
  routing_key: ['order.*', 'invoice.created'],              # array or string
  prefetch:    1,                                            # channel QoS
  retry_queue: { delay: 5_000 },                            # or true, or false
  error_queue: true,                                         # or queue name, or false
  process:     { name: :default, threads: 5 },              # worker assignment
  channel:     { pool_size: 1, shutdown_timeout: 60, abort_on_exception: false }
)
```

| Key | Purpose |
|-----|---------|
| `queue` | The queue name — string, or a hash for advanced options (`name`, `durable`, `arguments`, …). |
| `exchange` | Bind to this exchange. String, or hash (`name`, `type`, `durable`, `auto_delete`). |
| `routing_key` | Binding routing key(s). |
| `prefetch` | Channel QoS (`basic.qos`). Leave at `1` unless you know you need more. |
| `retry_queue` | When truthy, declares a `<queue>.retry` queue and dead-letters rejected messages into it; after `delay` ms they return to the queue. Only `:reject` (and a `perform` that raises, which rejects) goes there; `:requeue` and `:nack` put the message straight back on the queue. |
| `error_queue` | Queue name (string) or `true` to auto-name. Messages that exhaust retries land here. |
| `process.name` | The named worker pool this consumer runs in — see `Lepus.configure.worker(:name)`. |
| `process.threads` | Threads inside the consumer's worker dedicated to this consumer. |

## The `perform` method

```ruby
def perform(message)
  # ...
end
```

`message` is a `Lepus::Message` with:

- `#payload` — the decoded body (raw bytes, or parsed data if a decoding middleware is in the chain).
- `#delivery_info` — `#exchange`, `#routing_key`, `#redelivered?`, `#delivery_tag`, `#consumer_tag`.
- `#metadata` — `#headers`, `#content_type`, `#content_encoding`, `#correlation_id`, `#message_id`, `#reply_to`, `#type`, `#timestamp`, `#user_id`, `#app_id`, `#priority`.

Return a disposition symbol or call one of the helpers:

| Return | Helper | Effect |
|--------|--------|--------|
| `:ack` | `ack!` | Acknowledge the message. |
| `:reject` | `reject!` | Reject without requeue (drops, or goes to DLX if configured). |
| `:requeue` | `requeue!` | Reject with requeue — back of the queue. |
| `:nack` | `nack!` | Negative-ack. |
| `:ack` | `delay!(ms)` | Re-deliver the message to this queue after `ms` milliseconds, then ack it. See [Delaying a message](#delaying-a-message). |

A `perform` that returns nothing implicitly acks. A `perform` that raises is logged, `on_thread_error` fires, and the message is rejected.

## Middleware

Add middlewares to a consumer with `use`:

```ruby
class OrdersConsumer < Lepus::Consumer
  use :json, symbolize_keys: true
  use :max_retry, retries: 5, error_queue: 'orders.error'
  use :exception_logger
  use :honeybadger
end
```

Built-in middlewares:

| Name | Purpose |
|------|---------|
| `:json` | Parse JSON body into a hash. |
| `:max_retry` | Track `x-death` headers; after N retries, route to error queue. |
| `:exception_logger` | Log unhandled exceptions with backtrace. |
| `:honeybadger` | Notify Honeybadger on exceptions. |
| `:unique` | Idempotent dedupe by `correlation_id` (requires storage). |

Write your own — see [middleware.md](middleware.md).

## Error handling

A `perform` that raises:

1. The message is rejected by default.
2. `config.on_thread_error` is called with the exception.
3. If `:exception_logger` middleware is in the chain, it logs with backtrace.
4. If `:max_retry` is in the chain, it tracks retry count via RabbitMQ's `x-death` header and redirects to an error queue after N rejections.

## Retries

The built-in retry pattern uses RabbitMQ's dead-letter machinery:

```ruby
configure(
  queue:       'orders',
  exchange:    { name: 'orders', type: :topic, durable: true },
  routing_key: 'order.*',
  retry_queue: { delay: 5_000 },  # 5-second delay before retry
  error_queue: 'orders.error'
)
use :max_retry, retries: 5, error_queue: 'orders.error'
```

On rejection:

1. The rejected message is dead-lettered into the retry queue.
2. After the TTL, the retry queue dead-letters it back to the original queue for another attempt.
3. On each delivery `max_retry` counts the `rejected` entries of the `x-death` header.
4. Once the rejected count exceeds `retries` (the first attempt plus N retries), the middleware publishes the payload, without headers or properties, to the error queue and acks the message.

## Delaying a message

`delay!(ms)` (aliased `delay`) puts the message being processed back on this consumer's queue after `ms` milliseconds and acks the current delivery. Use it when the work can't be done yet, e.g. waiting for a replica to catch up:

```ruby
class ReindexConsumer < Lepus::Consumer
  configure(queue: 'reindex', exchange: 'stories', routing_key: 'story.published')
  use :json

  MAX_DELAYS = 3

  def perform(message)
    attempts = message.metadata.headers.to_h['x-lepus-delayed-count'].to_i
    return delay!(5_000) if replica_behind? && attempts < MAX_DELAYS

    reindex(message.payload)
    ack!
  end
end
```

It accepts milliseconds or anything responding to `in_milliseconds` (`5.seconds`). No configuration is needed:

- The message is re-published as received (raw payload, headers and properties, before middlewares changed it), minus `expiration`, through the default exchange to a `reindex.delay.5000` queue with `x-message-ttl: 5000` that dead-letters into `reindex`. The `.delay.` infix keeps it apart from the `<exchange>.delayed.<ms>` queues of producer delays, even when the queue and exchange share a name. Only this queue gets it again, not other queues bound to the exchange.
- The `x-lepus-delayed-count` header is incremented on each delay, so you can cap your own backoff.
- The redelivery arrives with routing key `reindex` (the queue name), like retries do. Put anything you route on in the payload or headers.
- The queue is declared on first use and gets `x-expires` like producer delays; see [Queue expiry](producers.md#queue-expiry).
- `max_retry` ignores delays: it only counts `rejected` deaths, while delay queues produce `expired` ones.
- `delay!` returns `:ack`, so the `:unique` middleware releases the dedupe lock under the default `release_on: [:ack]`. Duplicates published during the delay are not suppressed, and the redelivered message doesn't hold a lock.

`delay!` must be called from `perform`; outside a delivery it raises `Lepus::Error`. Any publish to the default exchange can be delayed the same way: `Lepus::Publisher.new('').publish(payload, routing_key: 'reindex', delay: 5_000)`.

## Worker assignment

Assign a consumer to a named worker pool:

```ruby
configure(
  queue:    'orders',
  exchange: { name: 'orders', type: :topic },
  process:  { name: :high_priority, threads: 10 }
)
```

Then in the global config:

```ruby
Lepus.configure do |config|
  config.worker(:high_priority) do |w|
    w.pool_size = 20
  end
end
```

Consumers assigned to the same worker share a single subprocess.

## Logging

Inside `perform`, `logger` is the Lepus logger (tagged with the consumer class name):

```ruby
def perform(message)
  logger.info("processing #{message.delivery_info.routing_key}")
  # ...
end
```

## Testing

See [testing.md](testing.md) for the test-mode helpers.
