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
| `retry_queue` | When truthy, sets up a retry queue with a delay exchange. Messages requeued via `:requeue` or `max_retry` go here. |
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

1. `max_retry` inspects `x-death` headers.
2. If retries are below the limit, it re-publishes to the retry queue.
3. After TTL, the retry queue dead-letters back to the original queue for another attempt.
4. After N failures, the middleware routes to the error queue.

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
