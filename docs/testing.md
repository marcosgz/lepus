# Testing

Lepus ships a test-mode module that captures publishes and runs consumer `perform` methods synchronously — no RabbitMQ connection required.

## Enabling

```ruby
# spec/spec_helper.rb (RSpec)
require 'lepus/testing'

RSpec.configure do |config|
  config.before(:each) { Lepus::Testing.enable! }
  config.after(:each)  { Lepus::Testing.reset! }
end
```

Once enabled:

- Publishes don't hit RabbitMQ. They're captured in an in-memory buffer keyed by producer class.
- Consumer handling is synchronous when invoked through `Lepus::Testing.consumer_perform`.

## Testing a consumer

```ruby
describe OrdersConsumer do
  it 'creates an order' do
    result = Lepus::Testing.consumer_perform(
      OrdersConsumer,
      { order_id: 42, total: 99.99 }
    )

    expect(result).to eq(:ack)
    expect(Order.find(42).total).to eq(99.99)
  end

  it 'rejects invalid payloads' do
    result = Lepus::Testing.consumer_perform(OrdersConsumer, { bad: 'data' })
    expect(result).to eq(:reject)
  end

  it 'sets delivery info and metadata' do
    result = Lepus::Testing.consumer_perform(
      OrdersConsumer,
      { order_id: 7 },
      delivery_info: { routing_key: 'order.created' },
      metadata:      { correlation_id: 'abc-123' }
    )
    expect(result).to eq(:ack)
  end
end
```

`consumer_perform` signature:

```ruby
Lepus::Testing.consumer_perform(
  ConsumerClass,
  payload,
  delivery_info: {},
  metadata: {}
)
```

It builds a `Lepus::Message`, runs the full middleware chain (including global middlewares), and returns the disposition symbol.

## Testing a producer

```ruby
describe OrdersProducer do
  it 'publishes the order' do
    order = Order.create!(id: 42, total: 99.99)
    OrdersProducer.order_created(order)

    messages = Lepus::Testing.producer_messages(OrdersProducer)
    expect(messages.size).to eq(1)
    expect(messages[0][:payload]).to include(order_id: 42)
    expect(messages[0][:routing_key]).to eq('order.created')
  end

  it 'runs through middleware' do
    OrdersProducer.publish({ foo: 'bar' }, routing_key: 'x')

    msg = Lepus::Testing.producer_messages(OrdersProducer).last
    expect(msg[:metadata][:correlation_id]).to be_present  # set by :correlation_id middleware
    expect(msg[:metadata][:content_type]).to eq('application/json')
  end
end
```

`producer_messages(ProducerClass)` returns an array of hashes with `:payload`, `:routing_key`, `:delivery_info`, `:metadata`.

## RSpec matchers

```ruby
# spec/spec_helper.rb
require 'lepus/testing/rspec_matchers'
```

Then:

```ruby
expect { OrdersProducer.order_created(order) }
  .to have_published_message(OrdersProducer)
  .with_payload(include(order_id: order.id))
  .to_routing_key('order.created')
```

## Testing middleware in isolation

Middlewares are plain Ruby objects with a `call(message, app)` method. Unit-test them directly:

```ruby
describe LogLevelMiddleware do
  it 'logs before calling down the chain' do
    middleware = LogLevelMiddleware.new(level: :debug)
    message   = Lepus::Testing::MessageBuilder.build(payload: { x: 1 })
    captured  = nil

    allow(Lepus.logger).to receive(:debug) { |msg| captured = msg }
    middleware.call(message, ->(m) { :ack })

    expect(captured).to include('Processing:')
  end
end
```

`Lepus::Testing::MessageBuilder.build(**kwargs)` builds a realistic `Lepus::Message` for unit tests.

## Resetting between tests

`Lepus::Testing.reset!` clears captured publishes. In shared setup:

```ruby
RSpec.configure do |config|
  config.before(:each) { Lepus::Testing.enable!; Lepus::Testing.reset! }
end
```

## When you do need a real RabbitMQ

Integration tests that exercise the full round-trip (publish → RabbitMQ → consume) benefit from a real broker. Use `docker run rabbitmq:3-management` or your test infra's existing one, and skip `Lepus::Testing.enable!` for those specs.
