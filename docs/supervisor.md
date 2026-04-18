# Supervisor

The supervisor is the parent process when you run `lepus start`. It forks workers, monitors them, and handles signals.

## Process model

```
Supervisor (pid = $$)
├── Worker[:default]        pid = 1001
│   ├── Thread OrdersConsumer
│   └── Thread OrdersConsumer
└── Worker[:high_priority]  pid = 1002
    └── Thread PaymentsConsumer
```

- **One worker per named pool.** Consumers with `process.name = :default` share a worker; consumers with `process.name = :high_priority` share a different one. Unnamed consumers default to `:default`.
- **Multiple threads per worker.** Each worker runs a thread pool sized by `config.worker(:name).pool_size`.
- **One channel per consumer.** Each consumer gets its own Bunny channel to avoid cross-consumer interference.

Fork boundaries matter because child processes inherit open file descriptors, sockets, and DB connections. See the `before_fork` / `after_fork` hooks below.

## Fork hooks

```ruby
Lepus.configure do |config|
  config.worker(:default) do |w|
    # Runs in the SUPERVISOR just before fork()
    w.before_fork do
      ActiveRecord::Base.connection_handler.clear_all_connections!
      Redis.current.disconnect!
    end

    # Runs in the CHILD after fork()
    w.after_fork do
      ActiveRecord::Base.establish_connection
      Redis.current = Redis.new
      SecureRandom.hex(4)  # implicit reseed
    end
  end
end
```

The classic pattern: close long-lived connections in `before_fork`, reopen them in `after_fork`. Otherwise all children end up sharing the same socket.

## Signals

| Signal | Supervisor response |
|--------|---------------------|
| `SIGTERM` | Graceful shutdown — see below. |
| `SIGINT` | Graceful shutdown (same as SIGTERM). |
| `SIGQUIT` | Graceful shutdown, slightly more aggressive. |
| `SIGTTIN` | Dump thread backtraces of every worker (debugging). |
| `SIGUSR1` | Reopen log files (useful for logrotate). |

Child workers respond to the same signals, but normally the supervisor handles signals and forwards the shutdown to children.

## Graceful shutdown

1. Supervisor writes a shutdown message to each worker's pipe.
2. Each worker stops accepting new messages (`basic.cancel` on its channels).
3. In-flight `perform` calls are allowed to finish.
4. Workers close connections and exit with code 0.
5. If a worker takes longer than `shutdown_timeout` (default 5 seconds per message, tuned via consumer `channel.shutdown_timeout`), it's killed with `SIGKILL`.
6. Supervisor exits.

Rule of thumb for deploy scripts: send SIGTERM, wait at least `pool_size × average_message_duration + 5 seconds`, then the supervisor should have exited cleanly.

## Worker crash recovery

If a worker exits unexpectedly (raised exception outside a `perform` call, OOM, killed by OOM killer):

1. Supervisor detects the pipe close.
2. Logs the exit status.
3. Forks a new worker using the same `before_fork` / `after_fork` hooks.
4. Worker re-declares its queues and resumes consuming.

Within a `perform`, exceptions are caught and routed to `on_thread_error`; the worker is not restarted for those. Only crashes at the worker level (outside message handling) trigger a restart.

## Heartbeats and the process registry

Each worker (and the supervisor itself) emits heartbeats to the process registry:

```ruby
config.process_heartbeat_interval = 60     # seconds
config.process_alive_threshold    = 5 * 60 # seconds
```

The web dashboard reads from this registry to display process status. Processes whose last heartbeat is older than `process_alive_threshold` are considered dead and hidden from the UI (but kept briefly so transient restarts don't flash).

## Pidfile

```bash
bundle exec lepus start --pidfile /var/run/lepus.pid
```

Written by the supervisor at boot, removed at graceful shutdown. If the file exists when lepus starts, the supervisor checks if the PID is alive; if so, it exits (don't run two supervisors). If not, it overwrites.

## Running under a process manager

- **systemd:** `ExecStart=/path/to/bundle exec lepus start --pidfile /run/lepus.pid`, `KillSignal=SIGTERM`, `TimeoutStopSec=60`.
- **Foreman / Procfile:** `worker: bundle exec lepus start`. No pidfile needed.
- **Kubernetes:** set a `preStop` lifecycle hook to send SIGTERM, and tune `terminationGracePeriodSeconds` to be larger than your longest `perform`.

## Debugging a stuck worker

Send SIGTTIN:

```bash
kill -TTIN <worker-pid>
```

The worker prints thread backtraces to the log. Useful when you suspect a deadlock or a `perform` stuck on a slow network call.
