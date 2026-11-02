'use strict';
// node tests/frame_pacing_test.js — nhịp vẽ 3D (frameDue cắt từ web/index.html) và trần mật độ điểm ảnh.
// BUG-REV-AO-PERF-1: xưởng vẽ 60 khung/giây ở DPR 2 kể cả khi đứng yên / giảm chuyển động (~45% CPU renderer + ~44% GPU lúc rảnh).
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const html = fs.readFileSync(path.join(__dirname, '..', 'web', 'index.html'), 'utf8');
const m = html.match(/const AMBIENT_MS = [^\n]*\nfunction frameDue[^\n]*\n/);
assert.ok(m, 'không tìm thấy AMBIENT_MS / frameDue trong index.html');
const ctx = {};
vm.createContext(ctx);
vm.runInContext(m[0] + '\nthis.frameDue = frameDue; this.AMBIENT_MS = AMBIENT_MS; this.STILL_MS = STILL_MS;', ctx);
const { frameDue } = ctx;

// có chuyển động: vẽ mọi khung
assert.strictEqual(frameDue(1000, 999, true, false), true);
assert.strictEqual(frameDue(1000, 999, true, true), true);
// cảnh đứng yên, có hoạt cảnh: ~20 khung/giây (rAF 60 Hz -> vẽ cách hai khung)
let n = 0, last = -Infinity;
for (let i = 0; i < 600; i++) { const now = i * (1000 / 60); if (frameDue(now, last, false, false)) { n++; last = now; } }
assert.ok(n >= 190 && n <= 210, 'đứng yên phải vẽ ~20 khung/giây, thấy ' + n / 10);
// giảm chuyển động / dạng bảng che cảnh, đứng yên: 1 khung/giây
n = 0; last = -Infinity;
for (let i = 0; i < 600; i++) { const now = i * (1000 / 60); if (frameDue(now, last, false, true)) { n++; last = now; } }
assert.ok(n >= 9 && n <= 11, 'giảm chuyển động đứng yên phải vẽ ~1 khung/giây, thấy ' + n / 10);
// khung đầu tiên luôn vẽ
assert.strictEqual(frameDue(0, -Infinity, false, true), true);

// vòng frame dùng frameDue, và "chuột vừa đổi" chỉ tính khi có chuột trên canvas (hoverDirty bật sẵn mỗi lần dựng cảnh, không có
// chuột thì không bao giờ tắt: nếu tính thẳng thì cảnh không bao giờ hạ nhịp)
const frame = html.match(/function frame\(now\) \{[\s\S]*?\n\}\n/);
assert.ok(frame, 'không tìm thấy frame()');
assert.match(frame[0], /if \(!frameDue\(now, lastRender, busy, reduceMotion\.matches \|\| boardOpen\)\) return;/);
// bóng đổ không vẽ lại mỗi khung
assert.match(html, /renderer\.shadowMap\.autoUpdate = false;/);
assert.match(frame[0], /renderer\.shadowMap\.needsUpdate = true;/);
assert.match(frame[0], /\(hoverDirty && !!hoverEvt\)/);
assert.doesNotMatch(frame[0], /\|\| hoverDirty \|\|/);
// trần DPR
const dpr = html.match(/const MAX_DPR = ([\d.]+);/);
assert.ok(dpr && +dpr[1] <= 1.5, 'MAX_DPR phải <= 1.5');
assert.match(html, /renderer\.setPixelRatio\(Math\.min\(window\.devicePixelRatio \|\| 1, MAX_DPR\)\)/);
assert.doesNotMatch(html, /setPixelRatio\(Math\.min\(window\.devicePixelRatio \|\| 1, 2\)\)/);
// renderDirty khai báo trước mọi chỗ dùng (resize() chạy ngay lúc nạp trang: let khai báo sau sẽ ném ReferenceError)
assert.ok(html.indexOf('let renderDirty') < html.indexOf('function resize()'), 'let renderDirty phải nằm trước resize()');
console.log('frame_pacing_test OK');
