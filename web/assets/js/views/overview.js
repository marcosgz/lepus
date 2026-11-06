import { api } from "../api.js";
import { h, s, clear, reducedMotion } from "../dom.js";
import { every, pollMs } from "../live.js";
import { TopologyMap } from "../map.js";
import { Memory, buildModel } from "../model.js";
import { RateStrip } from "../rates.js";
import { compact, count, rate } from "../format.js";
import { ProcessList } from "./processes.js";
import { QueueTable } from "./queues.js";
import { ConnectionTable } from "./connections.js";

const RANGE_KEY = "lepus:range";
const RANGES = [
  { key: "10m", age: 600, short: "10 min", phrase: "the last 10 minutes" },
  { key: "1h", age: 3600, short: "1 h", phrase: "the last hour" }
];
const EXPANDED_KEY = "lepus:expanded";

function symbol(kind) {
  const svg = s("svg", { viewBox: "0 0 20 20", "aria-hidden": "true" });
  if (kind === "move") svg.append(s("rect", { class: "sym-token", x: 1, y: 5, width: 18, height: 10, rx: 5 }));
  if (kind === "idle") svg.append(s("rect", { class: "sym-idle", x: 2, y: 5.5, width: 16, height: 9, rx: 4.5 }));
  if (kind === "stop") svg.append(s("rect", { class: "sym-stop", x: 7, y: 0, width: 6, height: 20, rx: 2 }));
  if (kind === "back") svg.append(s("rect", { class: "sym-back", x: 1, y: 5, width: 18, height: 10, rx: 5 }));
  if (kind === "wait") svg.append(s("g", { class: "sym-wait" }, s("circle", { cx: 10, cy: 10, r: 7.5 }), s("path", { d: "M10 5.5V10h3.6" })));
  return h("span", { class: "sym" }, svg);
}

// A compact number for the eye and the exact one for screen readers.
function amount(shown, exact) {
  if (shown === exact) return h("span", { class: "n" }, shown);
  return h("span", { class: "n", title: exact }, h("span", { "aria-hidden": "true" }, shown), h("span", { class: "visually-hidden" }, exact));
}

function load(key, fallback) {
  try { return JSON.parse(localStorage.getItem(key)) ?? fallback; } catch { return fallback; }
}

function store(key, value) {
  try { localStorage.setItem(key, JSON.stringify(value)); } catch {}
}

function section(id, title, ...children) {
  return h("section", { id, class: "page-section", "aria-labelledby": `${id}-title` },
    h("h2", { class: "section-title", id: `${id}-title` }, title),
    ...children);
}

export function overview(root, { meta }) {
  let range = RANGES.find((candidate) => candidate.key === load(RANGE_KEY, "10m")) || RANGES[0];
  const expanded = new Set(load(EXPANDED_KEY, []));
  const memory = new Memory();
  let topology = null;
  let model = null;
  let destroyed = false;

  const headline = h("h1", { class: "headline", id: "map" }, h("span", { class: "quiet" }, "Reading the broker"));
  const subline = h("p", { class: "subline" },
    "Each band is an exchange routing to its queues; every line runs on to the queue's consumer and to acknowledgement. " +
    "Amber tokens are messages on the move, more of them on busier lines. A hollow amber bar is a backlog waiting in its queue, " +
    "violet loops beneath a line are retries, a teal clock counts messages delayed on purpose until they are released, and red bars count messages parked in error queues. Point at a queue for exact numbers, select it to find it in the table.");
  const status = h("p", { class: "status-note", role: "status", hidden: true });
  const mapHost = h("div", { class: "map" });
  const mapNote = h("p", { class: "map-note" });
  const empty = h("p", { class: "map-empty", hidden: true });
  const rangeButtons = RANGES.map((candidate) => h("button", {
    type: "button",
    "aria-pressed": String(candidate === range),
    onclick: () => pickRange(candidate)
  }, candidate.short));
  const ratesNote = h("p", { class: "section-note" });
  const ratesHost = h("div", { class: "tp" });
  const processesHost = h("div");
  const queuesHost = h("div");
  const connectionsHost = h("div");

  root.append(
    h("header", { class: "intro" }, headline, subline),
    status,
    empty,
    mapHost,
    h("div", { class: "map-foot" }, mapNote),
    h("section", { class: "through", "aria-labelledby": "rates-title" },
      h("div", { class: "through-head" },
        h("div", {},
          h("h2", { class: "section-title", id: "rates-title" }, "Message rates"),
          ratesNote),
        h("div", { class: "range-row" },
          h("span", { class: "range-label", id: "range-label" }, "Window"),
          h("div", { class: "seg", role: "group", "aria-labelledby": "range-label" }, rangeButtons))),
      ratesHost),
    section("queues", "Queues", queuesHost),
    section("processes", "Processes", processesHost),
    section("connections", "Connections", connectionsHost));

  const queueTable = new QueueTable(queuesHost, { onShow: (name) => showOnMap(name) });
  const map = new TopologyMap(mapHost, {
    label: "Exchanges, their queues and consumers",
    onPick: (name) => queueTable.pick(name),
    onToggle: (band) => {
      if (expanded.has(band)) expanded.delete(band);
      else expanded.add(band);
      store(EXPANDED_KEY, [...expanded]);
      drawMap();
      const key = expanded.has(band) ? `${band}|less` : `${band}|more`;
      mapHost.querySelector(`[data-key="${CSS.escape(key)}"]`)?.focus({ preventScroll: true });
    }
  });
  const strip = new RateStrip(ratesHost);
  const processList = new ProcessList(processesHost, meta);
  const connectionTable = new ConnectionTable(connectionsHost);

  const describeRange = () => {
    ratesNote.textContent = `Messages per second across the broker over ${range.phrase}, as sampled by RabbitMQ.`;
  };
  describeRange();

  function pickRange(next) {
    if (next === range) return;
    range = next;
    store(RANGE_KEY, range.key);
    rangeButtons.forEach((button, index) => button.setAttribute("aria-pressed", String(RANGES[index] === range)));
    describeRange();
    refreshRates().catch(() => {});
  }

  function renderHeadline(totals) {
    const parts = [];
    const add = (kind, shown, exact, words) => parts.push(h("span", { class: "part" }, symbol(kind), amount(shown, exact), " ", words));
    add("move", `${rate(totals.deliver)} msg/s`, `${count(totals.deliver)} messages a second`, "flowing");
    if (totals.backingUp) add("idle", `${count(totals.backingUp)}`, `${count(totals.backingUp)}`, totals.backingUp === 1 ? "queue backing up" : "queues backing up");
    if (totals.retry >= 0.01) add("back", `${rate(totals.retry)} msg/s`, `${count(totals.retry)} messages a second`, "retrying");
    if (totals.delayed) add("wait", compact(totals.delayed), count(totals.delayed), "delayed");
    add("stop", compact(totals.errors), count(totals.errors), totals.errors === 1 ? "message in error queues" : "messages in error queues");
    clear(headline);
    parts.forEach((part, index) => {
      if (index > 0) headline.append(index === parts.length - 1 ? " and " : ", ");
      headline.append(part);
    });
    headline.append(".");
  }

  // Finds a queue's station, unfolding its band when the queue is folded
  // away, and moves focus there so its numbers show.
  function showOnMap(name) {
    const band = model && model.bands.find((candidate) => candidate.allRows.some((row) => row.kind === "queue" && row.name === name));
    if (band && !band.rows.some((row) => row.name === name)) {
      expanded.add(band.key);
      store(EXPANDED_KEY, [...expanded]);
      drawMap();
    }
    const station = map.find(name);
    if (!station) return;
    const svgTop = station.ownerSVGElement.getBoundingClientRect().top + window.scrollY;
    const bandTop = map.bandTop(name) ?? 0;
    window.scrollTo({ top: Math.max(0, svgTop + bandTop - 24), behavior: reducedMotion.matches ? "auto" : "smooth" });
    station.focus({ preventScroll: true });
    map.flash(name);
  }

  function drawMap() {
    if (!topology) return;
    const bands = new Set(topology.bindings.map((binding) => binding.source)).size;
    const limit = mapHost.clientWidth < 700 || bands > 6 ? 4 : 6;
    model = buildModel(topology, memory, { expanded, limit });
    const hasRows = model.bands.some((band) => band.rows.length);
    empty.hidden = hasRows;
    mapHost.hidden = !hasRows;
    if (!hasRows) {
      empty.textContent = topology.management
        ? "No exchange routes to a queue yet. Lines appear as soon as consumers declare and bind their queues."
        : "Nothing to draw until the management API answers or a worker sends a heartbeat.";
    }
    map.set(model);
    renderHeadline(model.totals);
    const notes = [];
    if (model.unbound.length) {
      const waits = new Map(model.bands.filter((band) => band.delayed && band.delayed.messages).map((band) => [band.key, band.delayed.messages]));
      const names = model.unbound.map((name) => (waits.has(name) ? `${name} (${compact(waits.get(name))} delayed)` : name));
      notes.push(`${names.length === 1 ? "Exchange" : "Exchanges"} with no queue bound: ${names.join(", ")}.`);
    }
    notes.push("The queues table below lists every queue with exact numbers.");
    mapNote.textContent = notes.join(" ");
  }

  async function refresh() {
    const [topologyData, processes, connections] = await Promise.allSettled([api.topology(), api.processes(), api.connections()]);
    if (destroyed) return;
    if (topologyData.status === "fulfilled") {
      topology = topologyData.value;
      status.hidden = topology.management;
      if (!topology.management) {
        status.textContent = `${topology.management_error || "The RabbitMQ management API did not answer"}. Queues and rates are missing; the map shows what worker heartbeats report.`;
      }
      drawMap();
      queueTable.set(topology, model.bands);
    } else {
      status.hidden = false;
      status.textContent = topologyData.reason.message;
    }
    if (processes.status === "fulfilled") processList.set(processes.value);
    if (connections.status === "fulfilled") connectionTable.set(connections.value);
  }

  async function refreshRates() {
    const asked = range;
    const overviewData = await api.overview(asked.age);
    if (destroyed || asked !== range) return;
    strip.set(overviewData, asked);
  }

  const stops = [every(pollMs, refresh), every(() => Math.max(pollMs(), 10_000), refreshRates)];
  return {
    destroy() {
      destroyed = true;
      stops.forEach((stop) => stop());
      map.destroy();
      strip.destroy();
    }
  };
}
