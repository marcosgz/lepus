# Rails Integration

When Rails is loaded, Lepus's Railtie wires up sensible defaults. No initializer is strictly required.

## What the Railtie does

- Sets `config.logger = Rails.logger` (unless you've already set one).
- Sets `config.app_executor = Rails.application.executor` — every consumer `perform` runs inside the Rails executor, which means:
  - Autoloading works (Zeitwerk is active).
  - Query cache is cleared after each message.
  - Connection cleanup runs after each message.
  - Reloading works in development.
- Subscribes the log subscriber for friendly production log lines.
- Integrates with `Rails.error` — unhandled exceptions are reported there.

## Overriding

```ruby
# config/initializers/lepus.rb
Lepus.configure do |config|
  config.rabbitmq_url    = ENV.fetch('RABBITMQ_URL')
  config.connection_name = 'my-service'

  # Override the defaults:
  config.logger       = MyLogger.new
  config.app_executor = nil   # disable executor wrapping entirely

  config.consumers_directory = 'app/consumers'

  config.worker(:default) do |w|
    w.pool_size = 5
    w.before_fork { ActiveRecord::Base.connection_handler.clear_all_connections! }
    w.after_fork  { ActiveRecord::Base.establish_connection }
  end
end
```

## Defining consumers and producers

Put them in `app/consumers/` and `app/producers/`. With `config.consumers_directory = 'app/consumers'`, `lepus start` with no arguments auto-loads all of them.

```ruby
# app/consumers/orders_consumer.rb
class OrdersConsumer < Lepus::Consumer
  configure(
    queue:    'orders',
    exchange: { name: 'orders', type: :topic, durable: true },
    routing_key: 'order.*'
  )
  use :json, symbolize_keys: true

  def perform(message)
    Order.create!(message.payload)
    :ack
  end
end
```

```ruby
# app/producers/orders_producer.rb
class OrdersProducer < Lepus::Producer
  configure(exchange: { name: 'orders', type: :topic, durable: true })
  use :json
  use :correlation_id
end
```

## Running alongside a Rails web app

```bash
# Terminal 1 — web
bin/rails server

# Terminal 2 — consumers
bundle exec lepus start --require_file config/environment.rb
```

Or use Foreman:

```
# Procfile
web:    bin/rails server
worker: bundle exec lepus start --require_file config/environment.rb
```

## The Puma plugin

For apps that want consumers running inside the same Puma process (development convenience, or small-scale production where you don't want another service):

```ruby
# config/puma.rb
plugin :lepus
```

The plugin forks consumer workers as Puma's cluster workers would, tying their lifecycle to Puma's.

**Caution:** running consumers inside Puma means process restarts on deploy take longer (waiting for in-flight messages) and you can't scale consumers independently of web requests. For non-trivial workloads, run them as a separate service.

## Mounting the web dashboard

```ruby
# config/routes.rb
require 'lepus/web'

authenticate :user, ->(u) { u.admin? } do
  mount Lepus::Web::App, at: '/lepus'
end
```

See [web.md](web.md).

## Testing

```ruby
# spec/rails_helper.rb (or spec/spec_helper.rb)
require 'lepus/testing'

RSpec.configure do |config|
  config.before(:each) { Lepus::Testing.enable!; Lepus::Testing.reset! }
end
```

See [testing.md](testing.md).

## Active Record gotchas

Since `app_executor` is set to `Rails.application.executor`, Active Record connection management is handled per message — no manual `clear_active_connections!` needed.

For worker subprocesses, the `before_fork` / `after_fork` hooks close and reopen connections cleanly:

```ruby
Lepus.configure do |config|
  config.worker(:default) do |w|
    w.before_fork { ActiveRecord::Base.connection_handler.clear_all_connections! }
    w.after_fork  { ActiveRecord::Base.establish_connection }
  end
end
```

Without these hooks, all children inherit the same database socket and things go badly fast.

## Exception reporting

Lepus's Rails integration reports unhandled exceptions via `Rails.error`:

```ruby
# config/application.rb or an initializer
Rails.error.subscribe do |exception, handled:, severity:, context:, source:|
  Honeybadger.notify(exception, context: context) if source == 'lepus'
end
```

Or use the `:honeybadger` middleware directly on your consumers — see [middleware.md](middleware.md).

## Zeitwerk

Consumer and producer classes are autoloaded by Zeitwerk like any other Rails class. `app/consumers/orders_consumer.rb` → `OrdersConsumer`, namespaced with the usual folder-to-module rules.

## Generators

None at the moment. Create consumer and producer files by hand (or your editor's snippet of choice).
