import { h, refill } from "../dom.js";
import { ago, bytes, compact, count, duration, plural, toTime } from "../format.js";

const WORKERS_SHOWN = 8;
const CONSUMERS_SHOWN = 3;

const byName = (a, b) => String(a.application || a.name).localeCompare(String(b.application || b.name));

function health(process, meta, now) {
  const age = now - (toTime(process.last_heartbeat_at) || 0);
  const interval = (meta.heartbeat_interval || 60) * 1000;
  if (age <= interval * 1.5) return "ok";
  if (age <= (meta.alive_threshold || 300) * 1000) return "late";
  return "stale";
}

function counter(n, word, cls) {
  const shown = compact(n);
  return h("span", { class: n ? cls : null, title: `${count(n)} ${word}` },
    h("span", { "aria-hidden": "true" }, `${shown} ${word}`),
    h("span", { class: "visually-hidden" }, `${count(n)} ${word}`));
}

// Workers older than delay! report neither delays nor a delayed count.
function consumerItem(consumer) {
  const delays = consumer.delays && consumer.delays.length ? `, delay! after ${consumer.delays.map(duration).join(" or ")}` : "";
  return h("li", { class: "con" },
    h("span", { class: "con-name" },
      h("b", {}, consumer.class_name),
      h("span", {}, ` on ${consumer.queue}, ${plural(consumer.threads || 0, "thread")}${delays}`)),
    h("span", { class: "con-counts" },
      counter(consumer.processed, "processed", null),
      consumer.delayed || delays ? counter(consumer.delayed || 0, "delayed", "is-delayed") : null,
      counter(consumer.rejected, "rejected", "is-rejected"),
      counter(consumer.errored, "errored", "is-errored")));
}

function workerItem(worker, meta, now, open) {
  const state = health(worker, meta, now);
  const beat = h("span", { class: state === "ok" ? null : `is-${state}` },
    state === "ok" ? `heartbeat ${ago(worker.last_heartbeat_at, now)}` : `last heartbeat ${ago(worker.last_heartbeat_at, now)}`);
  const consumers = [...(worker.consumers || [])].sort((a, b) => String(a.class_name).localeCompare(String(b.class_name)));
  return h("li", { class: state === "ok" ? "worker" : `worker is-${state}` },
    h("div", { class: "worker-head" },
      h("span", { class: "worker-name" }, worker.name),
      h("span", { class: "worker-meta" },
        `pid ${worker.pid}, ${bytes(worker.rss_memory)}, ${plural(worker.connections || 0, "connection")}, `, beat)),
    consumers.length ? h("ul", { class: "cons" }, consumers.slice(0, CONSUMERS_SHOWN).map(consumerItem)) : null,
    consumers.length > CONSUMERS_SHOWN
      ? h("details", { class: "con-more", open: open.has(worker.id), ontoggle: (event) => { if (event.target.open) open.add(worker.id); else open.delete(worker.id); } },
        h("summary", { "data-focus-key": `${worker.id}|more` }, `${plural(consumers.length - CONSUMERS_SHOWN, "more consumer")}`),
        h("ul", { class: "cons" }, consumers.slice(CONSUMERS_SHOWN).map(consumerItem)))
      : null);
}

// Supervisors with their workers and each worker's consumers, as the
// heartbeats last reported them.
export class ProcessList {
  constructor(host, meta) {
    this.meta = meta;
    this.note = h("p", { class: "section-note" });
    this.list = h("ul", { class: "procs" });
    this.all = false;
    this.open = new Set();
    this.more = h("button", { type: "button", class: "btn btn-quiet btn-small", hidden: true, onclick: () => { this.all = !this.all; this.set(this.processes); } });
    host.append(this.note, this.list, h("div", { class: "list-foot" }, this.more));
  }

  set(processes) {
    this.processes = processes;
    const now = Date.now();
    const supervisors = processes.filter((p) => p.kind === "Supervisor").sort(byName);
    const workers = processes.filter((p) => p.kind !== "Supervisor").sort(byName);
    const known = new Set(supervisors.map((p) => p.id));
    const hosts = new Set(processes.map((p) => p.hostname));
    const interval = this.meta.heartbeat_interval || 60;
    this.note.textContent = processes.length
      ? `${plural(supervisors.length, "supervisor")} running ${plural(workers.length, "worker")} on ${plural(hosts.size, "host")}. Workers report every ${interval} s; counts run from each worker's start, and a message handed back with delay! counts as delayed, not processed.`
      : "";
    if (!processes.length) {
      refill(this.list, h("li", { class: "empty" }, "No Lepus process has sent a heartbeat. Workers started with lepus start show up here within one heartbeat."));
      return;
    }
    const groups = supervisors.map((supervisor) => ({ supervisor, workers: workers.filter((w) => w.supervisor_id === supervisor.id).sort((a, b) => a.name.localeCompare(b.name)) }));
    const orphans = workers.filter((w) => !known.has(w.supervisor_id));
    if (orphans.length) groups.push({ supervisor: null, workers: orphans });
    this.more.hidden = workers.length <= WORKERS_SHOWN;
    this.more.textContent = this.all ? "Show fewer" : `Show all ${count(workers.length)} workers`;
    let budget = this.all ? Infinity : WORKERS_SHOWN;
    for (const group of groups) {
      group.hidden = Math.max(0, group.workers.length - budget);
      group.workers = group.workers.slice(0, Math.max(0, budget));
      budget -= group.workers.length;
    }
    refill(this.list, groups.filter((group) => group.workers.length || !group.hidden).map(({ supervisor, workers: own, hidden }) => h("li", {},
      h("div", { class: "sup" },
        h("span", { class: "sup-name" }, supervisor ? supervisor.application || supervisor.name : "Without a supervisor"),
        supervisor ? h("span", { class: "sup-meta" }, `${supervisor.hostname}, pid ${supervisor.pid}, ${plural(own.length + hidden, "worker")}`) : null),
      own.length ? h("ul", { class: "workers" }, own.map((worker) => workerItem(worker, this.meta, now, this.open))) : null)));
  }
}
