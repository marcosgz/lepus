# Lepus


Lepus is a lightweight but powerful Ruby library to help you to consume and produce messages to [RabbitMQ](https://www.rabbitmq.com/) using the [Bunny](https://github.com/ruby-amqp/bunny) gem. It's similar to the Sidekiq, Faktory, ActiveJob, SolidQueue, and other libraries, but using RabbitMQ as the message broker.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'lepus'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install lepus
```

## Usage


## Configuration

You can configure the Lepus using the `Lepus.configure` method.

```ruby
Lepus.configure do |config|
  config.connection_name = 'MyApp'
  config.rabbitmq_url = ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')
end
```

The configuration options are:

- `rabbitmq_url`: The RabbitMQ host. Default: to `RABBITMQ_URL` environment variable or `amqp://guest:guest@localhost:5672`.
- `connection_name`: The connection name. Default: `Lepus`.
- `recovery_attempts`: The number of attempts to recover the connection. Nil means infinite. Default: `10`.
- `recover_from_connection_close`: If the connection should be recovered when it's closed. Default: `true`.
- `app_executor`: The [Rails executor](https://guides.rubyonrails.org/threading_and_code_execution.html#executor) used to wrap asynchronous operations. Only available if you are using Rails. Default: `nil`.
- `on_thread_error`: The block to be executed when an error occurs on the thread. Default: `nil`.
- `process_heartbeat_interval`: The interval in seconds between heartbeats. Default is `60 seconds`.
- `process_heartbeat_timeout`: The timeout in seconds to wait for a heartbeat. Default is `10 seconds`.
- `worker`: A block to configure the worker process that will run the consumers. You can set the `pool_size`, `pool_timeout`, and before/after fork callbacks inline options or using a block. Main worker is `:default`, but you can define more workers with different names for different consumers.
- `logger`: The logger instance. Default: `Logger.new($stdout)`.

### Configuration > Producer

Lepus can be used to both **produce** and **consume** RabbitMQ events. Producers and consumers use separate connection pools, allowing for efficient and isolated message publishing and processing.

You can configure the producer connection pool using the `producer` method inside the configuration block:

```ruby
Lepus.configure do |config|
  # Block
  config.producer do |c|
    c.pool_size = 2
    c.pool_timeout = 10.0
  end
  # Inline
  config.producer(pool_size: 1, pool_timeout: 5.0)
end
```

Once configured, you can use `Lepus::Publisher` to publish messages to RabbitMQ exchanges:

```ruby
# Create a publisher for a specific exchange
publisher = Lepus::Publisher.new("my_exchange", type: :topic, durable: true)

# Publish a string message
publisher.publish("Hello, RabbitMQ!")

# Publish a JSON message (automatically serialized)
publisher.publish({user_id: 123, action: "login"}, routing_key: "user.login")

# Publish with custom options
publisher.publish("Important message",
  routing_key: "notifications.urgent",
  expiration: 30000,
  priority: 10
)
```

### Using Lepus::Producer

For a more structured approach, you can use `Lepus::Producer` to define reusable producer classes with pre-configured exchange settings:

```ruby
# Define a producer with exchange configuration
class UserEventsProducer < Lepus::Producer
  configure(exchange: "user_events")
end

# Define a producer with detailed exchange and publish options
class OrderEventsProducer < Lepus::Producer
  configure(
    exchange: {
      name: "order_events",
      type: :direct,
      durable: true
    },
    publish: {
      persistent: true,
      mandatory: false
    }
  )
end

# Define a producer with block configuration
class NotificationProducer < Lepus::Producer
  configure(exchange: "notifications") do |definition|
    definition.publish_options[:persistent] = true
  end
end

# Usage examples:

# Publish using class methods
UserEventsProducer.publish("User created: 123")
OrderEventsProducer.publish(
  { order_id: 456, status: "created" },
  routing_key: "order.created"
)

# Publish using instance methods
producer = NotificationProducer.new
producer.publish(
  { message: "Welcome!", user_id: 789 },
  routing_key: "user.welcome"
)
```

The `Lepus::Producer` class provides:
- **Pre-configured exchanges**: Define exchange settings once in your producer class
- **Default publish options**: Set default publish behavior (persistent, mandatory, etc.)
- **Class and instance methods**: Use either `ProducerClass.publish()` or `producer_instance.publish()`
- **Block configuration**: Fine-tune settings using configuration blocks

### Producer Hooks

Lepus provides a powerful hooks system that allows you to control when producers can publish messages. This is particularly useful for testing, debugging, or temporarily disabling message publishing in specific environments.

#### Basic Usage

```ruby
# Disable all producers
Lepus::Producers.disable!

# Enable all producers
Lepus::Producers.enable!

# Disable specific producers
Lepus::Producers.disable!(UserEventsProducer, OrderEventsProducer)

# Enable specific producers
Lepus::Producers.enable!(UserEventsProducer)

# Disable by exchange name (affects all producers using that exchange)
Lepus::Producers.disable!("user_events", "order_events")

# Enable by exchange name
Lepus::Producers.enable!("notifications")

# Check if producers are enabled/disabled
Lepus::Producers.enabled?(UserEventsProducer)  # => true/false
Lepus::Producers.disabled?(UserEventsProducer) # => true/false
```

#### Block-based Control

The hooks system provides block-based methods for temporary control:

```ruby
# Temporarily disable publishing for a block
Lepus::Producers.without_publishing do
  # All producer.publish() calls will be ignored
  UserEventsProducer.publish("This won't be sent")
  OrderEventsProducer.publish("This won't be sent either")
end
# Publishing is automatically restored after the block

# Temporarily disable specific producers
Lepus::Producers.without_publishing(UserEventsProducer) do
  UserEventsProducer.publish("This won't be sent")      # Disabled
  OrderEventsProducer.publish("This will be sent")      # Still enabled
end

# Temporarily enable publishing for a block
Lepus::Producers.disable!
Lepus::Producers.with_publishing do
  # Publishing is temporarily enabled
  UserEventsProducer.publish("This will be sent")
end
# Publishing is automatically restored to disabled state
```

### Producer Middlewares

Producers support middlewares that can modify the message payload, headers, routing key, and other publish options before messages are sent to RabbitMQ. Middlewares are executed in the order they are registered.

#### Built-in Middlewares

* `:json`: Serializes Hash payloads to JSON and sets `content_type` to `application/json`.
* `:header`: Adds default headers to messages (static values or dynamic procs).
* `:correlation_id`: Auto-generates a `correlation_id` (UUID) if not already set.
* `:instrumentation`: Emits instrumentation events via `Lepus.instrument` for monitoring.

#### Per-Producer Middlewares

Use the `use` method to add middlewares to a specific producer:

```ruby
class OrderEventsProducer < Lepus::Producer
  configure(exchange: "order_events")

  use :json
  use :correlation_id
  use :header, defaults: {
    "app" => "my-service",
    "published_at" => -> { Time.now.iso8601 }
  }
end

# Messages will be serialized to JSON, have a correlation_id,
# and include the default headers
OrderEventsProducer.publish({ order_id: 123, status: "created" })
```

#### Global Producer Middlewares

You can configure middlewares that apply to all producers:

```ruby
Lepus.configure do |config|
  config.producer_middlewares do |chain|
    chain.use :instrumentation
    chain.use :correlation_id
  end
end
```

Global middlewares are executed before per-producer middlewares.

#### Custom Producer Middlewares

Create custom middlewares by extending `Lepus::Middleware` (same interface as consumer middlewares):

```ruby
class TimestampMiddleware < Lepus::Middleware
  def call(message, app)
    # Add a timestamp header
    current_headers = message.metadata.headers || {}
    new_headers = current_headers.merge("published_at" => Time.now.iso8601)

    new_metadata = Lepus::Message::Metadata.new(
      **message.metadata.to_h,
      headers: new_headers
    )

    # Pass the modified message to the next middleware
    app.call(message.mutate(metadata: new_metadata))
  end
end

class MyProducer < Lepus::Producer
  configure(exchange: "my_exchange")

  use TimestampMiddleware
end
```

### Configuration > Consumer Worker

You can configure the consumer process using the `worker` method. The default worker is named `:default`, but you can define more workers with different names for different consumers.

Configuration can be done inline or using a block:

```ruby
Lepus.configure do |config|
  # Block
  config.worker(:default) do |c|
    c.pool_size = 2
    c.pool_timeout = 10.0
    c.before_fork do
      ActiveRecord::Base.clear_all_connections!
    end
    c.after_fork do
      ActiveRecord::Base.establish_connection
    end
  end
  # Inline
  config.worker(:datasync, pool_size: 1, pool_timeout: 5.0)
end
```

The options are:
- `pool_size`: The number of threads in the pool. Default: `1`.
- `pool_timeout`: The timeout in seconds to wait for a thread to be available. Default: `5.0`.
- `before_fork`: A block to be executed before forking the process. Default: `nil`.
- `after_fork`: A block to be executed after forking the process. Default: `nil`.

To define a consumer, you need to create a class inheriting from `Lepus::Consumer` and implement the `perform` method. The `perform` method will be called when a message is received. Use the `configure` method to set the queue name, exchange name, and other options.

The example below defines a consumer with required settings:

```ruby
class MyConsumer < Lepus::Consumer
  configure(
    queue: "queue_name",
    exchange: "exchange_name",
    routing_key: %w[routing_key1 routing_key2],
  )

  def perform(message)
    puts "delivery_info: #{message.delivery_info}"
    puts "metadata: #{message.metadata}"
    puts "payload: #{message.payload}"

    ack!
  end
end
```

### Consumer Configuration

The `configure` method accepts the following options:

- **\*** `queue`: . The queue name or a Hash with the queue options. Default: `nil`.
- **\*** `exchange`: The exchange name or a Hash with the exchange options. Default: `nil`.
- `routing_key`: One or more routing keys. Default: `nil`.
- `bind`: The binding options. Default: `nil`.
- `retry_queue`: Boolean or a Hash to configure the retry queue. Default: `false`.
- `error_queue`: Boolean or a Hash to configure the error queue. Default: `false`.

Options marked with `*` are required.

You can pass a more descriptive configuration using a Hash with custom options for each part of message broker:

```ruby
class MyConsumer < Lepus::Consumer
  configure(
    queue: {
      name: "queue_name",
      durable: true,
      # You can set any other exchange options here
      # arguments: { 'x-message-ttl' => 60_000 }
    },
    exchange: {
      name: "exchange_name",
      type: :direct, # You may use :direct, :fanout, :topic, or :headers
      durable: true,
      # You can set any other exchange options here
      # arguments: { 'x-message-ttl' => 60_000 }
    },
    bind: {
      routing_key: %w[routing_key1 routing_key2]
    },
    retry_queue: { # As shortcut, you can just pass `true` to create a retry queue with default options below.
      name: "queue_name.retry",
      durable: true,
      delay: 5000,
    },
    error_queue: { # As shortcut, you can just pass `true` to create an error queue with default options below.
      name: "queue_name.error",
      durable: true,
    }
  )
  # ...
end
```

By declaring the `retry_queue` option, it will automatically create a queue named `queue_name.retry` and use the arguments `x-dead-letter-exchange` and `x-dead-letter-routing-key` to route rejected messages to it. When routed to the retry queue, messages will wait there for the number of milliseconds specified in `delay`, after which they will be redelivered to the original queue.
**Note that this will not automatically catch unhandled errors. You still have to catch any errors yourself and reject your message manually for the retry mechanism to work.**

It may result in a infinite loop if the message is always rejected. To avoid this, you can use the `error_queue` option to route the message to an `queue_name.error` queue after a number of attempts by using the `MaxRetry` middleware covered in the next section.

Refer to the [Dead Letter Exchanges](https://www.rabbitmq.com/docs/dlx) documentation for more information about retry.

### Middlewares

Consumers can use middlewares for recurring tasks like logging, error handling, parsing, and others. It comes with a few built-in middlewares:

* `:max_retry`: Rejects the message and routes it to the error queue after a number of attempts.
* `:json`: Parses the message payload as JSON.
* `:honeybadger`: Reports exceptions to Honeybadger.
* `:exception_logger`: Logs unhandled exceptions to `Lepus.logger` (or a custom logger) and re-raises.

You can use the `use` method to add middlewares to the consumer:

```ruby
class MyConsumer < Lepus::Consumer
  configure(...)

  # If you don't have an error-reporting middleware (e.g. Honeybadger, Airbrake),
  # add :exception_logger to ensure errors are actually logged.
  use(
    :exception_logger
  )

  use(
    :max_retry,
    retries: 6,
    error_queue: "queue_name.error" # The queue to route the message after the number of retries
  )

  use(
    :json,
    symbolize_keys: true,
    on_error: proc { :reject } # You can omit since the default value is :reject
  )

  def perform(message)
    puts message.payload[:name]
    ack!
  end
end
```

> Important: If you are not using an external error-reporting middleware like Honeybadger or Airbrake, make sure to add `:exception_logger` to all consumers. The worker execution flow rescues exceptions to keep the process alive; without a logging middleware, exceptions may be swallowed and go unnoticed. `:exception_logger` ensures the error message is written to your logs.

#### Global Consumer Middlewares

You can configure middlewares that apply to all consumers:

```ruby
Lepus.configure do |config|
  config.consumer_middlewares do |chain|
    chain.use :exception_logger
    chain.use :json, symbolize_keys: true
  end
end
```

Global middlewares are executed before per-consumer middlewares. This is useful for common cross-cutting concerns like logging or JSON parsing that you want applied consistently across all consumers.

You can also create your own middlewares, just create subclasses of `Lepus::Middleware` and implement the `call` method:

```ruby
class MyMiddleware < Lepus::Middleware
  def initialize(**options)
    @options = options
  end

  def call(message, app
    # Do something before calling the next middleware
    app.call(message)
  end
end
```

### Unique Middleware (Experimental)

> **Note:** This feature is experimental and may change in future versions.

The unique middleware prevents duplicate messages from being published using Redis-based distributed locking via the [de-dupe](https://github.com/marcosgz/de-dupe) gem. It works as a pair: the **producer middleware acquires a lock** before publishing, and the **consumer middleware releases the lock** after successful processing (`:ack`).

Multiple producers can share the same lock namespace. For example, `StoryCreatedProducer` and `StoryUpdatedProducer` can both use `lock_key: "story"` to prevent duplicate processing of the same story.

#### Setup

Add the `de-dupe` gem to your Gemfile:

```ruby
gem 'de-dupe'
```

Configure DeDupe with Redis, then require the middleware:

```ruby
# In an initializer or application setup:
DeDupe.configure do |config|
  config.redis = Redis.new(url: ENV["REDIS_URL"])
end

require "lepus/unique"
```

The `require "lepus/unique"` call will raise an error if `de-dupe` is not installed or DeDupe is not configured with Redis.

#### Producer Usage

```ruby
class StoryCreatedProducer < Lepus::Producer
  configure(exchange: "story_created")
  use :json
  use :unique, lock_key: "story", lock_id: ->(msg) { msg.payload[:story_id].to_s }, ttl: 3600
end

class StoryUpdatedProducer < Lepus::Producer
  configure(exchange: "story_updated")
  use :json
  use :unique, lock_key: "story", lock_id: ->(msg) { msg.payload[:story_id].to_s }
end
```

Options:
- `lock_key` (required): Shared lock namespace (e.g., `"story"`).
- `lock_id` (required): A `Proc` that extracts a unique identifier from the message. If it returns `nil`, deduplication is skipped.
- `ttl` (optional): Lock TTL in seconds. Defaults to the DeDupe global configuration. The TTL is passed to the consumer via message headers (`x-dedupe-lock-ttl`), so the consumer uses the same TTL when releasing the lock.

When a duplicate is detected (lock already held), the publish is **silently skipped**.

#### Consumer Usage

Register the `:unique` middleware on your consumer. It reads lock information from message headers set by the producer (`x-dedupe-lock-key`, `x-dedupe-lock-id`, and optionally `x-dedupe-lock-ttl`):

```ruby
class StoryConsumer < Lepus::Consumer
  configure(
    queue: "stories",
    exchange: "story_created",
    routing_key: %w[story.created story.updated]
  )
  use :json, symbolize_keys: true
  use :unique

  def perform(message)
    story_id = message.payload[:story_id]
    Story.find(story_id).process!

    ack!
  rescue ActiveRecord::RecordNotFound
    reject!
  end
end
```

By default, the lock is **only released when the consumer returns `:ack`**. On `:reject`, `:requeue`, or `:nack`, the lock remains held so that retries are still deduplicated.

You can customize this behavior with the `release_on` option:

```ruby
# Release on ack or reject (e.g., message is permanently handled either way)
use :unique, release_on: [:ack, :reject]

# Release on error too (e.g., dead-letter scenarios where you don't want the lock held)
use :unique, release_on: [:ack, :error]
```

Valid values for `release_on`: `:ack`, `:reject`, `:requeue`, `:nack`, `:error`. When `:error` is included, the lock is released if the downstream raises an exception, and the exception is re-raised after release.

## Starting the Consumer Process

To start the consumer, can use the `lepus` CLI:

```bash
bundle exec lepus
```

You can pass one or more consumers to the `lepus` CLI:

```bash
bundle exec lepus start MyConsumer1 MyConsumer2 --debug
```

Each consumer will run in a separate process, and a supervisor will monitor them. If a consumer crashes, the supervisor will restart it.

### Puma Plugin

We provide a Puma plugin if you want to run the Lepus's supervisor together with Puma and have Puma monitor and manage it. You just need to add

```ruby
plugin :lepus
```

**Note**: The Puma plugin is only available if you are using Puma 6.x or higher.

## Web UI Dashboard

Lepus includes a built-in web dashboard that provides a real-time view of your message processing infrastructure. The dashboard allows you to monitor processes, queues, connections, and consumer performance.

### Starting the Web Dashboard

You can start the web dashboard using the `lepus web` command:

```bash
bundle exec lepus web
```

The dashboard will be available at `http://localhost:9292` by default. You can customize the host and port:

```bash
bundle exec lepus web --port 3000 --host 127.0.0.1
```

### Web Dashboard Features

The Lepus web dashboard provides:

- **Process Monitoring**: View all running supervisors and workers with their PIDs, memory usage, and heartbeat status
- **Queue Management**: Monitor queue statistics including message counts, consumer connections, and memory usage
- **Connection Tracking**: View active RabbitMQ connections and their states
- **Consumer Performance**: Track processed, rejected, and errored messages per consumer
- **Real-time Updates**: Dashboard automatically refreshes to show current system state

### Integrating with Rails

To integrate the Lepus web dashboard into your Rails application, you can mount it as a Rack application in your routes:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Your existing routes...

  # Mount Lepus web dashboard (simple way)
  mount Lepus::Web => "/lepus"
end
```

You can also use the more explicit syntax:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Your existing routes...

  # Mount Lepus web dashboard (explicit way)
  mount Lepus::Web::App.build => "/lepus"
end
```

This will make the dashboard available at `http://your-app.com/lepus` in your Rails application.

#### Process registry backend

Lepus tracks running supervisors and workers in a **process registry**. Two
backends are available:

- `:file` (default for a core `require "lepus"`) — stores process data in a
  local file under `/tmp`. Fast and dependency-free, but the file is only
  visible to processes that share the same filesystem.
- `:rabbitmq` — stores the same data in a dedicated RabbitMQ queue, so every
  process connected to the same broker sees the same registry.

**Requiring `lepus/web` automatically switches the default to `:rabbitmq`.**
This is because the dashboard is almost always run in a separate process (and
often a separate container) from the workers, and the `:file` backend cannot
bridge that gap — you'd see an empty dashboard even with workers running. The
dashboard still needs the RabbitMQ Management API for queue/connection data,
but the registry is what lets it discover your workers.

If you really want the file backend even with the dashboard loaded, set it
explicitly after your `require`:

```ruby
# config/initializers/lepus.rb
Lepus.configure do |config|
  config.process_registry_backend = :file
end
```

`Lepus::Web` is a plain Rack app, so authentication is applied by wrapping it
in standard Rack middleware or by gating the mount with a real auth helper.
Rails routing `constraints:` is **not** an authentication mechanism — a falsy
constraint returns 404 and never prompts for credentials.

HTTP Basic Auth (wrap the Rack app):

```ruby
# config/routes.rb
require "rack/auth/basic"

lepus_web = Rack::Builder.new do
  use Rack::Auth::Basic, "Lepus Dashboard" do |username, password|
    ActiveSupport::SecurityUtils.secure_compare(username, ENV.fetch("LEPUS_USER")) &
      ActiveSupport::SecurityUtils.secure_compare(password, ENV.fetch("LEPUS_PASSWORD"))
  end
  run Lepus::Web
end

Rails.application.routes.draw do
  mount lepus_web => "/lepus"
end
```

Devise (only admins can see the dashboard):

```ruby
# config/routes.rb
Rails.application.routes.draw do
  authenticate :user, ->(u) { u.admin? } do
    mount Lepus::Web => "/lepus"
  end
end
```

## Prometheus metrics (optional)

Lepus ships an optional integration with
[`prometheus_exporter`](https://github.com/discourse/prometheus_exporter). It is
not a required dependency and is not auto-loaded — add the gem to your `Gemfile`
and require `lepus/prometheus` explicitly from the Lepus process you want to
instrument.

```ruby
# Gemfile
gem "prometheus_exporter"
```

```ruby
# e.g. config/initializers/lepus.rb, or at the top of your consumer boot script
require "lepus/prometheus"

# Optional: poll the RabbitMQ Management API for queue-level gauges
# from a single process (typically the supervisor).
Lepus::Prometheus.watch_queues(interval: 30)
```

Requiring `lepus/prometheus` installs the necessary hooks into
`Lepus::Consumers::Handler` (delivery counters and latency) and
`Lepus::Consumers::Worker` (process RSS gauge), and subscribes to
`publish.lepus` notifications (publish counters). Metrics are sent over TCP to
the `PrometheusExporter::Client.default` client.

On the exporter side, load the bundled type collector so the server knows how
to turn Lepus payloads into Prometheus metrics:

```bash
bundle exec prometheus_exporter -a lepus/prometheus/collector
```

Point Prometheus at the exporter (default port `9394`) and import
[`examples/grafana-dashboard.json`](examples/grafana-dashboard.json) into
Grafana. The dashboard covers every metric exposed by the collector.

### Exposed metrics

| Metric                                    | Type      | Labels                            | Source                                     |
|-------------------------------------------|-----------|-----------------------------------|--------------------------------------------|
| `lepus_messages_processed_total`          | counter   | `consumer`, `queue`, `result`     | `Handler#process_delivery`                 |
| `lepus_delivery_duration_seconds`         | histogram | `consumer`, `queue`               | `Handler#process_delivery`                 |
| `lepus_messages_published_total`          | counter   | `exchange`, `routing_key`         | `publish.lepus` notification               |
| `lepus_publish_duration_seconds`          | histogram | `exchange`, `routing_key`         | `publish.lepus` notification               |
| `lepus_process_rss_memory_bytes`          | gauge     | `kind`, `name`, `pid`             | `Worker#heartbeat`                         |
| `lepus_queue_messages`                    | gauge     | `name`                            | `watch_queues` via management API          |
| `lepus_queue_messages_ready`              | gauge     | `name`                            | `watch_queues` via management API          |
| `lepus_queue_messages_unacknowledged`     | gauge     | `name`                            | `watch_queues` via management API          |
| `lepus_queue_consumers`                   | gauge     | `name`                            | `watch_queues` via management API          |
| `lepus_queue_memory_bytes`                | gauge     | `name`                            | `watch_queues` via management API          |

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/marcosgz/lepus.


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
