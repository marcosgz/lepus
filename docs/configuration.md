# Configuration

Lepus is configured via a single block:

```ruby
Lepus.configure do |config|
  # ... see below ...
end
```

The configuration is mutable at boot and should be set once. Values are read lazily — most only matter at worker-start time.

## Connection

```ruby
Lepus.configure do |config|
  config.rabbitmq_url                    = ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')
  config.connection_name                 = 'my-service'
  config.recovery_attempts               = 10          # nil = infinite
  config.recover_from_connection_close   = true
end
```

| Key | Default | Purpose |
|-----|---------|---------|
| `rabbitmq_url` | `ENV['RABBITMQ_URL']` or `amqp://guest:guest@localhost:5672` | Connection string |
| `connection_name` | gem-generated | Shown in RabbitMQ management UI — set to your service name |
| `recovery_attempts` | `10` | Max automatic reconnects; `nil` for infinite |
| `recover_from_connection_close` | `true` | Auto-recover after a clean close |

## Application metadata

```ruby
config.application_name       = 'orders-service'
config.management_api_url     = 'http://rabbitmq:15672'   # only for :rabbitmq registry backend
```

Shown in the web dashboard. `management_api_url` is only required if `process_registry_backend = :rabbitmq`.

## Consumer discovery

```ruby
config.consumers_directory = 'app/consumers'
```

When present, `lepus start` with no class arguments auto-loads every class under this directory and runs all configured consumers.

## Worker pools

A **worker** is a subprocess the supervisor forks. Consumers are grouped into workers by their `process.name`.

```ruby
config.worker(:default) do |w|
  w.pool_size    = 5       # threads per worker
  w.pool_timeout = 10.0    # seconds before yielding to another task

  w.before_fork { ActiveRecord::Base.connection_handler.clear_all_connections! }
  w.after_fork  { ActiveRecord::Base.establish_connection }
end

config.worker(:high_priority, pool_size: 10)
```

| Key | Default | Purpose |
|-----|---------|---------|
| `pool_size` | `2` | Max threads per worker process |
| `pool_timeout` | `10.0` | Seconds threads wait on queue checkout |
| `before_fork` | no-op | Block run in parent before fork — close sockets, drop DB connections, etc. |
| `after_fork` | no-op | Block run in child after fork — reconnect, reseed RNG, etc. |

Assign consumers to a named worker via their own `configure(process: { name: :high_priority })` (see [consumers.md](consumers.md)).

## Producer pool

Producers share a connection pool:

```ruby
config.producer do |p|
  p.pool_size    = 5
  p.pool_timeout = 5.0
end
```

## Global middleware

Middleware chains run around every message published or consumed, in addition to any per-producer or per-consumer `use` calls.

```ruby
config.producer_middlewares do |chain|
  chain.use :instrumentation
  chain.use :correlation_id
end

config.consumer_middlewares do |chain|
  chain.use :json, symbolize_keys: true
end
```

See [middleware.md](middleware.md).

## Process registry

The supervisor keeps a registry of running processes, visible to the web dashboard.

```ruby
config.process_registry_backend     = :file      # or :rabbitmq
config.process_heartbeat_interval   = 60         # seconds
config.process_alive_threshold      = 5 * 60     # seconds
```

- `:file` — metadata in local files under `/tmp/lepus/...`. Single-host.
- `:rabbitmq` — metadata in RabbitMQ itself; multi-host visibility in the web dashboard.

## Rails integration

When Rails is loaded, a Railtie wires:

- `config.app_executor = Rails.application.executor` automatically
- `config.logger = Rails.logger`

You can override either:

```ruby
config.app_executor = nil             # disable executor wrapping
config.logger       = MyLogger.new
```

See [rails.md](rails.md).

## Threading error handler

```ruby
config.on_thread_error = ->(exception) {
  Rails.error.report(exception)
  Honeybadger.notify(exception)
}
```

Called when a worker thread raises. Does not stop the worker.

## Logger

```ruby
config.logger = Logger.new($stdout)
```

Default: `Logger.new($stdout)` (or `Rails.logger` if Rails is present). The `--debug` CLI flag sets the level to DEBUG.

## Full example

```ruby
Lepus.configure do |config|
  config.rabbitmq_url    = ENV.fetch('RABBITMQ_URL')
  config.connection_name = 'orders-service'
  config.application_name = 'orders-service'
  config.consumers_directory = 'app/consumers'

  config.worker(:default) do |w|
    w.pool_size = 5
    w.before_fork { ActiveRecord::Base.connection_handler.clear_all_connections! }
    w.after_fork  { ActiveRecord::Base.establish_connection }
  end

  config.producer_middlewares do |chain|
    chain.use :instrumentation
    chain.use :correlation_id
  end

  config.on_thread_error = ->(exc) { Honeybadger.notify(exc) }
end
```
