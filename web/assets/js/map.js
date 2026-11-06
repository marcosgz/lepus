import { h, s, clear, graft, reducedMotion } from "./dom.js";
import { compact, count, perSecond, plural, duration } from "./format.js";
import { isLive, onLive } from "./live.js";
import { released } from "./model.js";

// Draws the broker as a transit map. Each band is an exchange: a terminal on
// the left with one line per bound queue. A line runs exchange -> queue ->
// consumer -> the acknowledged terminal on the right. Amber tokens ride each
// segment at a pace that grows with the log of its message rate; violet ones
// loop back through the retry queue beneath the line and red ones drop into
// the error queue. A backlog is a hollow amber bar piling up at the queue.
// Messages delayed on purpose wait in a teal clock pill tucked under the
// queue, or under the exchange name when they are released to the exchange.

const MAX_TOKENS = 320;
const RAIL = 13;
const WAIT = 17;
const WAIT_LINE = 18;
const WIDE = 1100;

const visualRate = (rate) => (rate > 0 ? Math.min(2.6, 0.2 + 0.6 * Math.log10(1 + rate)) : 0);
const charsFor = (px, size = 7.2) => Math.max(4, Math.floor(px / size));

function clock(x, y) {
  return s("g", { class: "m-clock" },
    s("circle", { cx: x, cy: y, r: 4.5 }),
    s("path", { d: `M${x} ${y - 2.6}V${y}h2.2` }));
}

const pillWidth = (text) => text.length * 6.4 + 27;

// A pill with a clock face: messages waiting out a delay.
function waitPill(x, y, text, title) {
  return s("g", { class: "m-wait" },
    title ? s("title", {}, title) : null,
    s("rect", { class: "m-wait-box", x, y: y - 8, width: pillWidth(text), height: 16, rx: 8 }),
    clock(x + 10.5, y),
    s("text", { class: "m-wait-n", x: x + 19, y: y + 4 }, text));
}

function fit(text, chars) {
  if (text.length <= chars) return text;
  return `${text.slice(0, Math.max(1, chars - 1))}…`;
}

export class TopologyMap {
  constructor(host, { label, onPick, onToggle }) {
    this.host = host;
    this.onPick = onPick;
    this.onToggle = onToggle;
    this.model = null;
    this.width = 0;
    this.flows = new Map();
    this.tokens = [];
    this.frame = null;
    this.visible = true;
    this.uid = `tm${Math.random().toString(36).slice(2, 8)}`;
    this.svg = s("svg", { role: "group", "aria-label": label });
    this.tokenLayer = s("g", { "aria-hidden": "true" });
    this.tip = h("div", { class: "m-tip", role: "tooltip", hidden: true });
    host.append(this.svg, this.tip);
    this.tickBound = (time) => this.tick(time);
    this.offLive = onLive(() => this.wake());
    this.onVisibility = () => this.wake();
    document.addEventListener("visibilitychange", this.onVisibility);
    this.onMotion = () => this.render();
    reducedMotion.addEventListener("change", this.onMotion);
    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(host);
    this.viewObserver = new IntersectionObserver((entries) => {
      this.visible = entries.some((entry) => entry.isIntersecting);
      this.wake();
    });
    this.viewObserver.observe(host);
  }

  destroy() {
    this.resizeObserver.disconnect();
    this.viewObserver.disconnect();
    this.offLive();
    document.removeEventListener("visibilitychange", this.onVisibility);
    reducedMotion.removeEventListener("change", this.onMotion);
    cancelAnimationFrame(this.frame);
    this.frame = null;
  }

  set(model) {
    this.model = model;
    this.render();
  }

  resize() {
    const width = Math.round(this.host.clientWidth);
    if (width && width !== this.width) {
      this.width = width;
      if (this.model) this.render();
    }
  }

  // Geometry

  layout() {
    const width = this.width || Math.round(this.host.clientWidth) || 1000;
    const wide = width >= WIDE;
    const nameCol = wide ? Math.min(260, Math.max(180, Math.round(width * 0.14))) : 0;
    const capL = nameCol + 14;
    const capR = width - 12;
    const span = capR - capL;
    const geo = {
      width, wide, nameCol, capL, capR,
      qx: Math.round(capL + span * (wide ? 0.4 : 0.44)),
      cx: Math.round(capL + span * (wide ? 0.72 : 0.74)),
      rowH: wide ? 56 : 66,
      speed: wide ? 150 : 90,
      bands: []
    };
    let y = 50;
    for (const band of this.model.bands) {
      const head = wide ? 0 : 30;
      const top = y + head;
      let rowTop = top + (wide ? 0 : 6);
      const rows = band.rows.map((row) => {
        const placed = { row, y: rowTop + geo.rowH / 2 };
        rowTop += geo.rowH + (!wide && row.delayed > 0 ? WAIT_LINE : 0);
        return placed;
      });
      const bottom = rowTop - (wide ? 0 : 6);
      geo.bands.push({ band, top: y, rows, bottom });
      y = bottom + (wide ? 26 : 22);
    }
    geo.height = Math.max(y - 10, 120);
    return geo;
  }

  // Static drawing, redone on every poll; tokens live in their own layer.

  render() {
    if (!this.model) return;
    const active = this.svg.contains(document.activeElement) ? document.activeElement : null;
    const kept = this.stations;
    const geo = this.layout();
    this.geo = geo;
    const svg = this.svg;
    const fresh = s("svg");
    svg.setAttribute("viewBox", `0 0 ${geo.width} ${geo.height}`);
    svg.setAttribute("width", geo.width);
    svg.setAttribute("height", geo.height);
    this.base = s("g");
    this.stations = s("g");
    this.over = s("g");
    fresh.append(this.gradients(), this.base, this.stations, this.tokenLayer, this.over);

    this.drawHead(geo);
    if (geo.wide && geo.bands.length) {
      const first = geo.bands[0].rows[0];
      const last = geo.bands[geo.bands.length - 1].rows.slice(-1)[0];
      if (first && last) this.drawCap(geo.capR, first.y - 18, last.y + 18);
    }
    const flows = new Map();
    for (const bandGeo of geo.bands) this.drawBand(geo, bandGeo, flows);
    this.swapIn(svg, fresh, active, kept);
    this.setFlows(flows);
  }

  find(key) {
    return key ? [...this.stations.querySelectorAll("[data-key]")].find((node) => node.dataset.key === key) : null;
  }

  // Swaps the new drawing in. A focused station stays the same element, only
  // brought up to date, so a poll neither moves focus nor makes a screen
  // reader announce it again.
  swapIn(svg, fresh, active, kept) {
    const match = this.find(active ? active.dataset.key : this.tipKey);
    if (active && match && graft(svg, fresh, active, match)) {
      this.stations = kept;
      active.tip = match.tip;
      active.anchor = match.anchor;
      if (!this.tip.hidden) this.showTip(active);
      return;
    }
    clear(svg).append(...fresh.childNodes);
    if (active && match) match.focus({ preventScroll: true });
    else if (match && !active) this.showTip(match);
    else this.hideTip();
  }

  drawHead(geo) {
    const { totals } = this.model;
    const left = s("text", { x: geo.capL - 9, y: 22 },
      s("tspan", { class: "m-cap-num" }, perSecond(totals.publish)),
      s("tspan", { class: "m-cap-label", dx: 6 }, "published"));
    const right = s("text", { x: geo.capR + 9, y: 22, "text-anchor": "end" },
      s("tspan", { class: "m-cap-num" }, perSecond(totals.ack)),
      s("tspan", { class: "m-cap-label", dx: 6 }, "acknowledged"));
    this.base.append(left, right);
    if (geo.wide) {
      this.base.append(
        s("text", { class: "m-cap-label", x: 0, y: 22 }, "Exchange"),
        s("text", { class: "m-cap-label", x: geo.qx - 9, y: 22 }, "Queue"),
        s("text", { class: "m-cap-label", x: geo.cx - 9, y: 22 }, "Consumer"));
    }
  }

  drawCap(x, top, bottom, quiet = false) {
    this.base.append(s("rect", { class: quiet ? "m-cap is-quiet" : "m-cap", x: x - 9, y: top, width: 18, height: Math.max(34, bottom - top), rx: 9 }));
  }

  drawBand(geo, { band, top, rows }, flows) {
    if (!rows.length) return;
    const firstY = rows[0].y;
    const lastY = rows[rows.length - 1].y;
    const meta = [band.type].filter(Boolean);
    if (band.rate >= 0.01) meta.push(`${perSecond(band.rate)} in`);
    const delayed = band.delayed && band.delayed.messages ? band.delayed : null;
    const waits = delayed ? released(delayed, `the ${band.name} exchange`) : null;
    const title = s("title", {}, [`${band.name}, ${meta.join(", ")}`, waits].filter(Boolean).join(". "));
    if (geo.wide) {
      const chars = charsFor(geo.nameCol - 8, 8.8);
      this.base.append(
        s("text", { class: band.quiet ? "m-ex is-quiet" : "m-ex", x: 0, y: firstY - 2 }, title, fit(band.name, chars)),
        s("text", { class: "m-meta", x: 0, y: firstY + 17 }, fit(meta.join(", "), charsFor(geo.nameCol - 8, 6.6))));
      if (delayed) this.over.append(waitPill(0, firstY + 33, `${compact(delayed.messages)} delayed`, waits));
    } else {
      this.base.append(s("text", { x: geo.capL - 9, y: top + 18 }, title,
        s("tspan", { class: band.quiet ? "m-ex is-quiet" : "m-ex" }, fit(band.name, charsFor(geo.width * 0.55, 8.8))),
        s("tspan", { class: "m-meta", dx: 8 }, meta.join(", ")),
        delayed ? s("tspan", { class: "m-meta m-wait-n", dx: 8 }, `${compact(delayed.messages)} delayed`) : null));
    }
    for (const { row, y } of rows) {
      if (row.kind === "queue") this.drawQueue(geo, band, row, y, flows);
      else if (row.kind === "exchange") this.drawExchangeRow(geo, band, row, y, flows);
      else this.drawFold(geo, band, row, y);
    }
    this.drawCap(geo.capL, firstY - 18, lastY + 18, band.quiet);
    if (!geo.wide) this.drawCap(geo.capR, firstY - 18, lastY + 18, band.quiet);
  }

  line(x1, x2, y, cls) {
    this.base.append(s("path", { class: cls, d: `M${x1} ${y}H${x2}` }));
  }

  drawQueue(geo, band, row, y, flows) {
    const { capL, capR, qx, cx, wide } = geo;
    const q = row.queue;
    const noConsumer = q.consumers === 0;
    const quiet = row.quiet;
    this.line(capL, qx, y, quiet ? "m-line is-quiet" : "m-line");
    this.line(qx, cx, y, quiet ? "m-line is-quiet" : noConsumer ? "m-line is-future" : "m-line");
    this.line(cx, capR, y, quiet ? "m-line is-quiet" : noConsumer ? "m-line is-future" : "m-line");

    let barW = 0;
    if (row.backlog > 0) {
      const text = compact(row.backlog);
      const room = (qx - capL) * 0.5;
      barW = Math.max(text.length * 7.4 + 14, Math.min(room, 22 + 24 * Math.log10(row.backlog)));
      const x = qx - 12 - barW;
      this.over.append(
        s("rect", { class: "m-backlog", x, y: y - 8, width: barW, height: 16, rx: 8 }),
        s("text", { class: "m-backlog-n", x: x + barW / 2, y: y + 4, "text-anchor": "middle" }, text));
    }

    if (wide && row.delayed > 0) {
      const full = `${compact(row.delayed)} delayed`;
      const room = qx - 22 - (capL + 18);
      const text = pillWidth(full) <= room ? full : compact(row.delayed);
      const x = qx - 22 - pillWidth(text);
      if (x >= capL + 18) {
        this.base.append(s("path", { class: "m-wait-hook", d: `M${qx - 22} ${y + WAIT}H${qx - 9}q7 0 7-7` }));
        this.over.append(waitPill(x, y + WAIT, text, released(row.delay, row.name)));
      }
    }

    const keysX = capL + 18;
    if (wide && (row.keys.length || row.also.length) && band.type !== "fanout") {
      const parts = [];
      if (row.keys.length) parts.push(row.keys.join(", "));
      if (row.also.length) parts.push(`also ${row.also.join(", ")}`);
      const room = qx - barW - 40 - keysX;
      if (room > 40) this.base.append(s("text", { class: "m-keys", x: keysX, y: y - 11 }, fit(parts.join("; "), charsFor(room, 6.4))));
    }

    let errorX = null;
    if (row.retry) {
      const active = row.retry.messages > 0 || row.rates.retry > 0;
      this.base.append(s("path", { class: active ? "m-rail is-active" : "m-rail", d: `M${cx - 10} ${y + RAIL}H${qx + 10}` }));
      if (row.retry.messages > 0) {
        const text = `${compact(row.retry.messages)} retrying`;
        const w = text.length * 6.4 + 14;
        const mid = (qx + cx) / 2;
        this.over.append(
          s("rect", { class: "m-retry", x: mid - w / 2, y: y + RAIL - 8, width: w, height: 16, rx: 8 }),
          s("text", { class: "m-retry-n", x: mid, y: y + RAIL + 4, "text-anchor": "middle" }, text));
      }
      flows.set(`${row.key}|retry`, { x1: cx - 12, x2: qx + 12, y: y + RAIL, rate: row.rates.retry, kind: "back" });
    }
    if (row.error && row.error.messages > 0) {
      errorX = wide ? Math.round(cx + Math.min(150, (capR - cx) * 0.45)) : capR - 28;
      const n = row.error.messages;
      const size = Math.min(24, 8 + 6 * Math.log10(Math.max(1, n)));
      this.base.append(s("path", { class: "m-spur", d: `M${cx + 8} ${y + RAIL}H${errorX}` }));
      this.over.append(
        s("rect", { class: "m-block", x: errorX - 3, y: y + 6, width: 6, height: size, rx: 2 }),
        s("text", { class: "m-block-n", x: wide ? errorX + 8 : capR - 14, y: wide ? y + RAIL + 5 : y + 34, "text-anchor": wide ? "start" : "end" }, `${compact(n)} in error`));
      flows.set(`${row.key}|error`, { x1: cx + 10, x2: errorX - 6, y: y + RAIL, rate: row.rates.error, kind: "stop" });
    }

    flows.set(`${row.key}|in`, { x1: capL + 12, x2: qx - 14 - barW, y, rate: row.rates.in, kind: "move" });
    if (!noConsumer) {
      flows.set(`${row.key}|out`, { x1: qx + 12, x2: cx - 10, y, rate: row.rates.out, kind: "move" });
      flows.set(`${row.key}|ack`, { x1: cx + 10, x2: capR - 12, y, rate: row.rates.ack, kind: "move" });
    }

    const states = ["m-station", quiet ? "is-quiet" : "", row.rising ? "is-backlog" : ""].join(" ").trim();
    const consumerStates = ["m-station", quiet ? "is-quiet" : "", noConsumer ? "is-idle" : "", row.stopped ? "is-stopped" : ""].join(" ").trim();
    const group = s("a", { class: "m-row", href: "#queues", "data-key": row.key, "aria-label": this.describe(band, row).join(". ") });
    const hit = s("rect", { class: "m-hit", x: qx - 16, y: y - 26, width: capR - qx + 16, height: 46, rx: 6 });
    const station = s("g", { class: states },
      s("circle", { class: "m-dot", cx: qx, cy: y, r: 7 }));
    const consumer = s("g", { class: consumerStates },
      s("circle", { class: "m-halo", cx, cy: y, r: 15 }),
      s("circle", { class: "m-dot", cx, cy: y, r: 6 }));
    const consumerText = row.consumerLabel || "no consumer";
    let name;
    let consumerLabel = null;
    if (wide) {
      const sub = quiet || row.rates.in < 0.01 ? "" : ` ${perSecond(row.rates.in)}`;
      name = s("text", { class: "m-name", x: qx + 14, y: y - 11 },
        fit(row.name, charsFor(cx - qx - 40 - sub.length * 6.4, 7.4)), sub ? s("tspan", { class: "m-sub" }, sub) : null);
      const ackSub = row.rates.ack >= 0.01 && !quiet ? ` ${perSecond(row.rates.ack)}` : "";
      consumerLabel = s("text", {
        class: ["m-consumer", row.consumerLabel ? "" : "is-missing", row.stopped ? "is-stopped" : ""].join(" ").trim(),
        x: cx + 14,
        y: y - 11
      }, fit(consumerText, charsFor(capR - cx - 30 - ackSub.length * 6.4, 7)), ackSub ? s("tspan", { class: "m-sub" }, ackSub) : null);
    } else {
      const room = capR - capL - 30;
      const shownName = fit(row.name, charsFor(room * 0.6, 7.4));
      const rest = charsFor(room - shownName.length * 7.4 - 20, 6.6);
      name = s("text", { class: "m-name", x: capL + 16, y: y - 16 }, shownName,
        rest > 5 ? s("tspan", { class: row.stopped ? "m-sub m-sub-stop" : "m-sub" }, ` → ${fit(consumerText, rest)}`) : null);
      if (!quiet && (row.rates.in >= 0.01 || row.rates.ack >= 0.01)) {
        consumerLabel = s("text", { class: "m-meta", x: capL + 16, y: y + 24 }, `${perSecond(row.rates.in)} in, ${perSecond(row.rates.ack)} acked`);
      }
      if (row.delayed > 0) {
        const text = `${compact(row.delayed)} delayed`;
        const after = `after ${row.delay.queues.filter((kid) => kid.messages > 0).map((kid) => duration(kid.delay_ms)).join(" or ")}`;
        const x = capL + 16 + pillWidth(text) + 8;
        this.over.append(waitPill(capL + 16, y + 24 + WAIT_LINE - 4, text, released(row.delay, row.name)));
        this.base.append(s("text", { class: "m-meta", x, y: y + 24 + WAIT_LINE }, fit(after, charsFor(capR - x - (errorX === null ? 12 : 90), 6.6))));
      }
    }
    group.append(...[hit, station, consumer, name, consumerLabel].filter(Boolean));
    this.bindRow(group, band, row);
    this.stations.append(group);
  }

  drawExchangeRow(geo, band, row, y, flows) {
    const { capL, qx, wide } = geo;
    this.line(capL, qx, y, row.quiet ? "m-line is-quiet" : "m-line");
    this.base.append(s("rect", { class: row.quiet ? "m-cap is-quiet" : "m-cap", x: qx - 6, y: y - 12, width: 12, height: 24, rx: 6 }));
    const keys = row.keys.length ? ` by ${row.keys.join(", ")}` : "";
    this.base.append(s("text", { class: "m-name", x: wide ? qx + 14 : capL + 16, y: wide ? y + 4 : y - 16 },
      s("title", {}, `${band.name} routes to the ${row.name} exchange${keys}`),
      `to ${fit(row.name, 40)}`, s("tspan", { class: "m-sub" }, " exchange")));
    flows.set(`${row.key}|in`, { x1: capL + 12, x2: qx - 10, y, rate: row.rates.in, kind: "move" });
  }

  drawFold(geo, band, row, y) {
    const { capL, qx, wide } = geo;
    const more = row.kind === "more";
    if (more) this.line(capL, qx - 16, y, "m-line is-quiet");
    let text;
    if (!more) text = "Show fewer";
    else if (row.quietCount === row.count) text = `+${count(row.count)} quiet ${row.count === 1 ? "queue" : "queues"}`;
    else text = `+${count(row.count)} more ${row.count === 1 ? "queue" : "queues"}`;
    const w = text.length * 6.9 + 22;
    const x = wide || !more ? qx - 12 : capL + 22;
    const label = more ? `${text}${row.quietCount && row.quietCount !== row.count ? `, ${row.quietCount} of them quiet` : ""}. Show them` : `Show fewer queues for ${band.name}`;
    const button = s("g", { class: "m-more", role: "button", tabindex: 0, "aria-expanded": String(!more), "aria-label": label, "data-key": row.key },
      s("rect", { class: "m-more-box", x, y: y - 11, width: w, height: 22, rx: 11 }),
      s("text", { class: "m-more-n", x: x + w / 2, y: y + 4, "text-anchor": "middle" }, text));
    const toggle = () => this.onToggle(band.key);
    button.addEventListener("click", toggle);
    button.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        toggle();
      }
    });
    this.stations.append(button);
    if (more) {
      const bits = [];
      if (row.backlog) bits.push(`${compact(row.backlog)} ready`);
      if (row.rates.in >= 0.01) bits.push(`${perSecond(row.rates.in)} in`);
      if (row.errors) bits.push(`${compact(row.errors)} in error`);
      if (row.delayed) bits.push(`${compact(row.delayed)} delayed`);
      if (bits.length) this.base.append(s("text", { class: "m-meta", x: x + w + 10, y: y + 4 }, bits.join(", ")));
    }
  }

  describe(band, row) {
    const q = row.queue;
    const lines = [row.name];
    const bound = band.key ? `From ${band.name}${row.keys.length ? ` by ${row.keys.join(", ")}` : ""}` : "Published straight to the queue";
    lines.push(row.also.length ? `${bound}, also from ${row.also.join(", ")}` : bound);
    const held = [`${count(q.ready)} ready`, `${count(q.unacked)} unacked`];
    if (q.backlog_rate > 0.05) held.push(`growing ${perSecond(q.backlog_rate)}`);
    else if (q.backlog_rate < -0.05 && q.ready) held.push(`draining ${perSecond(-q.backlog_rate)}`);
    lines.push(held.join(", "));
    lines.push(`Published ${perSecond(q.publish_rate)}, delivered ${perSecond(q.deliver_rate)}, acknowledged ${perSecond(q.ack_rate)}`);
    if (q.consumers === 0) {
      lines.push("No consumer is subscribed");
    } else {
      const names = row.consumers.map((c) => c.class_name || c.connection_name).filter(Boolean);
      lines.push(`${plural(q.consumers, "consumer channel")}${names.length ? `: ${names.join(", ")}` : ""}`);
    }
    if (row.stopped) lines.push("Errors in the last few minutes");
    if (row.retry) lines.push(`Retry ${row.retry.name}: ${count(row.retry.messages)} waiting${row.retry.ttl ? ` ${duration(row.retry.ttl)}` : ""}`);
    if (row.error) lines.push(`Error ${row.error.name}: ${plural(row.error.messages, "message")}`);
    if (row.delay.queues.length) lines.push(row.delayed ? released(row.delay, row.name) : `Delay queues for ${row.delay.queues.map((kid) => duration(kid.delay_ms)).join(", ")}, empty`);
    for (const consumer of row.consumers) {
      if (!consumer.delays || !consumer.delays.length) continue;
      const after = consumer.delays.map(duration).join(" or ");
      lines.push(`${consumer.class_name} hands messages back with delay! after ${after}${consumer.delayed ? `, ${count(consumer.delayed)} so far` : ""}`);
    }
    return lines;
  }

  bindRow(group, band, row) {
    const show = () => this.showTip(group);
    const hide = () => this.hideTip();
    group.addEventListener("pointerenter", show);
    group.addEventListener("focus", show);
    group.addEventListener("pointerleave", hide);
    group.addEventListener("blur", hide);
    group.addEventListener("keydown", (event) => { if (event.key === "Escape") hide(); });
    group.addEventListener("click", (event) => {
      event.preventDefault();
      this.onPick(row.name);
    });
    group.tip = () => this.describe(band, row);
    const y = Number(group.querySelector("circle").getAttribute("cy"));
    group.anchor = () => ({ x: this.geo.qx, y });
  }

  showTip(group) {
    if (!group.tip) return;
    this.tipKey = group.dataset.key;
    const [head, ...rest] = group.tip();
    clear(this.tip).append(h("b", {}, head), ...rest.map((line) => h("span", {}, line)));
    this.tip.hidden = false;
    const p = group.anchor();
    const hostW = this.host.clientWidth;
    const tipW = this.tip.offsetWidth;
    const tipH = this.tip.offsetHeight;
    const left = Math.max(0, Math.min(hostW - tipW, p.x - 24));
    const above = p.y - 34 - tipH;
    this.tip.style.left = `${Math.round(left)}px`;
    this.tip.style.top = `${Math.round(above >= -40 ? above : p.y + 30)}px`;
  }

  hideTip() {
    this.tipKey = null;
    this.tip.hidden = true;
  }

  gradients() {
    const defs = s("defs");
    for (const kind of ["move", "back", "stop"]) {
      for (const dir of ["f", "b"]) {
        defs.append(s("linearGradient", { id: `${this.uid}-${kind}-${dir}`, x1: dir === "f" ? 0 : 1, x2: dir === "f" ? 1 : 0, y1: 0, y2: 0 },
          s("stop", { offset: 0, class: `g-trail-${kind}`, "stop-opacity": 0 }),
          s("stop", { offset: 1, class: `g-trail-${kind}`, "stop-opacity": 0.9 })));
      }
    }
    return defs;
  }

  // Motion

  setFlows(next) {
    const fresh = this.flows.size === 0;
    for (const [key, flow] of next) {
      const old = this.flows.get(key);
      flow.acc = old ? old.acc : Math.random();
      flow.length = Math.max(1, Math.abs(flow.x2 - flow.x1));
      if (!old && !fresh) flow.seed = true;
      if (fresh) flow.seed = true;
    }
    this.flows = next;
    this.tokens = this.tokens.filter((token) => {
      if (this.flows.has(token.flow)) return true;
      token.el.remove();
      token.trail.remove();
      return false;
    });
    if (reducedMotion.matches) {
      this.drawStill();
      return;
    }
    this.tokens = this.tokens.filter((token) => {
      if (!token.still) return true;
      token.el.remove();
      token.trail.remove();
      return false;
    });
    for (const [key, flow] of this.flows) {
      if (!flow.seed) continue;
      flow.seed = false;
      const pace = visualRate(flow.rate) * (this.geo.wide ? 1 : 0.7);
      const n = Math.floor((pace * flow.length) / this.geo.speed);
      for (let i = 0; i < n && this.tokens.length < MAX_TOKENS; i++) this.spawn(key, flow, (i + Math.random() * 0.6) / Math.max(1, n));
    }
    this.place();
    this.wake();
  }

  drawStill() {
    for (const token of this.tokens) {
      token.el.remove();
      token.trail.remove();
    }
    this.tokens = [];
    for (const [key, flow] of this.flows) {
      if (flow.rate > 0) this.spawn(key, flow, 0.5, true);
    }
    this.place();
  }

  spawn(key, flow, t = 0, still = false) {
    const el = s("rect", { class: flow.kind === "move" ? "t-token" : `t-token is-${flow.kind}`, width: 18, height: 10, rx: 5 });
    const trail = s("rect", { height: 4, width: 42, rx: 2, fill: `url(#${this.uid}-${flow.kind}-${flow.x2 >= flow.x1 ? "f" : "b"})` });
    if (still) trail.setAttribute("visibility", "hidden");
    this.tokenLayer.append(trail, el);
    this.tokens.push({ flow: key, t, el, trail, still });
  }

  place() {
    for (const token of this.tokens) {
      const flow = this.flows.get(token.flow);
      if (!flow) continue;
      const dir = flow.x2 >= flow.x1 ? 1 : -1;
      const x = flow.x1 + (flow.x2 - flow.x1) * token.t;
      token.el.setAttribute("x", (x - 9).toFixed(1));
      token.el.setAttribute("y", flow.y - 5);
      const tx = dir > 0 ? x - 9 - 38 : x + 9 - 4;
      const visible = Math.abs(x - flow.x1) > 30;
      token.trail.setAttribute("x", tx.toFixed(1));
      token.trail.setAttribute("y", flow.y - 2);
      token.trail.setAttribute("visibility", visible && !token.still ? "visible" : "hidden");
      const edge = Math.min(token.t, 1 - token.t);
      const opacity = token.still ? 1 : Math.max(0, Math.min(1, edge * 12));
      token.el.setAttribute("opacity", opacity.toFixed(2));
      token.trail.setAttribute("opacity", opacity.toFixed(2));
    }
  }

  wake() {
    if (this.frame === null && !reducedMotion.matches) this.frame = requestAnimationFrame(this.tickBound);
  }

  tick(now) {
    this.frame = null;
    if (!isLive() || document.hidden || !this.visible || !this.geo) {
      this.lastTime = null;
      return;
    }
    const dt = Math.min(0.1, (now - (this.lastTime || now)) / 1000);
    this.lastTime = now;
    const scale = this.geo.wide ? 1 : 0.7;
    for (const [key, flow] of this.flows) {
      const pace = visualRate(flow.rate) * scale;
      if (!pace) continue;
      flow.acc += dt * pace * (0.6 + Math.random() * 0.8);
      while (flow.acc >= 1) {
        flow.acc -= 1;
        if (this.tokens.length < MAX_TOKENS) this.spawn(key, flow);
      }
    }
    this.tokens = this.tokens.filter((token) => {
      const flow = this.flows.get(token.flow);
      token.t += (dt * this.geo.speed) / flow.length;
      if (token.t < 1) return true;
      token.el.remove();
      token.trail.remove();
      return false;
    });
    this.place();
    this.frame = requestAnimationFrame(this.tickBound);
  }
}
