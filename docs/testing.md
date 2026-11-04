# Testing

Lepus ships a test-mode module that captures publishes and runs consumer `perform` methods synchronously — no RabbitMQ connection required.

## Enabling

```ruby
# spec/spec_helper.rb (RSpec)
require 'lepus/testing'

RSpec.configure do |config|
  config.before(:each) do
    Lepus::Testing.enable!
    Lepus::Testing.clear_all_messages!
  end
  config.after(:each) { Lepus::Testing.disable! }
end
```

Once enabled:

- Publishes don't hit RabbitMQ. They're captured in in-memory fake exchanges keyed by exchange name.
- Consumer exceptions are re-raised instead of turning into `:reject`, so failures show up in your specs. Use `Lepus::Testing.consumer_capture_errors!` to get the production behavior back.
- Consumer handling is synchronous when invoked through `Lepus::Testing.consumer_perform`.

## Testing a consumer

```ruby
describe OrdersConsumer do
  it 'creates an order' do
    result = Lepus::Testing.consumer_perform(OrdersConsumer, { order_id: 42, total: 99.99 })

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
      payload: { order_id: 7 },
      routing_key: 'order.created',
      correlation_id: 'abc-123',
      headers: { 'tenant' => 'acme' }
    )
    expect(result).to eq(:ack)
  end
end
```

`consumer_perform(ConsumerClass, message_or_payload)` accepts:

- a Hash, used as a JSON payload;
- a String, used as a `text/plain` payload;
- a Hash with a `:payload` key, where every other key maps to a `MessageBuilder#with_<key>` method (`routing_key`, `exchange`, `headers`, `correlation_id`, `content_type`, `redelivered`, …);
- a `Lepus::Message`, e.g. built with `Lepus::Testing.message_builder`.

It runs the full middleware chain (including global middlewares) and returns the disposition symbol.

## Testing a producer

```ruby
describe OrdersProducer do
  it 'publishes the order' do
    order = Order.create!(id: 42, total: 99.99)
    OrdersProducer.order_created(order)

    messages = OrdersProducer.messages # same as Lepus::Testing.producer_messages(OrdersProducer)
    expect(messages.size).to eq(1)
    expect(messages[0][:routing_key]).to eq('order.created')
  end
end
```

Each captured message is a hash with `:exchange`, `:connection`, `:payload`, `:routing_key`, `:headers`, `:persistent`, `:mandatory`, `:immediate`, `:content_type`, `:delay`, `:expiration` and `:timestamp` (when it was captured). `:payload` is what reached the publisher, so with the `:json` middleware it's the serialized JSON string.

Query a fake exchange directly:

```ruby
Lepus::Testing.exchange('orders').messages
Lepus::Testing.exchange('orders').find_messages(routing_key: 'order.created', headers: { 'tenant' => 'acme' })
```

Each fake message also records the named connection it was published through:

```ruby
Lepus::Testing.exchange('orders').find_messages(connection: :replica)
```

The connection may be given as a symbol or a string. Publishing through a connection that was never registered with `config.connection` raises `Lepus::InvalidConnectionError`, as it does outside of fake mode.

### Delayed messages

`delay:` is recorded on the target exchange, normalized to milliseconds, so `OrdersProducer.messages` and `to_exchange` keep working:

```ruby
OrdersProducer.publish({ order_id: 42 }, routing_key: 'order.reminder', delay: 30_000)

expect(OrdersProducer.messages.last[:delay]).to eq(30_000)
```

A consumer's `delay!(ms)` is recorded on the default exchange (`''`) with the consumer queue as routing key, and the `x-lepus-delayed-count` header incremented:

```ruby
Lepus::Testing.consumer_perform(ReindexConsumer, { story_id: 1 })

message = Lepus::Testing.exchange('').messages.last
expect(message).to include(routing_key: 'reindex', delay: 5_000)
```

## RSpec matchers

The matchers are included in RSpec when `lepus/testing` is required.

```ruby
expect { OrdersProducer.order_created(order) }
  .to lepus_publish_message
  .to_exchange('orders')
  .with_routing_key('order.created')
  .with(satisfy { |json| MultiJson.load(json)['order_id'] == order.id }) # :json middleware serialized it

expect { OrdersProducer.publish(payload, delay: 30_000) }
  .to lepus_publish_message(1).with_delay(30_000)

# Matches the messages already captured for a producer
expect(OrdersProducer).to lepus_publish_message.with_routing_key('order.created')

# Consumer dispositions
expect(OrdersConsumer).to lepus_acknowledge_message({ order_id: 42 }) # alias: lepus_ack_message
expect(OrdersConsumer).to lepus_reject_message({ bad: 'data' })
expect(OrdersConsumer).to lepus_requeue_message(payload)
expect(OrdersConsumer).to lepus_nack_message(payload)
```

`with_delay` accepts milliseconds or anything responding to `in_milliseconds`. `with` takes a value or any RSpec matcher and is checked against the captured `:payload`.

## Testing middleware in isolation

Middlewares are plain Ruby objects with a `call(message, app)` method. Unit-test them directly:

```ruby
describe LogLevelMiddleware do
  it 'logs before calling down the chain' do
    middleware = LogLevelMiddleware.new(level: :debug)
    message    = Lepus::Testing.message_builder.with_payload({ x: 1 }).with_routing_key('order.created').build
    captured   = nil

    allow(Lepus.logger).to receive(:debug) { |msg| captured = msg }
    middleware.call(message, ->(m) { :ack })

    expect(captured).to include('Processing:')
  end
end
```

`Lepus::Testing.message_builder` returns a `Lepus::Testing::MessageBuilder`; chain `with_*` methods (`with_payload`, `with_routing_key`, `with_headers`, `with_correlation_id`, `with_channel`, …) and call `build` to get a `Lepus::Message`.

## Resetting between tests

`Lepus::Testing.clear_all_messages!` clears captured publishes. `Lepus::Testing.disable!` turns fake publishing and error re-raising off.

## When you do need a real RabbitMQ

Integration tests that exercise the full round-trip (publish → RabbitMQ → consume) benefit from a real broker. Use `docker run rabbitmq:3-management` or your test infra's existing one, and skip `Lepus::Testing.enable!` for those specs.
