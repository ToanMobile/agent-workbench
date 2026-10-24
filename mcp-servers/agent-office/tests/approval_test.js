'use strict';
// Chạy bằng node: node tests/approval_test.js. Chạy thật needsApproval/approveState cắt từ web/index.html:
// chỉ thẻ Blocked + nhãn needs-you còn mở vào khung duyệt; nút Duyệt chỉ bật khi đã đọc được bước,
// đã tick "đã chạy xong" nếu thẻ có lệnh needs-you, chưa duyệt và không đang gửi.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const html = fs.readFileSync(path.join(__dirname, '..', 'web', 'index.html'), 'utf8');
const grab = (re, what) => { const m = html.match(re); assert.ok(m, 'không tìm thấy ' + what + ' trong index.html'); return m[0]; };
const src = [
  grab(/const KIND_RULES = [\s\S]*?\];\n/, 'KIND_RULES'),
  grab(/const kindOf = .*\n/, 'kindOf'),
  grab(/function needsApproval\(it\) \{[\s\S]*?\n\}\n/, 'needsApproval'),
  grab(/function approveState\(it, ui\) \{[\s\S]*?\n\}\n/, 'approveState'),
  grab(/function pendingApprovals\(items\) \{[\s\S]*?\n\}\n/, 'pendingApprovals'),
].join('\n') + '\nthis.needsApproval = needsApproval; this.approveState = approveState; this.pendingApprovals = pendingApprovals;';
const ctx = { STATE: { demo: false, columns: [{ name: 'Blocked', kind: 'blocked' }, { name: 'Ready', kind: 'ready' }] } };
vm.createContext(ctx);
vm.runInContext(src, ctx);

const card = (o) => Object.assign({ status: 'Blocked', state: 'OPEN', type: 'Issue', labels: [{ name: 'needs-you' }], approval: { steps: [], approved: false } }, o);
assert.strictEqual(ctx.needsApproval(card({})), true, 'thẻ 🙋');
assert.strictEqual(ctx.needsApproval(card({ labels: [] })), false, 'không có nhãn needs-you');
assert.strictEqual(ctx.needsApproval(card({ status: 'Ready' })), false, 'không ở Blocked');
assert.strictEqual(ctx.needsApproval(card({ state: 'CLOSED' })), false, 'đã đóng');
assert.strictEqual(ctx.needsApproval(card({ type: 'DraftIssue' })), false, 'bản nháp không nhận comment');

const st = (it, ui) => ctx.approveState(it, ui || {});
assert.strictEqual(st(card({})).canApprove, true, 'không có lệnh: duyệt được ngay');
const withStep = card({ approval: { steps: ['npx prisma migrate deploy'], approved: false } });
assert.strictEqual(st(withStep).canApprove, false, 'có lệnh chưa tick');
assert.strictEqual(st(withStep, { ticked: true }).canApprove, true, 'có lệnh đã tick');
assert.strictEqual(st(withStep, { ticked: true, busy: true }).canApprove, false, 'đang gửi');
assert.strictEqual(st(withStep, { ticked: true, busy: true }).canReject, false, 'đang gửi: từ chối cũng khoá');
assert.strictEqual(st(card({ approval: null })).canApprove, false, 'chưa đọc được bước: không duyệt');
assert.strictEqual(st(card({ approval: null })).canReject, true, 'chưa đọc được bước: vẫn từ chối được');
const done = st(card({ approval: { steps: [], approved: true } }));
assert.strictEqual(done.canApprove, false, 'đã duyệt');
assert.strictEqual(done.approved, true);
// băng nhắc chỉ đếm thẻ còn chờ: đã duyệt (chờ wave sau) hay không phải 🙋 thì không nhắc
const pend = ctx.pendingApprovals([card({}), card({ approval: { steps: [], approved: true } }), card({ labels: [] }), card({ approval: null })]);
assert.strictEqual(pend.length, 2, 'thẻ chờ duyệt (kể cả chưa đọc được bước)');
console.log('approval_test: OK');
