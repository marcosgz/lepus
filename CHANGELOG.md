# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
