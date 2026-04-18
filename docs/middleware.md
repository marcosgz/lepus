# Middleware

Lepus middlewares form a chain around each message — both for producers (around each publish) and consumers (around each delivery). Every middleware gets the message and the next app in the chain:

```ruby
class MyMiddleware < Lepus::Middleware
  def initialize(option: nil)
    @option = option
  end

  def call(message, app)
    # pre-processing
    new_message = message.mutate(payload: transform(message.payload))
    # pass down the chain (and let the consumer/publisher actually run)
    result = app.call(new_message)
    # post-processing
    result
  end

  private

  def transform(payload) = payload
end
```

## Registering

### Per consumer / per producer

```ruby
class OrdersConsumer < Lepus::Consumer
  use :json, symbolize_keys: true        # built-in by symbol
  use :max_retry, retries: 5
  use MyMiddleware, option: 'value'      # your own class
end
```

### Globally

```ruby
Lepus.configure do |config|
  config.consumer_middlewares do |chain|
    chain.use :json, symbolize_keys: true
    chain.use :exception_logger
  end

  config.producer_middlewares do |chain|
    chain.use :json
    chain.use :correlation_id
    chain.use :instrumentation
  end
end
```

Global middlewares run **before** per-class middlewares.

## Built-in consumer middlewares

### `:json`

Parse the payload from JSON.

```ruby
use :json, symbolize_keys: true, on_error: proc { :reject }
```

Options:

- `symbolize_keys: true` — hash keys become symbols.
- `on_error:` — a callable that takes the exception; its return becomes the disposition (default: `:reject`).

### `:max_retry`

Track retry count via RabbitMQ `x-death` headers and route to an error queue after N attempts.

```ruby
use :max_retry, retries: 5, error_queue: 'orders.error'
```

Requires the consumer's `configure` to declare a `retry_queue:` so requeued messages loop through a delay queue.

### `:exception_logger`

Catch exceptions from downstream middlewares/perform, log with backtrace, then re-raise (so higher-level error handling still sees the exception).

```ruby
use :exception_logger
```

### `:honeybadger`

Notify Honeybadger on exceptions. Requires the `honeybadger` gem.

```ruby
use :honeybadger
```

### `:unique`

Dedupe messages by `correlation_id`. Requires a storage backend (your code wires Redis or similar).

```ruby
use :unique, store: MyRedisStore
```

## Built-in producer middlewares

### `:json`

Serialize a hash payload as JSON; set `content_type` to `application/json`.

```ruby
use :json
```

### `:correlation_id`

Auto-generate a UUID correlation id if one isn't already set on the message.

```ruby
use :correlation_id
```

### `:header`

Add headers to every publish.

```ruby
use :header, 'X-Service', 'orders-api'
use :header, 'X-Request-Id', -> { Current.request_id }
```

The value can be a static value or a callable.

### `:instrumentation`

Emit `ActiveSupport::Notifications` events before and after each publish. Event name: `publish.lepus`.

```ruby
use :instrumentation
```

Subscribe:

```ruby
ActiveSupport::Notifications.subscribe('publish.lepus') do |name, start, finish, id, payload|
  puts "published to #{payload[:exchange]} in #{(finish - start) * 1000}ms"
end
```

### `:unique`

Drop duplicate publishes. Requires a storage backend.

```ruby
use :unique, store: MyRedisStore
```

## Writing your own

### Consumer middleware

```ruby
class LogLevelMiddleware < Lepus::Middleware
  def initialize(level: :info)
    @level = level
  end

  def call(message, app)
    Lepus.logger.public_send(@level, "Processing: #{message.payload.inspect}")
    app.call(message)
  end
end

class OrdersConsumer < Lepus::Consumer
  use LogLevelMiddleware, level: :debug
end
```

### Producer middleware

Same interface. Typical use: decorate the message with metadata before it's published.

```ruby
class TenantScopingMiddleware < Lepus::Middleware
  def call(message, app)
    with_tenant = message.mutate(metadata: message.metadata.merge(headers: message.metadata[:headers].merge('X-Tenant-Id' => Current.tenant_id)))
    app.call(with_tenant)
  end
end
```

### Mutating a message

`message.mutate(**kwargs)` returns a new message with updated fields — payload, metadata, delivery_info. Don't mutate in place; build a new one and pass it down.

```ruby
app.call(message.mutate(payload: transformed_payload))
```

## Order of execution

For a consumer:

```
incoming delivery
  → global consumer middlewares (in config order)
  → per-consumer middlewares (in class-file order)
  → perform(message)
  → each middleware unwinds (post-processing)
  → disposition returned
```

For a producer:

```
publish(payload)
  → per-producer middlewares
  → global producer middlewares
  → Bunny publish
  → unwind
```

## Conditional middleware

Middleware can decide not to call the next app — effectively short-circuiting:

```ruby
class SkipDuringMaintenanceMiddleware < Lepus::Middleware
  def call(message, app)
    if Feature.maintenance_mode?
      Lepus.logger.warn('skipping publish during maintenance')
      return  # do NOT call app.call(message)
    end
    app.call(message)
  end
end
```

For consumers, returning early means the consumer's `perform` never runs. The return value of `call` becomes the disposition.
