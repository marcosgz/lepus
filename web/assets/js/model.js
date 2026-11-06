// Turns /api/topology into what the map draws: one band per exchange, one
// row per queue bound to it (exchange -> queue -> consumer -> acknowledged),
// with the queue's retry, error and delay queues folded into its row.

const ACTIVE = 0.01;
const QUIET_AFTER_MS = 30_000;
const ERRORS_SHOW_MS = 300_000;
const ERROR_SHARE = 0.01;
export const DEFAULT_BAND = "";

const sum = (items, fn) => items.reduce((total, item) => total + (fn(item) || 0), 0);
const byName = (a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);

export function isMain(queue, queues) {
  if (queue.role === "main") return true;
  if (queue.parent_exchange) return false;
  return !queues.has(queue.parent);
}

// Growing, or nobody is reading it.
export const backingUp = (queue) => queue.ready > 0 && (queue.backlog_rate > 0.05 || queue.consumers === 0);

export class Memory {
  constructor() {
    this.lastActive = new Map();
    this.errored = new Map();
  }

  // Consumer counters only grow while a worker lives. When more than one in
  // a hundred messages handled since the last report raised an error, the
  // consumer stays red for a few minutes.
  erroredRecently(consumer, now) {
    const key = `${consumer.queue}|${consumer.class_name || consumer.connection_name}`;
    const handled = consumer.processed + consumer.rejected + consumer.errored;
    const seen = this.errored.get(key);
    if (!seen) {
      this.errored.set(key, { errored: consumer.errored, handled, changedAt: 0 });
      return false;
    }
    const errors = consumer.errored - seen.errored;
    const total = handled - seen.handled;
    if (errors > 0 && total > 0 && errors / total >= ERROR_SHARE) seen.changedAt = now;
    if (total !== 0) Object.assign(seen, { errored: consumer.errored, handled });
    return now - seen.changedAt < ERRORS_SHOW_MS;
  }

  quiet(key, active, now) {
    if (active) {
      this.lastActive.set(key, now);
      return false;
    }
    const last = this.lastActive.get(key);
    return !last || now - last >= QUIET_AFTER_MS;
  }
}

function consumerLabel(consumers) {
  const named = consumers.filter((c) => c.channels || c.reporting);
  if (!named.length) return null;
  const first = named[0].class_name || named[0].connection_name || "Consumer";
  return named.length > 1 ? `${first} +${named.length - 1}` : first;
}

function buildRow(queue, { keys, also, children, consumers, memory, now }) {
  const kids = children.get(queue.name) || [];
  const retry = kids.find((kid) => kid.role === "retry") || null;
  const error = kids.find((kid) => kid.role === "error") || null;
  const delays = kids.filter((kid) => kid.role === "delay");
  const mine = consumers.filter((consumer) => consumer.queue === queue.name);
  const rates = {
    in: queue.publish_rate,
    out: queue.deliver_rate,
    ack: queue.ack_rate,
    retry: retry ? retry.publish_rate : 0,
    error: error ? error.publish_rate : 0,
    delay: sum(delays, (q) => q.publish_rate)
  };
  const held = queue.messages + sum(kids, (kid) => kid.messages);
  const active = held > 0 || Object.values(rates).some((value) => value >= ACTIVE);
  const erroring = mine.map((consumer) => memory.erroredRecently(consumer, now)).some(Boolean);
  const stopped = erroring || (rates.error >= 0.05 && rates.error >= rates.out * ERROR_SHARE);
  return {
    kind: "queue",
    key: queue.name,
    name: queue.name,
    queue,
    keys,
    also,
    retry,
    error,
    delayed: sum(delays, (q) => q.messages),
    delayQueues: delays,
    consumers: mine,
    consumerLabel: consumerLabel(mine),
    rates,
    backlog: queue.ready,
    rising: backingUp(queue),
    stopped,
    quiet: memory.quiet(queue.name, active, now),
    score: Math.log10(1 + queue.ready) * 2 + Math.log10(1 + rates.in + rates.out) + (stopped ? 6 : 0) + (error && error.messages ? 3 : 0)
  };
}

function foldRows(rows, { expanded, limit, band }) {
  const foldable = rows.filter((row) => row.kind === "queue");
  const fixed = rows.filter((row) => row.kind !== "queue");
  const active = foldable.filter((row) => !row.quiet);
  if (expanded) {
    const shown = [...fixed, ...foldable].sort(byName);
    const canFold = active.length < foldable.length || foldable.length > limit;
    return canFold ? [...shown, { kind: "less", key: `${band}|less`, band }] : shown;
  }
  const keep = active.length <= limit ? active : [...active].sort((a, b) => b.score - a.score).slice(0, limit);
  const kept = new Set(keep);
  const rest = foldable.filter((row) => !kept.has(row));
  const shown = [...fixed, ...keep].sort(byName);
  if (!rest.length) return shown;
  const more = {
    kind: "more",
    key: `${band}|more`,
    band,
    count: rest.length,
    quietCount: rest.filter((row) => row.quiet).length,
    backlog: sum(rest, (row) => row.backlog),
    errors: sum(rest, (row) => (row.error ? row.error.messages : 0)),
    rates: { in: sum(rest, (row) => row.rates.in), out: sum(rest, (row) => row.rates.out) },
    names: rest.map((row) => row.name)
  };
  return [...shown, more];
}

export function buildModel(topology, memory, { now = Date.now(), expanded = new Set(), limit = 6 } = {}) {
  const queues = new Map(topology.queues.map((queue) => [queue.name, queue]));
  const exchanges = new Map(topology.exchanges.map((exchange) => [exchange.name, exchange]));
  const children = new Map();
  for (const queue of topology.queues) {
    if (isMain(queue, queues)) continue;
    if (!children.has(queue.parent)) children.set(queue.parent, []);
    children.get(queue.parent).push(queue);
  }

  // Exchanges whose bindings all lead to delay queues are the delayed
  // fronts of another exchange; their queues count as that one's delayed.
  const delayFronts = new Set();
  const delayedByExchange = new Map();
  const bindingsBySource = new Map();
  for (const binding of topology.bindings) {
    if (!bindingsBySource.has(binding.source)) bindingsBySource.set(binding.source, []);
    bindingsBySource.get(binding.source).push(binding);
  }
  for (const [source, list] of bindingsBySource) {
    const targets = list.map((binding) => queues.get(binding.destination));
    if (targets.every((queue) => queue && queue.role === "delay" && queue.parent_exchange)) {
      delayFronts.add(source);
      for (const queue of targets) {
        const entry = delayedByExchange.get(queue.parent_exchange) || { messages: 0, queues: 0, rate: 0 };
        entry.messages += queue.messages;
        entry.queues += 1;
        entry.rate += queue.publish_rate;
        delayedByExchange.set(queue.parent_exchange, entry);
      }
    }
  }

  const sources = new Map();
  for (const binding of topology.bindings) {
    if (delayFronts.has(binding.source)) continue;
    const target = binding.destination_type === "queue" ? queues.get(binding.destination) : null;
    if (binding.destination_type === "queue" && (!target || !isMain(target, queues))) continue;
    const key = `${binding.destination_type}:${binding.destination}`;
    if (!sources.has(key)) sources.set(key, []);
    sources.get(key).push(binding);
  }

  const bands = new Map();
  const band = (name) => {
    if (!bands.has(name)) {
      const exchange = exchanges.get(name);
      bands.set(name, {
        key: name,
        name: name === DEFAULT_BAND ? "Default exchange" : name,
        type: exchange ? exchange.type || "" : "direct",
        rate: exchange ? exchange.publish_in_rate : 0,
        delayed: delayedByExchange.get(name) || null,
        rows: []
      });
    }
    return bands.get(name);
  };
  const consumers = topology.consumers || [];

  for (const [key, list] of sources) {
    const sorted = [...list].sort((a, b) => (a.source < b.source ? -1 : a.source > b.source ? 1 : 0));
    const primary = sorted[0];
    const also = [...new Set(sorted.slice(1).map((binding) => binding.source))];
    const keys = primary.routing_keys || [];
    if (key.startsWith("exchange:")) {
      const target = exchanges.get(primary.destination);
      band(primary.source).rows.push({
        kind: "exchange", key: key, name: primary.destination, keys, also,
        rates: { in: target ? target.publish_in_rate : 0 }, quiet: !(target && target.publish_in_rate >= ACTIVE)
      });
    } else {
      band(primary.source).rows.push(buildRow(queues.get(primary.destination), { keys, also, children, consumers, memory, now }));
    }
  }

  const routed = new Set([...sources.keys()].filter((key) => key.startsWith("queue:")).map((key) => key.slice(6)));
  for (const queue of topology.queues) {
    if (!isMain(queue, queues) || routed.has(queue.name)) continue;
    band(DEFAULT_BAND).rows.push(buildRow(queue, { keys: [], also: [], children, consumers, memory, now }));
  }

  const ordered = [...bands.values()].sort((a, b) => (a.key === DEFAULT_BAND) - (b.key === DEFAULT_BAND) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  for (const entry of ordered) {
    entry.allRows = entry.rows;
    entry.quiet = entry.rows.every((row) => row.quiet) && !(entry.rate >= ACTIVE);
    entry.expanded = expanded.has(entry.key);
    entry.rows = foldRows(entry.rows, { expanded: entry.expanded, limit, band: entry.key });
  }

  const unbound = topology.exchanges
    .filter((exchange) => !bands.has(exchange.name) && !delayFronts.has(exchange.name))
    .map((exchange) => exchange.name)
    .sort();

  const mainQueues = topology.queues.filter((queue) => isMain(queue, queues));
  const roles = (role) => topology.queues.filter((queue) => queue.role === role && !isMain(queue, queues));
  return {
    bands: ordered,
    unbound,
    totals: {
      publish: sum(topology.exchanges, (e) => (delayFronts.has(e.name) ? 0 : e.publish_in_rate)) + sum(bands.get(DEFAULT_BAND)?.allRows || [], (row) => row.rates.in),
      deliver: sum(mainQueues, (q) => q.deliver_rate),
      ack: sum(mainQueues, (q) => q.ack_rate),
      retry: sum(roles("retry"), (q) => q.publish_rate),
      errors: sum(roles("error"), (q) => q.messages),
      backingUp: mainQueues.filter(backingUp).length,
      ready: sum(mainQueues, (q) => q.ready),
      queues: mainQueues.length
    }
  };
}
