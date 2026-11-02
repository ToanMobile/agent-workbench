'use strict';
// node tests/cc_switcher_retry_test.js — #742 review c27d199d, BUG-REV c39f91d4e7 (INSTINCT-002).
// Runs the real page script of web/cc-switcher.html against a minimal fake DOM, fake fetch and fake clock:
//  - the "Thử lại" button (#btnRetry) is disabled with aria-busy="true" in the same tick as the click, and stays so for at least
//    1000 ms even when the request answers sooner (a double tap starts one request, not two);
//  - load() keeps one request in flight: a timer tick or a tab switch while it runs starts no second GET /api/cc-switcher/state.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const html = fs.readFileSync(path.join(__dirname, '..', 'web', 'cc-switcher.html'), 'utf8');
const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
const page = scripts.find((s) => s.includes("'#btnRetry'"));
assert.ok(page, 'page script with #btnRetry not found in cc-switcher.html');

let now = 1_800_000_000_000;
const timers = [];
const clock = {
  setTimeout(fn, ms) { const t = { fn, at: now + Math.max(0, Number(ms) || 0) }; timers.push(t); return t; },
  clearTimeout(t) { const i = timers.indexOf(t); if (i >= 0) timers.splice(i, 1); },
  setInterval() { return {}; },      // the 1 s countdown and the 20 s poll are driven by hand below
  clearInterval() {},
};
async function flush() { for (let i = 0; i < 20; i++) await Promise.resolve(); }
async function advance(ms) {
  const end = now + ms;
  for (;;) {
    timers.sort((a, b) => a.at - b.at);
    const t = timers[0];
    if (!t || t.at > end) break;
    timers.shift(); now = t.at; t.fn(); await flush();
  }
  now = end; await flush();
}

const listeners = {};
function makeEl(tag) {
  const attrs = {};
  const own = {};
  const el = {
    tagName: String(tag || 'div').toUpperCase(), children: [], dataset: {}, style: {}, hidden: false, disabled: false,
    textContent: '', value: '', className: '',
    classList: { add() {}, remove() {}, toggle() {}, contains() { return false; } },
    setAttribute(k, v) { attrs[k] = String(v); if (k === 'disabled') el.disabled = true; if (k === 'hidden') el.hidden = true; },
    getAttribute(k) { return Object.prototype.hasOwnProperty.call(attrs, k) ? attrs[k] : null; },
    removeAttribute(k) { delete attrs[k]; if (k === 'disabled') el.disabled = false; if (k === 'hidden') el.hidden = false; },
    hasAttribute(k) { return Object.prototype.hasOwnProperty.call(attrs, k); },
    addEventListener(type, fn) { (own[type] = own[type] || []).push(fn); },
    appendChild(c) { el.children.push(c); return c; },
    replaceChildren() { el.children = []; },
    querySelector() { return makeEl('div'); },
    querySelectorAll() { return []; },
    closest() { return null; },
    focus() {}, showModal() {}, close() {}, remove() {},
    // a disabled button dispatches no click, as in a browser
    click() { if (el.disabled) return; (own.click || []).forEach((fn) => fn.call(el, { target: el, currentTarget: el, preventDefault() {} })); },
  };
  Object.defineProperty(el, 'innerHTML', { get() { return ''; }, set() { el.children = []; } });
  return el;
}
const byId = {};
const get = (sel) => (byId[sel] = byId[sel] || makeEl('div'));
const documentElement = makeEl('html');
const document = {
  hidden: false, documentElement,
  querySelector: get,
  getElementById: (id) => get('#' + id),
  querySelectorAll: () => [],
  createElement: makeEl,
  createTextNode: (t) => ({ textContent: String(t) }),
  addEventListener(type, fn) { (listeners[type] = listeners[type] || []).push(fn); },
};

const calls = [];
function fetch(url) {
  let settle;
  const p = new Promise((resolve, reject) => { settle = { resolve, reject }; });
  calls.push({ url: String(url), settle });
  return p;
}
const failWith = (c) => c.settle.resolve({ status: 500, ok: false, json: () => Promise.resolve({ ok: false, error: 'boom' }) });

class FakeDate extends Date {
  constructor(...a) { super(...(a.length ? a : [now])); }
  static now() { return now; }
}
const ctx = {
  document, fetch, Date: FakeDate, Intl, Promise, console: { log() {}, warn() {}, error() {} },
  localStorage: { getItem() { return null; }, setItem() {} },
  matchMedia: () => ({ matches: false, addEventListener() {} }),
  CSS: { escape: (s) => String(s) },
  ...clock,
};
ctx.window = ctx;
vm.createContext(ctx);

(async () => {
  vm.runInContext(page, ctx);
  await flush();
  assert.strictEqual(calls.length, 1, 'page start loads the state once');
  failWith(calls[0]); await flush();
  assert.strictEqual(get('#errBanner').hidden, false, 'a failed load shows the error banner with "Thử lại"');

  const retry = get('#btnRetry');
  retry.click();
  assert.strictEqual(retry.disabled, true, 'btnRetry is disabled in the same tick as the click');
  assert.strictEqual(retry.getAttribute('aria-busy'), 'true', 'btnRetry shows aria-busy="true" in the same tick as the click');
  assert.strictEqual(calls.length, 2, 'the click starts one request');
  retry.click(); retry.click();
  assert.strictEqual(calls.length, 2, 'a double tap starts no second request');

  // load() itself keeps one request in flight: the tab-visible handler while the retry request runs
  (listeners.visibilitychange || []).forEach((fn) => fn());
  await flush();
  assert.strictEqual(calls.length, 2, 'load() while a load is in flight starts no second request');

  // the request answers after 200 ms: the button stays locked until 1000 ms after the click
  await advance(200);
  failWith(calls[1]); await flush();
  await advance(300);
  assert.strictEqual(retry.disabled, true, 'still disabled 500 ms after the click (debounce >= 1000 ms)');
  retry.click();
  assert.strictEqual(calls.length, 2, 'a tap 500 ms after the first starts no request');
  await advance(500);
  assert.strictEqual(retry.disabled, false, 'enabled again 1000 ms after the click');
  assert.strictEqual(retry.getAttribute('aria-busy'), null, 'aria-busy removed when the button is enabled again');

  // after the lock, a new tap loads again (the in-flight flag was released)
  retry.click();
  assert.strictEqual(calls.length, 3, 'a later tap starts a new request');
  failWith(calls[2]); await advance(1000);
  (listeners.visibilitychange || []).forEach((fn) => fn());
  await flush();
  assert.strictEqual(calls.length, 4, 'with nothing in flight, the tab-visible handler loads again');
  console.log('cc_switcher_retry_test: OK');
})().catch((e) => { console.error(e && e.stack || e); process.exit(1); });
