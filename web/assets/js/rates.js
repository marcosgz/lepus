import { h, s, clear } from "./dom.js";
import { hourMinute, perSecond, rate } from "./format.js";

const SERIES = [
  ["publish", "Published"],
  ["deliver", "Delivered"],
  ["ack", "Acknowledged"],
  ["redeliver", "Redelivered"]
];

function niceTop(value) {
  if (value <= 4) return 4;
  const magnitude = 10 ** Math.floor(Math.log10(value));
  for (const m of [1, 2, 2.5, 3, 4, 5, 6, 8, 10]) if (m * magnitude >= value) return m * magnitude;
  return 10 * magnitude;
}

function ticks(start, end, px) {
  const steps = [30, 60, 120, 300, 600, 900, 1800, 3600].map((seconds) => seconds * 1000);
  const step = steps.find((ms) => (ms / (end - start)) * px >= 84) || steps[steps.length - 1];
  const out = [];
  for (let t = Math.ceil(start / step) * step; t <= end; t += step) out.push(t);
  return out;
}

// Message rates across the broker over the chosen window, from the samples
// the management API keeps: acknowledged as the filled area, published as
// the ink line and delivered as the dashed amber one, redeliveries in violet.
export class RateStrip {
  constructor(host) {
    this.host = host;
    this.totals = h("dl", { class: "tp-totals" });
    this.chart = h("div", { class: "tp-chart" });
    this.readout = h("p", { class: "tp-readout", "aria-hidden": "true" });
    this.tableBody = h("tbody");
    this.caption = h("caption", { class: "visually-hidden" });
    host.append(
      this.totals,
      this.chart,
      h("div", { class: "tp-foot" },
        this.readout,
        h("details", { class: "data-table" },
          h("summary", {}, "Show as table"),
          h("div", { class: "data-scroll" },
            h("table", {},
              this.caption,
              h("thead", {}, h("tr", {},
                h("th", { scope: "col" }, "Until"),
                SERIES.map(([, name]) => h("th", { scope: "col" }, `${name}/s`)))),
              this.tableBody)))));
    this.observer = new ResizeObserver(() => {
      const width = Math.round(this.chart.clientWidth);
      if (width && width !== this.width && this.data) this.draw();
    });
    this.observer.observe(this.chart);
  }

  destroy() {
    this.observer.disconnect();
  }

  set(overview, range) {
    const rows = (overview.history || []).map((row) => ({ ...row, t: Date.parse(row.t) }));
    this.data = { rows, range, current: overview.rates || {} };
    this.drawTotals();
    this.draw();
    this.drawTable();
  }

  drawTotals() {
    const { current } = this.data;
    clear(this.totals).append(...SERIES.map(([key, name]) =>
      h("div", {}, h("dt", {}, h("i", { class: `k-${key}` }), name), h("dd", {}, perSecond(current[key])))));
  }

  drawTable() {
    const { rows, range } = this.data;
    this.caption.textContent = `Messages per second across the broker over ${range.phrase}`;
    clear(this.tableBody);
    for (const row of [...rows].reverse()) {
      this.tableBody.append(h("tr", {},
        h("th", { scope: "row" }, hourMinute(row.t)),
        SERIES.map(([key]) => h("td", {}, rate(row[key])))));
    }
  }

  draw() {
    const { rows, range } = this.data;
    const width = Math.max(280, Math.round(this.chart.clientWidth) || 800);
    this.width = width;
    if (rows.length < 2) {
      clear(this.chart).append(h("p", { class: "tp-empty" }, "No rate samples yet. The management API keeps them once messages flow."));
      this.readout.textContent = "";
      return;
    }
    const narrow = width < 600;
    const height = narrow ? 140 : 168;
    const m = { top: 12, right: 4, bottom: 24, left: 40 };
    const plotW = width - m.left - m.right;
    const plotH = height - m.top - m.bottom;
    const start = rows[0].t;
    const end = rows[rows.length - 1].t;
    const x = (time) => m.left + ((time - start) / Math.max(1, end - start)) * plotW;
    const top = niceTop(Math.max(...rows.map((row) => Math.max(row.publish, row.deliver, row.ack, row.redeliver))));
    const y = (value) => m.top + plotH - (Math.min(value, top) / top) * plotH;
    const path = (key) => rows.map((row, index) => `${index ? "L" : "M"}${x(row.t).toFixed(1)} ${y(row[key]).toFixed(1)}`).join("");
    const area = (key) => `${path(key)}L${x(end)} ${y(0)}L${x(start)} ${y(0)}Z`;
    const peak = rows.reduce((best, row) => (row.publish > best.publish ? row : best), rows[0]);

    const svg = s("svg", {
      viewBox: `0 0 ${width} ${height}`, width, height, role: "img",
      "aria-label": `Over ${range.phrase}: published peaked at ${perSecond(peak.publish)} around ${hourMinute(peak.t)}. ` +
        `Now ${SERIES.map(([key, name]) => `${name.toLowerCase()} ${perSecond(this.data.current[key])}`).join(", ")}.`
    });
    for (const value of [0, top / 2, top]) {
      const gy = Math.round(y(value)) + 0.5;
      svg.append(
        s("line", { class: value ? "p-grid" : "p-rule", x1: m.left, x2: width - m.right, y1: gy, y2: gy }),
        s("text", { class: "p-axis", x: m.left - 8, y: gy + 4, "text-anchor": "end" }, value ? perSecond(value) : "0"));
    }
    svg.append(
      s("path", { class: "p-ack", d: area("ack") }),
      s("path", { class: "p-ack-edge", d: path("ack") }),
      s("path", { class: "p-redeliver", d: area("redeliver") }),
      s("path", { class: "p-publish", d: path("publish") }),
      s("path", { class: "p-deliver", d: path("deliver") }));

    for (const tick of ticks(start, end, plotW)) {
      const text = hourMinute(tick);
      const tx = x(tick);
      if (tx - text.length * 3.4 < m.left - 6 || tx + text.length * 3.4 > width) continue;
      svg.append(
        s("line", { class: "p-tick", x1: tx, x2: tx, y1: y(0), y2: y(0) + 4 }),
        s("text", { class: "p-axis", x: tx, y: height - 6, "text-anchor": "middle" }, text));
    }

    const cursor = s("line", { class: "p-cursor", x1: 0, x2: 0, y1: m.top, y2: y(0), visibility: "hidden" });
    const hit = s("rect", { class: "p-hit", x: m.left, y: 0, width: plotW, height });
    const show = (event) => {
      const box = svg.getBoundingClientRect();
      const px = ((event.clientX - box.left) / box.width) * width;
      const time = start + ((px - m.left) / plotW) * (end - start);
      const row = rows.reduce((best, candidate) => (Math.abs(candidate.t - time) < Math.abs(best.t - time) ? candidate : best), rows[0]);
      cursor.setAttribute("x1", x(row.t));
      cursor.setAttribute("x2", x(row.t));
      cursor.setAttribute("visibility", "visible");
      clear(this.readout).append(h("b", {}, `${hourMinute(row.t)}: `),
        SERIES.map(([key, name]) => `${name.toLowerCase()} ${perSecond(row[key])}`).join(", "));
    };
    const hide = () => {
      cursor.setAttribute("visibility", "hidden");
      this.readout.textContent = "Point at the chart to read the rates at a moment.";
    };
    hit.addEventListener("pointermove", show);
    hit.addEventListener("pointerdown", show);
    hit.addEventListener("pointerleave", hide);
    svg.append(cursor, hit);
    hide();
    clear(this.chart).append(svg);
  }
}
