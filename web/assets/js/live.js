const KEY = "lepus:poll";
const listeners = new Set();

// Polling state shared by every view: `seconds` is 0 when paused. The map
// reads `now()` so tokens freeze while paused instead of creeping on.
export const live = { seconds: 5, choices: [0, 2, 5, 15, 60], fallback: 5, frozenAt: null };

export const isLive = () => live.seconds > 0;
export const pollMs = () => (live.seconds || live.fallback) * 1000;
export const now = () => (isLive() ? Date.now() : live.frozenAt ?? Date.now());

export function setupPolling(me) {
  const choices = (me.poll_intervals || []).filter((n) => Number.isFinite(n) && n >= 0);
  if (choices.length) live.choices = [...new Set(choices)].sort((a, b) => a - b);
  if (!live.choices.includes(0)) live.choices.unshift(0);
  live.fallback = live.choices.includes(me.poll_interval) && me.poll_interval > 0 ? me.poll_interval : live.choices.find((n) => n > 0) || 5;
  let stored = null;
  try { stored = localStorage.getItem(KEY); } catch {}
  const wanted = stored === null ? live.fallback : Number(stored);
  setPoll(live.choices.includes(wanted) ? wanted : live.fallback, { store: false });
}

export function setPoll(seconds, { store = true } = {}) {
  const was = live.seconds;
  live.seconds = seconds;
  if (seconds === 0 && was !== 0) live.frozenAt = Date.now();
  if (seconds > 0) live.frozenAt = null;
  if (store) {
    try { localStorage.setItem(KEY, String(seconds)); } catch {}
  }
  for (const listener of listeners) listener(live);
}

export function onLive(listener) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

// Runs fn now (even while paused, so a view always has data) and then every
// `interval()` ms, measured from the start of each run, while polling is on
// and the tab is visible. Turning polling back on or changing the interval
// runs it again right away, or as soon as a run in progress finishes.
export function every(interval, fn) {
  const ms = typeof interval === "function" ? interval : () => interval;
  let timer = null;
  let stopped = false;
  let busy = false;
  let again = false;
  const tick = async (force = false) => {
    clearTimeout(timer);
    timer = null;
    if (stopped) return;
    if (busy) { again = true; return; }
    busy = true;
    again = false;
    const started = Date.now();
    if (force || (isLive() && !document.hidden)) {
      try { await fn(); } catch (error) { console.warn(error); }
    }
    busy = false;
    if (stopped || !isLive()) return;
    timer = setTimeout(tick, again ? 0 : Math.max(0, ms() - (Date.now() - started)));
  };
  const resume = () => { if (!stopped && isLive() && !document.hidden) tick(); };
  const offLive = onLive(resume);
  document.addEventListener("visibilitychange", resume);
  tick(true);
  return () => {
    stopped = true;
    clearTimeout(timer);
    offLive();
    document.removeEventListener("visibilitychange", resume);
  };
}
