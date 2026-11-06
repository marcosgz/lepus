import { h, s, clear, focusKey, graft, refill, reducedMotion } from "../dom.js";
import { compact, count, duration, perSecond, plural } from "../format.js";
import { DEFAULT_BAND, backingUp, isMain } from "../model.js";

const SHOWN = 30;
const PER_GROUP = 6;
const IDLE_FOLD = 2;
const PICKED_MS = 2400;
const ACTIVE = 0.01;
const OPEN_KEY = "lepus:queues:open";
const FOLD_KEY = "lepus:queues:folds";
const ROLES = { retry: "Retry", delay: "Delay", error: "Error" };
const ROLE_ORDER = Object.keys(ROLES);

const COLUMNS = [
  { key: "name", label: "Queue", value: (q) => q.name, text: true },
  { key: "ready", label: "Ready", value: (q) => q.ready },
  { key: "unacked", label: "Unacked", value: (q) => q.unacked },
  { key: "consumers", label: "Consumers", value: (q) => q.consumers },
  { key: "published", label: "Published/s", value: (q) => q.publish_rate },
  { key: "delivered", label: "Delivered/s", value: (q) => q.deliver_rate },
  { key: "acked", label: "Acked/s", value: (q) => q.ack_rate },
  { key: "retry", label: "Retry", value: (q) => (q.hasRetry ? q.retryCount : -1), hint: "Messages waiting in the queue's retry queues. – means the queue has no retry queue." },
  { key: "error", label: "Error", value: (q) => (q.hasError ? q.errorCount : -1), hint: "Messages parked in the queue's error queues. – means the queue has no error queue." }
];

function recall(key) {
  try { return new Set(JSON.parse(sessionStorage.getItem(key)) || []); } catch { return new Set(); }
}

function remember(key, set) {
  try { sessionStorage.setItem(key, JSON.stringify([...set])); } catch {}
}

function arrow() {
  return s("svg", { viewBox: "0 0 10 10", width: 10, height: 10, "aria-hidden": "true" }, s("path", { d: "M1.5 3.5h7L5 8z" }));
}

function chevron() {
  return s("svg", { class: "q-chevron", viewBox: "0 0 12 12", width: 12, height: 12, "aria-hidden": "true" }, s("path", { d: "M4.5 2.5 8 6l-3.5 3.5" }));
}

function num(n, cls) {
  const shown = compact(n);
  const exact = count(n);
  const classes = [cls, n ? "" : "q-zero"].join(" ").trim() || null;
  if (shown === exact) return h("span", { class: classes }, shown);
  return h("span", { class: classes, title: exact }, h("span", { "aria-hidden": "true" }, shown), h("span", { class: "visually-hidden" }, exact));
}

const speed = (value) => h("span", { class: value ? null : "q-zero" }, perSecond(value));
const rateCell = (label, value) => h("td", { class: value ? null : "is-still", "data-label": label }, speed(value));
const dash = () => h("span", { class: "q-zero" }, "–");
const capitalize = (text) => text.charAt(0).toUpperCase() + text.slice(1);
const listed = (words) => (words.length > 1 ? `${words.slice(0, -1).join(", ")} and ${words[words.length - 1]}` : words[0]);

function onward(queue) {
  const exchange = queue.dead_letter_exchange;
  const key = queue.dead_letter_routing_key;
  if (exchange === null || exchange === undefined) return null;
  if (exchange === "") {
    if (!key) return null;
    return key === queue.parent ? `back to ${key}` : `then to ${key}`;
  }
  return `then to the ${exchange} exchange${key ? ` by ${key}` : ""}`;
}

function delivers(queue) {
  const after = `releases after ${duration(queue.delay_ms)}`;
  return queue.target_type === "exchange" ? `${after} to the ${queue.target} exchange, keeping the routing key` : `${after} to ${queue.target}`;
}

// What a retry, delay or error queue does with its messages, read from its
// arguments: "retries after 5 s, back to orders.billing" or "releases after
// 5 s to orders.billing, expires when unused for 1 h".
function childDuty(queue) {
  const ttl = queue.ttl ? duration(queue.ttl) : null;
  const next = onward(queue);
  const parts = [];
  if (queue.role === "delay" && queue.delay_ms) parts.push(delivers(queue));
  else if (queue.role === "retry") parts.push(ttl ? `retries after ${ttl}` : "holds messages to retry");
  else if (queue.role === "delay") parts.push("holds delayed messages");
  else parts.push(ttl ? `keeps failed messages for ${ttl}` : "keeps failed messages until they are moved");
  if (next && queue.role !== "delay" && (ttl || queue.role !== "error")) parts.push(next);
  if (queue.expires) parts.push(`expires when unused for ${duration(queue.expires)}`);
  return parts.join(", ");
}

const delaysOf = (kids) => kids.filter((kid) => kid.role === "delay").map((kid) => kid.delay_ms).filter(Boolean);

const busy = (q) => q.ready || q.unacked || q.publish_rate >= ACTIVE || q.deliver_rate >= ACTIVE || q.ack_rate >= ACTIVE;

function entry(queue, also, kids) {
  const total = (role) => kids.filter((kid) => kid.role === role).reduce((sum, kid) => sum + kid.messages, 0);
  return {
    ...queue,
    also,
    kids,
    retryCount: total("retry"),
    errorCount: total("error"),
    hasRetry: kids.some((kid) => kid.role === "retry"),
    hasError: kids.some((kid) => kid.role === "error"),
    delayed: queue.delayed ?? kids.filter((kid) => kid.role === "delay").reduce((sum, kid) => sum + kid.messages, 0),
    delays: delaysOf(kids),
    idle: !busy(queue) && !kids.some((kid) => kid.messages || busy(kid))
  };
}

// The map's bands as table groups: each exchange with the queues drawn on
// its band, then the default exchange's queues, which have no binding.
// Delay queues whose queue or exchange is gone are listed under the
// default exchange.
function groupsFrom(topology, bands) {
  const queues = new Map(topology.queues.map((queue) => [queue.name, queue]));
  const children = new Map();
  for (const queue of topology.queues) {
    if (isMain(queue, queues) || !queue.parent) continue;
    if (!children.has(queue.parent)) children.set(queue.parent, []);
    children.get(queue.parent).push(queue);
  }
  const kidsOf = (name) => [...(children.get(name) || [])]
    .sort((a, b) => ROLE_ORDER.indexOf(a.role) - ROLE_ORDER.indexOf(b.role) || (a.delay_ms || 0) - (b.delay_ms || 0) || a.name.localeCompare(b.name));
  const groups = bands.map((band) => {
    const members = band.allRows.filter((row) => row.kind === "queue").map((row) => entry(row.queue, row.also, kidsOf(row.name)));
    const unbound = band.key === DEFAULT_BAND;
    return {
      key: band.key,
      name: band.name,
      unbound,
      type: band.type,
      rate: unbound ? members.reduce((sum, q) => sum + q.publish_rate, 0) : band.rate,
      delayed: (band.delayed ? band.delayed.messages : 0) + members.reduce((sum, q) => sum + q.delayed, 0),
      delays: band.delayed ? band.delayed.queues : [],
      queues: members
    };
  });
  const placed = new Set(bands.map((band) => band.key));
  const orphans = topology.queues.filter((queue) => queue.role === "delay" &&
    !(queue.parent_exchange ? placed.has(queue.parent_exchange) : queues.has(queue.parent)));
  if (orphans.length) {
    let fallback = groups.find((group) => group.unbound);
    if (!fallback) {
      fallback = { key: DEFAULT_BAND, name: "Default exchange", unbound: true, type: "direct", rate: 0, delayed: 0, delays: [], queues: [] };
      groups.push(fallback);
    }
    fallback.delays = [...fallback.delays, ...orphans].sort((a, b) => (a.delay_ms || 0) - (b.delay_ms || 0) || a.name.localeCompare(b.name));
    fallback.delayed += orphans.reduce((sum, queue) => sum + queue.messages, 0);
  }
  return groups.filter((group) => group.queues.length || group.delays.length);
}

// Every main queue under the exchange that routes to it, in the map's order,
// with its retry, delay and error queues one disclosure away.
export class QueueTable {
  constructor(host, { onShow }) {
    this.onShow = onShow;
    this.sort = { key: "name", dir: "asc" };
    this.filter = "";
    this.picked = null;
    this.revealed = null;
    this.groups = [];
    this.open = recall(OPEN_KEY);
    this.folds = recall(FOLD_KEY);
    this.bodies = new Map();
    this.note = h("p", { class: "section-note" });
    this.input = h("input", { type: "search", class: "filter", placeholder: "Filter queues", "aria-label": "Filter queues by name" });
    this.input.addEventListener("input", () => {
      this.filter = this.input.value.trim().toLowerCase();
      this.draw();
    });
    this.head = h("tr");
    this.thead = h("thead", {}, this.head);
    this.table = h("table", { class: "rows rows-sortable q-table" }, h("caption", { class: "visually-hidden" }, "Queues by exchange"), this.thead);
    this.count = h("p");
    host.append(
      h("div", { class: "section-head" }, this.note, this.input),
      this.table,
      h("div", { class: "list-foot" }, this.count));
    this.drawHead();
  }

  drawHead() {
    refill(this.head, COLUMNS.map((column) => {
      const sorted = this.sort.key === column.key;
      return h("th", { scope: "col", "aria-sort": sorted ? (this.sort.dir === "asc" ? "ascending" : "descending") : null },
        h("button", { type: "button", class: "sort", title: column.hint || null, onclick: () => this.sortBy(column) }, column.label, arrow()));
    }));
  }

  sortBy(column) {
    if (this.sort.key === column.key) this.sort.dir = this.sort.dir === "asc" ? "desc" : "asc";
    else this.sort = { key: column.key, dir: column.text ? "asc" : "desc" };
    this.drawHead();
    this.draw();
  }

  set(topology, bands) {
    this.groups = groupsFrom(topology, bands);
    const mains = this.groups.reduce((sum, group) => sum + group.queues.length, 0);
    const exchanges = this.groups.filter((group) => !group.unbound).length;
    this.note.textContent = mains
      ? `${plural(mains, "queue")} under ${plural(exchanges, "exchange")}, in the map's order; sorting orders the queues within each exchange. ` +
        "An exchange's Published/s is what reaches the exchange. Retry and Error count messages in a queue's retry and error queues, – means it has none. " +
        "Delay queues hold messages published with a delay or handed back with delay! until they are released; under an exchange they release to the exchange. " +
        "Rates are RabbitMQ's own, per second."
      : "";
    this.draw();
  }

  matches(queue) {
    const text = this.filter;
    return !text || queue.name.toLowerCase().includes(text) || (queue.application || "").toLowerCase().includes(text) ||
      queue.kids.some((kid) => kid.name.toLowerCase().includes(text));
  }

  shownDelays(group) {
    const text = this.filter;
    if (!text) return group.delays;
    return group.delays.filter((queue) => queue.name.toLowerCase().includes(text) || group.name.toLowerCase().includes(text));
  }

  toggle(set, storageKey, key) {
    if (set === this.folds) this.revealed = null;
    if (set.has(key)) set.delete(key);
    else set.add(key);
    remember(storageKey, set);
    this.draw();
  }

  rowFor(name) {
    return [...this.table.querySelectorAll("tr[data-queue]")].find((row) => row.dataset.queue === name) || null;
  }

  // Brings a queue picked on the map into view: unfiltered, shown even when
  // its group folds it away, expanded, highlighted for a moment and focused.
  pick(name) {
    const group = this.groups.find((candidate) => candidate.queues.some((queue) => queue.name === name));
    if (!group) return;
    const queue = group.queues.find((candidate) => candidate.name === name);
    if (!this.matches(queue)) {
      this.filter = "";
      this.input.value = "";
    }
    if (queue.kids.length && !this.open.has(name)) {
      this.open.add(name);
      remember(OPEN_KEY, this.open);
    }
    this.picked = name;
    this.revealed = name;
    this.draw();
    const row = this.rowFor(name);
    if (!row) return;
    row.focus({ preventScroll: true });
    row.scrollIntoView({ block: "center", behavior: reducedMotion.matches ? "auto" : "smooth" });
    clearTimeout(this.pickedTimer);
    this.pickedTimer = setTimeout(() => this.unpick(), PICKED_MS);
  }

  unpick() {
    const row = this.rowFor(this.picked);
    this.picked = null;
    if (!row) return;
    row.classList.remove("is-picked");
    if (reducedMotion.matches) return;
    row.classList.add("is-fading");
    setTimeout(() => row.classList.remove("is-fading"), 1000);
  }

  draw() {
    const column = COLUMNS.find((candidate) => candidate.key === this.sort.key);
    const dir = this.sort.dir === "asc" ? 1 : -1;
    const order = (a, b) => {
      const av = column.value(a);
      const bv = column.value(b);
      const result = column.text ? String(av).localeCompare(String(bv)) : av - bv;
      return result * dir || a.name.localeCompare(b.name);
    };
    const total = this.groups.reduce((sum, group) => sum + group.queues.length, 0);
    const limit = this.filter || total <= SHOWN ? Infinity : PER_GROUP;
    let matched = 0;
    const drawn = [];
    for (const group of this.groups) {
      const queues = group.queues.filter((queue) => this.matches(queue)).sort(order);
      const delays = this.shownDelays(group);
      matched += queues.length + delays.length;
      if (!queues.length && !delays.length) continue;
      const idleQueues = queues.filter((queue) => queue.idle);
      const idle = !this.filter && idleQueues.length >= IDLE_FOLD ? idleQueues : [];
      const active = queues.filter((queue) => !idle.includes(queue));
      const cut = active.length > limit + 1 ? limit : Infinity;
      const moreOpen = this.folds.has(`${group.key}|more`);
      const idleOpen = this.folds.has(`${group.key}|idle`);
      const shown = active.filter((queue, index) => moreOpen || index < cut || queue.name === this.revealed);
      const idleShown = idle.filter((queue) => idleOpen || queue.name === this.revealed);
      drawn.push(this.body(`group:${group.key}`, [
        this.groupRow(group, queues, delays),
        delays.map((queue) => this.childRow(queue, "q-exchange-delay")),
        shown.map((queue) => this.queueRows(queue)),
        active.length > cut ? this.foldRow(group, "more", moreOpen ? active.length - cut : active.length - shown.length, moreOpen) : null,
        idle.length ? this.foldRow(group, "idle", idleOpen ? idle.length : idle.length - idleShown.length, idleOpen) : null,
        idleShown.map((queue) => this.queueRows(queue))
      ]));
    }
    this.count.textContent = this.filter ? `${plural(matched, "queue")} ${matched === 1 ? "matches" : "match"} “${this.input.value.trim()}”.` : "";
    if (!drawn.length) {
      const message = this.groups.length ? "No queue matches that filter." : "No queues to show. They appear once the management API answers.";
      drawn.push(this.body("empty", h("tr", {}, h("td", { colspan: COLUMNS.length, class: "empty" }, message))));
    }
    this.place(drawn);
  }

  // Brings a group's rows up to date. A focused control stays the same
  // element, so a poll neither moves focus nor makes a screen reader
  // announce it again.
  body(key, rows) {
    if (!this.bodies.has(key)) this.bodies.set(key, h("tbody", { "data-key": key }));
    const body = this.bodies.get(key);
    const active = document.activeElement;
    if (!active || active === body || !body.contains(active)) return refill(body, rows);
    const fresh = h("tbody", {}, rows);
    if (fresh.childNodes.length === body.childNodes.length && [...fresh.childNodes].every((row, index) => row.isEqualNode(body.childNodes[index]))) return body;
    const match = [...fresh.querySelectorAll("[data-focus-key]")].find((node) => node.dataset.focusKey === focusKey(active));
    if (match && graft(body, fresh, active, match)) return body;
    clear(body).append(...fresh.childNodes);
    match?.focus({ preventScroll: true });
    return body;
  }

  // Puts the bodies in order, moving only those out of place so a focused
  // row never leaves the document.
  place(bodies) {
    for (const [key, body] of this.bodies) {
      if (bodies.includes(body)) continue;
      body.remove();
      this.bodies.delete(key);
    }
    let previous = this.thead;
    for (const body of bodies) {
      if (previous.nextSibling !== body) previous.after(body);
      previous = body;
    }
  }

  groupRow(group, queues, delays) {
    const sum = (key) => queues.reduce((total, queue) => total + queue[key], 0);
    const delayed = this.filter ? sum("delayed") + delays.reduce((total, queue) => total + queue.messages, 0) : group.delayed;
    const meta = [group.unbound ? "no binding, published straight to the queue" : `${group.type || "unknown"} exchange`];
    meta.push(queues.length === group.queues.length ? plural(group.queues.length, "queue") : `${count(queues.length)} of ${plural(group.queues.length, "queue")}`);
    if (delayed) meta.push(`${compact(delayed)} delayed`);
    else if (delays.length) meta.push(plural(delays.length, "empty delay queue"));
    return h("tr", { class: "q-group" },
      h("th", { scope: "rowgroup" },
        h("span", { class: "q-ex" }, group.name),
        h("span", { class: "q-ex-meta" }, meta.join(", "))),
      h("td", { "data-label": "Ready" }, num(sum("ready"))),
      h("td", { "data-label": "Unacked" }, num(sum("unacked"))),
      h("td", { "data-label": "Consumers" }, num(sum("consumers"))),
      h("td", { "data-label": group.unbound ? "Published" : "Into exchange", title: group.unbound ? null : "Published to the exchange" }, speed(group.rate)),
      h("td"), h("td"), h("td"), h("td"));
  }

  foldRow(group, kind, hidden, open) {
    const words = plural(hidden, kind === "idle" ? "idle queue" : "more queue");
    return h("tr", { class: "q-fold" },
      h("td", { colspan: COLUMNS.length },
        h("button", {
          type: "button",
          class: "q-more",
          "aria-expanded": String(open),
          "data-focus-key": `${group.key}|${kind}`,
          onclick: () => this.toggle(this.folds, FOLD_KEY, `${group.key}|${kind}`)
        }, chevron(), open ? `Hide ${words}` : `+${words}`, h("span", { class: "visually-hidden" }, ` under ${group.name}`))));
  }

  queueRows(queue) {
    const open = queue.kids.length > 0 && this.open.has(queue.name);
    return [this.queueRow(queue, open), open ? queue.kids.map((kid) => this.childRow(kid)) : null];
  }

  queueRow(queue, open) {
    const rising = backingUp(queue);
    const roles = ROLE_ORDER.filter((role) => queue.kids.some((kid) => kid.role === role)).map((role) => ROLES[role].toLowerCase());
    const words = [queue.application, queue.also.length ? `also bound to ${queue.also.join(", ")}` : null].filter(Boolean);
    const waits = queue.delayed
      ? h("span", { class: words.length ? "q-wait is-after" : "q-wait" }, `${compact(queue.delayed)} delayed`, queue.delays.length ? ` for ${listed(queue.delays.map(duration))}` : null)
      : null;
    const sub = words.length || waits ? [words.join(" · "), words.length && waits ? " · " : null, waits] : null;
    const classes = ["q-row", queue.idle && "is-idle", queue.name === this.picked && "is-picked"].filter(Boolean).join(" ");
    return h("tr", { class: classes, tabindex: -1, "data-queue": queue.name, "data-focus-key": `${queue.name}|row` },
      h("td", {},
        h("div", { class: "q-head" },
          queue.kids.length
            ? h("button", {
              type: "button",
              class: "q-toggle",
              "aria-expanded": String(open),
              "aria-label": `${capitalize(listed(roles))} ${queue.kids.length === 1 ? "queue" : "queues"} of ${queue.name}`,
              "data-focus-key": `${queue.name}|kids`,
              onclick: () => this.toggle(this.open, OPEN_KEY, queue.name)
            }, chevron())
            : h("span", { class: "q-toggle" }),
          h("div", { class: "q-id" },
            h("a", {
              class: "q-name",
              href: "#map",
              title: "Show on map",
              "data-focus-key": `${queue.name}|map`,
              onclick: (event) => { event.preventDefault(); this.onShow(queue.name); }
            }, queue.name),
            sub ? h("span", { class: "q-app" }, sub) : null))),
      h("td", { "data-label": "Ready" }, num(queue.ready, rising ? "q-ready is-backlog" : "q-ready"),
        rising && queue.backlog_rate > 0.05 ? h("span", { class: "q-trend" }, `+${perSecond(queue.backlog_rate)}`) : null),
      h("td", { "data-label": "Unacked" }, num(queue.unacked)),
      h("td", { "data-label": "Consumers" }, num(queue.consumers, queue.consumers === 0 && queue.ready > 0 ? "q-cons is-none" : null)),
      rateCell("Published", queue.publish_rate),
      rateCell("Delivered", queue.deliver_rate),
      rateCell("Acked", queue.ack_rate),
      h("td", { class: queue.retryCount ? null : "is-still", "data-label": "Retry" }, queue.hasRetry ? num(queue.retryCount, queue.retryCount ? "q-retry is-on" : null) : dash()),
      h("td", { class: queue.errorCount ? null : "is-still", "data-label": "Error" }, queue.hasError ? num(queue.errorCount, queue.errorCount ? "q-error is-on" : null) : dash()));
  }

  childRow(kid, extra = null) {
    const held = { error: "q-error is-on", retry: "q-retry is-on", delay: "q-wait" }[kid.role] || null;
    return h("tr", { class: ["q-row q-child", extra].filter(Boolean).join(" ") },
      h("td", {},
        h("div", { class: "q-head" },
          h("span", { class: "q-toggle" }),
          h("div", { class: "q-id" },
            h("span", { class: "q-kid" }, h("span", { class: `q-role is-${kid.role}` }, ROLES[kid.role]), " ", kid.name),
            h("span", { class: "q-app" }, childDuty(kid))))),
      h("td", { "data-label": "Ready" }, num(kid.ready, kid.ready ? held : null)),
      h("td", { "data-label": "Unacked" }, num(kid.unacked)),
      h("td", { "data-label": "Consumers" }, num(kid.consumers)),
      rateCell("Published", kid.publish_rate),
      rateCell("Delivered", kid.deliver_rate),
      rateCell("Acked", kid.ack_rate),
      h("td"), h("td"));
  }
}
