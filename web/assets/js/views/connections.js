import { h, refill } from "../dom.js";
import { ago, count, plural } from "../format.js";

const SHOWN = 12;
const SELF = "(web-aggregator)";

const label = (connection) => (connection.client_properties && connection.client_properties.connection_name) || connection.name;

// The broker's client connections, kept quiet below the map.
export class ConnectionTable {
  constructor(host) {
    this.all = false;
    this.note = h("p", { class: "section-note" });
    this.body = h("tbody");
    this.more = h("button", { type: "button", class: "btn btn-quiet btn-small", hidden: true, onclick: () => { this.all = !this.all; this.draw(); } });
    host.append(
      this.note,
      h("table", { class: "rows is-quiet" },
        h("caption", { class: "visually-hidden" }, "Connections"),
        h("thead", {}, h("tr", {},
          h("th", { scope: "col" }, "Connection"),
          h("th", { scope: "col" }, "User"),
          h("th", { scope: "col" }, "Channels"),
          h("th", { scope: "col" }, "State"),
          h("th", { scope: "col" }, "Connected"))),
        this.body),
      h("div", { class: "list-foot" }, this.more));
    this.connections = [];
  }

  set(connections) {
    this.connections = [...connections].sort((a, b) => label(a).localeCompare(label(b)));
    const channels = this.connections.reduce((sum, c) => sum + (c.channels || 0), 0);
    const users = new Set(this.connections.map((c) => c.user));
    this.note.textContent = this.connections.length
      ? `${plural(this.connections.length, "connection")} with ${plural(channels, "channel")} from ${plural(users.size, "user")}.`
      : "";
    this.draw();
  }

  draw() {
    const now = Date.now();
    const list = this.all ? this.connections : this.connections.slice(0, SHOWN);
    this.more.hidden = this.connections.length <= SHOWN;
    this.more.textContent = this.all ? "Show fewer" : `Show all ${count(this.connections.length)}`;
    if (!list.length) {
      refill(this.body, h("tr", {}, h("td", { colspan: 5, class: "empty" }, "No connections reported. They appear once the management API answers.")));
      return;
    }
    refill(this.body, list.map((connection) => {
      const name = label(connection);
      const state = connection.state || "unknown";
      return h("tr", {},
        h("td", {}, name, name.endsWith(SELF) ? h("span", { class: "c-self" }, "this dashboard") : null),
        h("td", { "data-label": "User" }, connection.user || ""),
        h("td", { "data-label": "Channels" }, count(connection.channels)),
        h("td", { "data-label": "State", class: `c-state is-${state}` }, state),
        h("td", { "data-label": "Connected" }, connection.connected_at ? ago(connection.connected_at, now) : ""));
    }));
  }
}
