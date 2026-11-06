import { api } from "./api.js";
import { clear, h } from "./dom.js";
import { live, onLive, setPoll, setupPolling } from "./live.js";
import { overview } from "./views/overview.js";

const THEME_KEY = "lepus:theme";
const view = document.getElementById("view");

function applyTheme(choice) {
  if (choice === "light" || choice === "dark") document.documentElement.setAttribute("data-theme", choice);
  else document.documentElement.removeAttribute("data-theme");
  for (const button of document.querySelectorAll("[data-theme-choice]")) {
    button.setAttribute("aria-pressed", String(button.dataset.themeChoice === choice));
  }
}

function setupTheme() {
  let choice = "auto";
  try { choice = localStorage.getItem(THEME_KEY) || "auto"; } catch {}
  applyTheme(choice);
  for (const button of document.querySelectorAll("[data-theme-choice]")) {
    button.addEventListener("click", () => {
      const next = button.dataset.themeChoice;
      try {
        if (next === "auto") localStorage.removeItem(THEME_KEY);
        else localStorage.setItem(THEME_KEY, next);
      } catch {}
      applyTheme(next);
    });
  }
}

const rateText = (seconds) => (seconds ? `${seconds} s` : "Paused");

function setupLive() {
  const wrap = document.getElementById("poll");
  const button = document.getElementById("live");
  const menu = document.getElementById("poll-menu");
  const options = document.getElementById("poll-options");
  const text = button.querySelector(".live-text");
  const rate = button.querySelector(".live-rate");

  // Arrow keys move through the radios one by one; only the rate the
  // keyboard settles on (or the menu closes on) is applied.
  let pending = null;
  let commitTimer = null;
  const commit = () => {
    clearTimeout(commitTimer);
    if (pending !== null && pending !== live.seconds) setPoll(pending);
    pending = null;
  };

  clear(options);
  const order = [0, ...live.choices.filter((n) => n > 0)];
  const radios = order.map((seconds) => {
    const input = h("input", { type: "radio", name: "poll", value: String(seconds) });
    input.addEventListener("change", () => {
      pending = seconds;
      clearTimeout(commitTimer);
      commitTimer = setTimeout(commit, 700);
    });
    options.append(h("label", { class: "poll-option" }, input,
      h("span", {}, seconds ? `Every ${seconds} s` : "Paused"),
      seconds === live.fallback ? h("span", { class: "poll-default" }, "default") : null));
    return input;
  });

  const show = () => {
    const on = live.seconds > 0;
    wrap.classList.toggle("is-paused", !on);
    text.textContent = on ? "Live" : "Paused";
    rate.textContent = on ? rateText(live.seconds) : "";
    button.setAttribute("aria-label", on ? `Live ${rateText(live.seconds)}, refresh interval` : "Paused, refresh interval");
    button.title = on ? `Updating every ${live.seconds} seconds` : "Updates paused";
    radios.forEach((input, index) => { input.checked = order[index] === live.seconds; });
  };

  const open = (state) => {
    menu.hidden = !state;
    button.setAttribute("aria-expanded", String(state));
    if (state) (radios.find((input) => input.checked) || radios[0]).focus();
  };
  const close = (refocus) => {
    commit();
    if (menu.hidden) return;
    open(false);
    if (refocus) button.focus();
  };

  button.addEventListener("click", () => open(menu.hidden));
  menu.addEventListener("keydown", (event) => {
    if (event.key === "Escape" || event.key === "Enter") { event.preventDefault(); close(true); }
  });
  menu.addEventListener("click", (event) => { if (event.target.matches("input") && event.detail > 0) close(true); });
  document.addEventListener("keydown", (event) => { if (event.key === "Escape") close(wrap.contains(document.activeElement)); });
  document.addEventListener("pointerdown", (event) => { if (!wrap.contains(event.target)) close(false); });
  wrap.addEventListener("focusout", (event) => { if (event.relatedTarget && !wrap.contains(event.relatedTarget)) close(false); });
  onLive(show);
  show();
}

function setupNav() {
  for (const link of document.querySelectorAll("[data-nav]")) {
    link.addEventListener("click", (event) => {
      const target = document.getElementById(link.dataset.nav);
      if (!target) return;
      event.preventDefault();
      target.scrollIntoView({ block: "start" });
      const heading = target.querySelector("h1, h2") || target;
      heading.setAttribute("tabindex", "-1");
      heading.focus({ preventScroll: true });
    });
  }
}

function setupScrollSpy() {
  const links = [...document.querySelectorAll("[data-nav]")];
  let frame = 0;
  const mark = () => {
    frame = 0;
    const line = Math.min(160, window.innerHeight / 3);
    let current = links[0];
    for (const link of links) {
      const target = document.getElementById(link.dataset.nav);
      if (target && target.getBoundingClientRect().top <= line) current = link;
    }
    if (window.scrollY > 0 && window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2) current = links[links.length - 1];
    for (const link of links) {
      if (link === current) link.setAttribute("aria-current", "location");
      else link.removeAttribute("aria-current");
    }
  };
  const schedule = () => { if (!frame) frame = requestAnimationFrame(mark); };
  window.addEventListener("scroll", schedule, { passive: true });
  window.addEventListener("resize", schedule);
  mark();
}

async function start() {
  setupTheme();
  let meta;
  try {
    meta = await api.meta();
    setupPolling(meta);
    setupLive();
  } catch (error) {
    clear(view).append(h("p", { class: "error" }, error.message));
    return;
  }
  setupNav();
  clear(view);
  overview(view, { meta });
  setupScrollSpy();
}

start();
