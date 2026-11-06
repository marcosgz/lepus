const SVG_NS = "http://www.w3.org/2000/svg";

function apply(el, attrs) {
  for (const [key, value] of Object.entries(attrs || {})) {
    if (value === null || value === undefined || value === false) continue;
    if (key === "text") el.textContent = value;
    else if (key.startsWith("on") && typeof value === "function") el.addEventListener(key.slice(2), value);
    else el.setAttribute(key, value === true ? "" : String(value));
  }
}

function append(el, children) {
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    el.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return el;
}

export function h(tag, attrs, ...children) {
  const el = document.createElement(tag);
  apply(el, attrs);
  return append(el, children);
}

export function s(tag, attrs, ...children) {
  const el = document.createElementNS(SVG_NS, tag);
  apply(el, attrs);
  return append(el, children);
}

export function clear(el) {
  while (el.firstChild) el.firstChild.remove();
  return el;
}

const FOCUSABLE = "a[href], button, input, select, summary, [tabindex]";
export const focusKey = (el) => el.dataset.focusKey || el.getAttribute("href") || `${el.tagName}|${el.textContent}`;

// Replaces el's children for a poll without disturbing assistive technology:
// unchanged content is left alone, and focus inside el moves to the matching
// control of the new content (the same data-focus-key, link target, or tag
// and text).
export function refill(el, ...children) {
  const next = append(document.createDocumentFragment(), children);
  const same = next.childNodes.length === el.childNodes.length &&
    [...next.childNodes].every((node, index) => node.isEqualNode(el.childNodes[index]));
  if (same) return el;
  const active = document.activeElement;
  const key = active && active !== el && el.contains(active) ? focusKey(active) : null;
  clear(el).append(next);
  if (key) [...el.querySelectorAll(FOCUSABLE)].find((node) => focusKey(node) === key)?.focus({ preventScroll: true });
  return el;
}

export const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

function copyAttributes(from, to) {
  for (const name of to.getAttributeNames()) if (!from.hasAttribute(name)) to.removeAttribute(name);
  for (const name of from.getAttributeNames()) {
    const value = from.getAttribute(name);
    if (to.getAttribute(name) !== value) to.setAttribute(name, value);
  }
}

function pathTo(root, node) {
  const path = [];
  for (let at = node; at && at !== root; at = at.parentNode) path.unshift(at);
  return path;
}

// Moves the children of a freshly drawn root into root, keeping keep (a node
// inside root) and its ancestors as the very nodes standing for match and its
// ancestors in the new drawing, so focus and a screen reader's place survive.
// Returns false, changing nothing, when the two trees do not line up.
export function graft(root, fresh, keep, match) {
  const old = [root, ...pathTo(root, keep)];
  const next = [fresh, ...pathTo(fresh, match)];
  if (old.length !== next.length || old.some((node, index) => node.nodeName !== next[index].nodeName)) return false;
  old.forEach((node, index) => {
    const kept = old[index + 1];
    const counterpart = next[index + 1];
    if (index) copyAttributes(next[index], node);
    for (const child of [...node.childNodes]) if (child !== kept) child.remove();
    if (!kept) {
      node.append(...next[index].childNodes);
      return;
    }
    const children = [...next[index].childNodes];
    const at = children.indexOf(counterpart);
    kept.before(...children.slice(0, at));
    kept.after(...children.slice(at + 1));
  });
  return true;
}
