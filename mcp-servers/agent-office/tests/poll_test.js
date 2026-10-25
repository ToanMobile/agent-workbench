'use strict';
// node tests/poll_test.js — chạy thật poll() cắt từ web/index.html: tab hiện lại khi một poll đang chạy thì không sinh vòng poll thứ hai.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const html = fs.readFileSync(path.join(__dirname, '..', 'web', 'index.html'), 'utf8');
const m = html.match(/let pollTimer[\s\S]*?\n\}\n/);
assert.ok(m, 'không tìm thấy poll trong index.html');

const timers = new Map(); let nextId = 1; let fetches = 0; const releases = [];
const el = { hidden: false, textContent: '', dataset: {} };
const ctx = {
  document: { hidden: true, addEventListener: (ev, fn) => { if (ev === 'visibilitychange') ctx.onVisible = fn; } },
  setTimeout: (fn) => { const id = nextId++; timers.set(id, fn); return id; },
  clearTimeout: (id) => { timers.delete(id); },
  fetch: () => { fetches++; return new Promise((r) => releases.push(() => r({ ok: true, status: 200, json: async () => ({ version: 1 }) }))); },
  apiHeaders: () => ({}), $: () => el, console, renderTop() {}, apply() {}, renderNotices() {}, dismissed: new Set(),
  OFFLINE_NOTICE: 'x', STATE: {}, VERSION: 1, LAST_S: null,
};
vm.createContext(ctx);
vm.runInContext(m[0] + '\nthis.poll = poll;', ctx);

(async () => {
  const first = ctx.poll();                 // vòng poll đang chạy (fetch chưa trả)
  ctx.document.hidden = false; ctx.onVisible(); // tab hiện lại giữa chừng
  assert.strictEqual(fetches, 1, 'tab hiện lại khi poll đang chạy không được bắn fetch thứ hai');
  releases.forEach((r) => r());
  await first;
  assert.strictEqual(timers.size, 1, 'đúng một timer poll kế tiếp, có ' + timers.size);
  // poll xong rồi thì tab hiện lại vẫn poll ngay
  ctx.onVisible(); assert.strictEqual(fetches, 2, 'poll rảnh phải chạy khi tab hiện lại');
  releases.forEach((r) => r());
  console.log('poll_test OK');
})().catch((e) => { console.error(e); process.exit(1); });
