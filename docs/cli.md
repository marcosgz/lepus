# CLI

The `lepus` executable is the main operational entry point. It's a Thor-based CLI with two subcommands.

```bash
bundle exec lepus <command> [args] [options]
```

## `lepus start`

Boot the supervisor and run the specified consumers.

```bash
bundle exec lepus start [CONSUMER_CLASSES...] [options]
```

If no classes are specified **and** `config.consumers_directory` is set, every consumer class discovered in that directory is started.

### Options

| Flag | Default | Purpose |
|------|---------|---------|
| `--debug` | `false` | Set logger level to DEBUG. |
| `--logfile PATH` | stdout | Write logs to a file. |
| `--pidfile PATH` | none | Write the supervisor PID to a file. |
| `--require_file PATH`, `-r PATH` | none | Require this file before starting (e.g. `config/environment.rb`). |

### Examples

```bash
# One consumer, no framework auto-load
bundle exec lepus start OrdersConsumer

# Multiple consumers, Rails env loaded first
bundle exec lepus start OrdersConsumer PaymentsConsumer \
  --require_file config/environment.rb

# Auto-load everything under config.consumers_directory
bundle exec lepus start

# Debug mode + pidfile (typical for a systemd unit)
bundle exec lepus start OrdersConsumer \
  --require_file config/environment.rb \
  --pidfile /var/run/lepus.pid \
  --logfile /var/log/lepus.log \
  --debug
```

### What happens at start

1. Load `--require_file` if given.
2. Resolve consumer classes (CLI args or auto-discovered).
3. Group consumers by their `process.name` (defaulting to `:default`).
4. Fork one worker subprocess per group. Parent becomes the supervisor.
5. Each worker opens a Bunny channel, declares queues/exchanges/bindings, and starts consuming with its configured thread pool.
6. Supervisor monitors children via pipes and restarts any that crash.

See [supervisor.md](supervisor.md) for the full lifecycle.

## `lepus web`

Run the web dashboard.

```bash
bundle exec lepus web [options]
```

### Options

| Flag | Default | Purpose |
|------|---------|---------|
| `--port PORT`, `-p PORT` | `9292` | Port to bind. |
| `--host HOST`, `-o HOST` | `0.0.0.0` | Host to bind. |

### Example

```bash
bundle exec lepus web --port 9292 --host 0.0.0.0
```

Visit http://localhost:9292.

The web UI reads from the process registry backend (`config.process_registry_backend`). For multi-host visibility, set the backend to `:rabbitmq`. See [web.md](web.md).

### Mounting in Rails

Instead of running the CLI, you can mount the web app directly:

```ruby
# config/routes.rb
require 'lepus/web'
mount Lepus::Web::App, at: '/lepus'
```

See [rails.md](rails.md) for authorization patterns.

## Exit codes

- `0` — graceful shutdown (SIGTERM / SIGINT).
- Non-zero — unrecoverable error at boot (config invalid, RabbitMQ unreachable, etc.).

Workers that crash after boot are restarted by the supervisor; the supervisor itself only exits on an unrecoverable event or a requested shutdown.

## Environment variables

- `RABBITMQ_URL` — fallback for `config.rabbitmq_url` if not explicitly set.

Everything else is configured via `Lepus.configure`. See [configuration.md](configuration.md).
