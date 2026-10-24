'use strict';
// Chạy bằng node: node tests/repo_label_test.js. Chạy thật rowState/repoLabelShown/dismissNotice cắt từ web/index.html:
// repo không có runner (hoặc runner đã dừng) không dựng nhãn bên trái; mất tín hiệu, chờ bạn, đang làm vẫn hiện.
// Ẩn thông báo: chỉ loại info được nhớ qua lần tải lại.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const html = fs.readFileSync(path.join(__dirname, '..', 'web', 'index.html'), 'utf8');
const grab = (re, what) => { const m = html.match(re); assert.ok(m, 'không tìm thấy ' + what + ' trong index.html'); return m[0]; };
const src = [
  grab(/function ago\(ts\) \{[\s\S]*?\n\}\n/, 'ago'),
  grab(/function rowState\(repo\) \{[\s\S]*?\n\}\n/, 'rowState'),
  grab(/function repoLabelShown\(repo\) \{[\s\S]*?\n\}\n/, 'repoLabelShown'),
  grab(/const savedNotices = .*\n/, 'savedNotices'),
  grab(/const dismissed = .*\n/, 'dismissed'),
  grab(/function dismissNotice\(n\) \{[\s\S]*?\n\}\n/, 'dismissNotice'),
  grab(/const OFFLINE_NOTICE = .*\n/, 'OFFLINE_NOTICE'),
].join('\n') + '\nthis.repoLabelShown = repoLabelShown; this.dismissNotice = dismissNotice; this.dismissed = dismissed; this.OFFLINE_NOTICE = OFFLINE_NOTICE;';
const store = new Map();
const ctx = { STATE: { workers: [] }, localStorage: { getItem: (k) => store.get(k) || null, setItem: (k, v) => store.set(k, v) } };
vm.createContext(ctx);
vm.runInContext(src, ctx);

// Mọi script inline phải đúng cú pháp (regex bên dưới không bắt được một dấu } bị comment nuốt)
for (const m of html.matchAll(/<script>([\s\S]*?)<\/script>/g)) new vm.Script(m[1], { filename: 'index.html inline script' });
// Key mới: bản trước lưu cả lỗi/cảnh báo vào 'ao-dismissed', không đọc lại key đó
assert.ok(!/'ao-dismissed'/.test(html), "không đọc/ghi key cũ 'ao-dismissed'");

// Nhãn repo: chỗ dựng nhãn phải đi qua repoLabelShown (bỏ guard thì test này đỏ)
assert.ok(/if \(repoLabelShown\(repo\)\) addLabel\('lbl-repo'/.test(html), "addLabel('lbl-repo') phải nằm sau if (repoLabelShown(repo))");
const now = Date.now() / 1000;
const tick = (waiting) => ({ at: now - 60, time: '10:00:00', waiting, counts: {}, lanes: {} });
const cases = [
  ['không có runner', { name: 'GeelyEx2' }, false],
  ['runner đã dừng', { name: 'A', runner: { state: 'finished', tick: tick(0) } }, false],
  ['runner đã dừng nhưng chờ bạn', { name: 'A', runner: { state: 'finished', tick: tick(2) } }, true],
  ['mất tín hiệu', { name: 'A', runner: { state: 'stale', tick: tick(0) } }, true],
  ['chờ việc', { name: 'A', runner: { state: 'idle', tick: tick(0) } }, true],
  ['runner đang chạy', { name: 'A', runner: { state: 'running', tick: tick(0) } }, true],
];
for (const [what, repo, want] of cases) assert.strictEqual(ctx.repoLabelShown(repo), want, what);
ctx.STATE.workers = [{ repo: 'B', status: 'working', issue: 7 }];
assert.strictEqual(ctx.repoLabelShown({ name: 'B' }), true, 'có agent đang làm dù không thấy runner');

// Ẩn cảnh báo rồi ẩn info: chỉ info được lưu; cả ba ẩn trong phiên này
ctx.dismissNotice({ level: 'warn', text: 'W' });
ctx.dismissNotice({ level: 'info', text: 'I' });
ctx.dismissNotice({ level: 'error', text: ctx.OFFLINE_NOTICE, transient: true });
assert.deepStrictEqual(JSON.parse(store.get('ao-dismissed-info')), ['I'], 'chỉ thông báo info được lưu');
for (const t of ['W', 'I', ctx.OFFLINE_NOTICE]) assert.ok(ctx.dismissed.has(t), t + ' phải ẩn trong phiên này');
// Có lại kết nối thì bỏ "đã ẩn" của thông báo mất kết nối, để lần mất sau vẫn báo
assert.ok(/dataset\.offline = '0'; dismissed\.delete\(OFFLINE_NOTICE\);/.test(html), 'poll() phải bỏ OFFLINE_NOTICE khỏi dismissed khi có lại kết nối');
assert.ok(/text: OFFLINE_NOTICE, transient: true/.test(html), 'renderNotices dùng OFFLINE_NOTICE');
console.log('repo_label_test: OK');
