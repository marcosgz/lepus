# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
* Added: `delay:` option on `Producer.publish` and `Lepus::Publisher#publish` (milliseconds, or anything responding to `in_milliseconds`) delivers messages later through per-delay TTL queues, without the delayed-message plugin
* Added: `delay!(ms)` (aliased `delay`) consumer helper re-delivers the current message to the consumer's own queue after the delay and acks it, incrementing the `x-lepus-delayed-count` header
* Added: `delay:` through the default exchange delivers to the queue named by `routing_key` later, e.g. `Lepus::Publisher.new("").publish(payload, routing_key: "jobs", delay: 5_000)` (also on `channel_publish`)
* Added: `config.delay_queue_expires` (default 1 hour) sets how long unused delay queues are kept beyond their delay before RabbitMQ deletes them
* Added: `delays:` option on producer and consumer `configure` restricts delays to a fixed set, raising `Lepus::Error` for any other value, to bound the number of delay queues
* Added: info log the first time each process declares a delay queue
* Added: `delay` key in the `publish.lepus` instrumentation payload
* Added: `Lepus::Testing` records `delay` and `expiration` of fake messages, and `lepus_publish_message.with_delay(ms)` matcher
* Fixed: `Consumers::Config#retry_queue_name` and `#error_queue_name` return nil instead of raising when the queue is not configured

## 0.2.2 - 2026-10-30
* Added: `lepus start --except A,B` (and `Supervisor.new(except:)`) runs every consumer but the ones listed

## 0.2.1 - 2026-10-30
* Added: `process_delivery.lepus` instrumentation around every consumed message, with consumer, exchange, routing key, redelivered flag and result
* Added: `consumer_error.lepus` instrumentation when `#perform` raises, before the message is rejected
* Added: `Lepus::LogSubscriber` logs processed deliveries (info) and consumer errors (error)
* Fixed: `Lepus.instrument` without a block no longer raises when ActiveSupport is not loaded

## 0.2.0 - 2026-10-28
* Added: named producer connections via `config.connection(name, url:, **bunny_options)`; `rabbitmq_url` remains the `:default` connection
* Added: `connection:` option on `Producer.configure`, `Producer.publish` and `Lepus::Publisher.new`, with one producer connection pool per name
* Added: `Lepus::InvalidConnectionError` raised for unregistered connection names
* Added: fake messages in `Lepus::Testing` record their `connection`

## 0.0.1 - 2024-08-01
The first release of the gem
* Added: Initial implementation with support to Sidekiq and Faktory backends
* UniqueJob middleware to avoid duplicated jobs
