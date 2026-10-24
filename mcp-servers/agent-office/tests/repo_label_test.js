'use strict';
// Chạy bằng node: node tests/repo_label_test.js. Chạy thật rowState/repoLabelShown cắt từ web/index.html:
// repo không có runner (hoặc runner đã dừng) không dựng nhãn bên trái; mất tín hiệu, chờ bạn, đang làm vẫn hiện.
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
].join('\n') + '\nthis.repoLabelShown = repoLabelShown;';
const ctx = { STATE: { workers: [] } };
vm.createContext(ctx);
vm.runInContext(src, ctx);

const now = Date.now() / 1000;
const tick = (waiting) => ({ at: now - 60, time: '10:00:00', waiting, counts: {}, lanes: {} });
const cases = [
  ['không có runner', { name: 'GeelyEx2' }, false],
  ['runner đã dừng', { name: 'A', runner: { state: 'finished', tick: tick(0) } }, false],
  ['runner đã dừng nhưng chờ bạn', { name: 'A', runner: { state: 'finished', tick: tick(2) } }, true],
  ['mất tín hiệu', { name: 'A', runner: { state: 'stale', tick: tick(0) } }, true],
  ['chờ việc', { name: 'A', runner: { state: 'idle', tick: tick(0) } }, true],
];
for (const [what, repo, want] of cases) assert.strictEqual(ctx.repoLabelShown(repo), want, what);

ctx.STATE.workers = [{ repo: 'B', status: 'working', issue: 7 }];
assert.strictEqual(ctx.repoLabelShown({ name: 'B' }), true, 'có agent đang làm dù không thấy runner');
console.log('repo_label_test: OK');
