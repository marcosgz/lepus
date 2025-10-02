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

You can also create your own middlewares, just create subclasses of `Lepus::Middleware` and implement the `call` method:

```ruby
class MyMiddleware < Lepus::Middleware
  def initialize(app, my_opt:, **options)
    @my_opt = my_opt
    super(app, **options)
  end

  def call(message)
    # Do something before calling the next middleware
    app.call(message)
  end
end
```

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


## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/marcosgz/lepus.


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
