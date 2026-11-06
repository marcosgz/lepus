const numbers = new Intl.NumberFormat();
const timeOfDay = new Intl.DateTimeFormat(undefined, { hour: "2-digit", minute: "2-digit" });

export const count = (value) => numbers.format(Math.round(value || 0));
export const plural = (n, one, many = `${one}s`) => `${count(n)} ${n === 1 ? one : many}`;
export const toTime = (value) => (value ? (typeof value === "number" ? value : Date.parse(value)) : null);
export const hourMinute = (value) => timeOfDay.format(new Date(value));

export function compact(value) {
  const n = Math.round(value || 0);
  if (n < 1000) return String(n);
  const [scaled, unit] = n < 1_000_000 ? [n / 1000, "k"] : [n / 1_000_000, "M"];
  const digits = scaled < 10 ? 1 : 0;
  const rounded = Number(scaled.toFixed(digits));
  if (rounded >= 1000 && unit === "k") return compact(1_000_000);
  return `${rounded}${unit}`;
}

// Messages per second: one decimal below ten so slow queues do not read as 0.
export function rate(value) {
  const n = value || 0;
  if (n === 0) return "0";
  if (n < 0.1) return "<0.1";
  if (n < 10) return String(Number(n.toFixed(1)));
  return compact(n);
}

export const perSecond = (value) => `${rate(value)}/s`;

export function bytes(value) {
  const n = value || 0;
  if (n < 1024 * 1024) return `${Math.round(n / 1024)} KB`;
  if (n < 1024 ** 3) return `${Math.round(n / 1024 / 1024)} MB`;
  return `${(n / 1024 ** 3).toFixed(1)} GB`;
}

export function duration(ms) {
  if (ms === null || ms === undefined || Number.isNaN(ms)) return "";
  if (ms < 1000) return `${Math.round(ms)} ms`;
  const seconds = ms / 1000;
  if (seconds < 10 && seconds % 1) return `${seconds.toFixed(1)} s`;
  if (seconds < 60) return `${Math.round(seconds)} s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) {
    const rest = Math.round(seconds - minutes * 60);
    return rest ? `${minutes} min ${rest} s` : `${minutes} min`;
  }
  const hours = Math.floor(minutes / 60);
  if (hours < 48) {
    const rest = minutes - hours * 60;
    return rest ? `${hours} h ${rest} min` : `${hours} h`;
  }
  return `${Math.round(hours / 24)} days`;
}

export function ago(value, now = Date.now()) {
  const time = toTime(value);
  if (!time) return "";
  const ms = Math.max(0, now - time);
  if (ms < 5_000) return "just now";
  if (ms < 60_000) return `${Math.round(ms / 1000)} s ago`;
  return `${duration(Math.round(ms / 60_000) * 60_000)} ago`;
}
