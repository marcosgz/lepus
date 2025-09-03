# Lepus


Lepus is a simple and lightweight Ruby library to help you to consume and produce messages to [RabbitMQ](https://www.rabbitmq.com/) using the [Bunny](https://github.com/ruby-amqp/bunny) gem. It's similar to the Sidekiq, Faktory, ActiveJob, SolidQueue, and other libraries, but using RabbitMQ as the message broker.

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

You can configure the Lepus using the `Lepus.configure` method. The configuration options are:

- `rabbitmq_url`: The RabbitMQ host. Default: to `RABBITMQ_URL` environment variable or `amqp://guest:guest@localhost:5672`.
- `connection_name`: The connection name. Default: `Lepus`.
- `recovery_attempts`: The number of attempts to recover the connection. Nil means infinite. Default: `10`.
- `recover_from_connection_close`: If the connection should be recovered when it's closed. Default: `true`.
- `app_executor`: The [Rails executor](https://guides.rubyonrails.org/threading_and_code_execution.html#executor) used to wrap asynchronous operations. Only available if you are using Rails. Default: `nil`.
- `on_thread_error`: The block to be executed when an error occurs on the thread. Default: `nil`.
- `process_heartbeat_interval`: The interval in seconds between heartbeats. Default is `60 seconds`.
- `process_heartbeat_timeout`: The timeout in seconds to wait for a heartbeat. Default is `10 seconds`.
- `worker`: A block to configure the worker process that will run the consumers. You can set the `pool_size`, `pool_timeout`, and before/after fork callbacks inline options or using a block. Main worker is `:default`, but you can define more workers with different names for different consumers.


```ruby
Lepus.configure do |config|
  config.connection_name = 'MyApp'
  config.rabbitmq_url = ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')
end
```

### Configuration > Consumer Worker

You can configure the consumer process using the `worker` method. The options are:
- `pool_size`: The number of threads in the pool. Default: `1`.
- `pool_timeout`: The timeout in seconds to wait for a thread to be available. Default: `5.0`.
- `before_fork`: A block to be executed before forking the process. Default: `nil`.
- `after_fork`: A block to be executed after forking the process. Default: `nil`.

The default worker is named `:default`, but you can define more workers with different names for different consumers.

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

You can use the `use` method to add middlewares to the consumer:

```ruby
class MyConsumer < Lepus::Consumer
  use(
    :max_retry,
    retries: 6,
    error_queue: "queue_name.error" # The queue to route the message after the number of retries
  )

  use(
    :json,
    symbolize_keys: true,
    on_error: proc { :nack } # The default is :reject on parsing error
  )

  def perform(message)
    puts message.payload[:name]
    ack!
  end
end
```

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
