// Nút Approve ghi `done` đúng như validate() của super-board-approval.py sẽ đọc nó: block tin cậy MỚI NHẤT (`approval-request:`
// hoặc `Reason tag: …🙋`) trên mọi nguồn của PR, người đăng có quyền write/maintain/admin (collaborators/{login}/permission),
// request chưa bị sửa, đúng repo/PR/head của phiếu, PR còn mở. Lệch một điều: `done` của chủ repo duyệt hộ PR khác (probe:
// #9 chung, request cho 164 rồi cho 20, `done` lên #9 ⇒ PR 20 approved=True, PR 164 False) hoặc rơi chỗ gate không đọc.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { approveSuperBoardCallback } from '../src/telegram.js';

const HEAD = 'ab'.repeat(20);
const OTHER = 'cd'.repeat(20);
const SCOPE = '0'.repeat(64);
const ID = '0123456789abcdef';
// Dạng request như approval.py --request in ra (repo chữ thường, khoá sắp xếp).
const request = (pr, head, scope = SCOPE) => `approval-request: {"head":"${head}","pr":${pr},"repo":"owner/repo","scope":"${scope}"}`;
const PERMISSION = { owner: 'admin', writer: 'write', maint: 'maintain', reader: 'read', outsider: 'none' };
const ASSOCIATION = { owner: 'OWNER', writer: 'COLLABORATOR', maint: 'MEMBER', reader: 'MEMBER', outsider: 'NONE' };

let nextId = 1;
// Comment REST thật: id, user{login,type}, author_association, created_at/updated_at (sửa = updated_at khác).
function comment(login, body, minute, edited = false) {
  const at = `2026-10-25T10:${String(minute).padStart(2, '0')}:00Z`;
  return {
    id: nextId++, user: { login, type: 'User' }, author_association: ASSOCIATION[login], body,
    created_at: at, updated_at: edited ? '2026-10-25T11:00:00Z' : at,
  };
}

function approvals(source = 164) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sb-approve-trust-'));
  // Phiếu đúng như needs_you_notify của merge gate ghi (super-board-notify.py): repo giữ hoa/thường, source = PR.
  fs.writeFileSync(path.join(dir, `${ID}.json`), JSON.stringify({ repo: 'Owner/Repo', pr: 164, head: HEAD, source }));
  return dir;
}

// gh giả: thân PR đóng #9 (issue chung với PR #20); comments[n] = comment của issue/PR n.
function fakeGh(comments, { body = 'Closes #9', state = 'OPEN', onComments } = {}) {
  return async (args) => {
    if (args[0] === 'pr' && args[1] === 'view') {
      return JSON.stringify({ headRefOid: HEAD, state, body, closingIssuesReferences: [] });
    }
    const flat = args.join(' ');
    const perm = flat.match(/collaborators\/([^/]+)\/permission/);
    if (perm) return JSON.stringify({ permission: PERMISSION[perm[1]] || 'none' });
    const m = flat.match(/issues\/(\d+)\/comments\?/);
    if (onComments) await onComments();
    return JSON.stringify([comments[m ? Number(m[1]) : 0] || []]);
  };
}

async function press(comments, ghOpts, source) {
  const dir = approvals(source);
  const posted = [];
  try {
    const result = await approveSuperBoardCallback(ID, {
      approvalsDir: dir,
      ghRead: fakeGh(comments, ghOpts),
      gh: async (args) => { posted.push(args.join(' ')); },
    });
    return { result, posted };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test('P1: #9 chung có request cho 164 rồi cho 20 — bấm Approve 164 không ghi done (sẽ duyệt nhầm PR 20)', async () => {
  const { result, posted } = await press({
    9: [comment('owner', request(164, HEAD), 0), comment('owner', request(20, OTHER), 1)],
  });
  assert.deepEqual(posted, []);
  assert.equal(result.showAlert, true);
});

test('block 🙋 tin cậy mới hơn request (không kèm request) thay request cũ: không ghi done', async () => {
  const { posted } = await press({
    9: [comment('owner', request(164, HEAD), 0), comment('writer', 'Reason tag: 🙋 needs you · Owner: Eric\nblocked-by: -', 2)],
  });
  assert.deepEqual(posted, []);
});

test('PR đã đóng/merge: không ghi done dù request hợp lệ', async () => {
  const { result, posted } = await press({ 9: [comment('owner', request(164, HEAD), 0)] }, { state: 'MERGED' });
  assert.deepEqual(posted, []);
  assert.equal(result.showAlert, true);
});

test('MEMBER chỉ có quyền đọc (permission read) đăng request: không ghi done', async () => {
  const { posted } = await press({ 9: [comment('reader', request(164, HEAD), 0)] });
  assert.deepEqual(posted, []);
});

test('request đã bị sửa (updated_at khác created_at): không ghi done', async () => {
  const { posted } = await press({ 9: [comment('owner', request(164, HEAD), 0, true)] });
  assert.deepEqual(posted, []);
});

test('request thiếu scope 64 hex: không ghi done', async () => {
  const { posted } = await press({ 9: [comment('owner', request(164, HEAD, 'abc'), 0)] });
  assert.deepEqual(posted, []);
});

test('hai block tin cậy cùng giây (mơ hồ): không ghi done', async () => {
  const { posted } = await press({
    164: [comment('owner', request(164, HEAD), 3)],
    9: [comment('writer', request(164, HEAD), 3)],
  });
  assert.deepEqual(posted, []);
});

test('request của người ngoài (permission none) trên issue thân PR đóng: không ghi done', async () => {
  const { posted } = await press({ 9: [comment('outsider', request(164, HEAD), 0)] });
  assert.deepEqual(posted, []);
});

test('request giả mới hơn của người ngoài không che request tin cậy: done ghi lên nguồn của request tin cậy', async () => {
  const { result, posted } = await press({
    164: [comment('outsider', request(20, OTHER), 5)],
    9: [comment('maint', request(164, HEAD), 1)],
  });
  assert.equal(result.showAlert, false, result.toastText);
  assert.equal(posted.length, 1);
  assert.match(posted[0], /repos\/Owner\/Repo\/issues\/9\/comments/);
  assert.match(posted[0], /body=done/);
});

test('request tin cậy mới nhất đúng PR/head (write): done ghi đúng nguồn', async () => {
  const { result, posted } = await press({
    9: [comment('owner', request(20, OTHER), 0), comment('writer', request(164, HEAD), 4)],
  });
  assert.equal(result.showAlert, false, result.toastText);
  assert.equal(posted.length, 1);
  assert.match(posted[0], /issues\/9\/comments/);
});

test('F1: request sau U+2028 (re.M của Python không coi là block) không được thành block mới nhất', async () => {
  // Gate: block mới nhất là request cho 20 ⇒ `done` lên #9 duyệt PR 20. Nút phải thấy đúng như vậy và không ghi done.
  const { posted } = await press({
    9: [comment('owner', request(20, OTHER), 0), comment('owner', `x  ${request(164, HEAD)}`, 2)],
  });
  assert.deepEqual(posted, []);
});

test('nguồn như gate: `Closes Owner/Repo#9` (cùng repo, khác hoa/thường) được đọc, done ghi lên #9', async () => {
  const { result, posted } = await press({ 9: [comment('owner', request(164, HEAD), 0)] }, { body: 'Closes Owner/Repo#9' });
  assert.equal(result.showAlert, false, result.toastText);
  assert.match(posted[0] || '', /issues\/9\/comments/);
});

test('nguồn như gate: `Closes other/repo#9` (repo khác) không phải nguồn', async () => {
  const { posted } = await press({ 9: [comment('owner', request(164, HEAD), 0)] }, { body: 'Closes other/repo#9' });
  assert.deepEqual(posted, []);
});

test('nguồn như gate: record.source khác PR và không liên kết thì không đọc, không ghi done lên đó', async () => {
  const { posted } = await press({ 77: [comment('owner', request(164, HEAD), 0)] }, { body: '' }, 77);
  assert.deepEqual(posted, []);
});

test('comment của các nguồn được đọc song song, không cộng dồn timeout 15 s từng lời gọi gh', async () => {
  let inFlight = 0;
  let maxInFlight = 0;
  const { posted } = await press({ 10: [comment('owner', request(164, HEAD), 0)] }, {
    body: 'Closes #9 fixes #10',
    onComments: async () => {
      inFlight += 1;
      maxInFlight = Math.max(maxInFlight, inFlight);
      await new Promise((resolve) => setTimeout(resolve, 20));
      inFlight -= 1;
    },
  });
  assert.equal(maxInFlight, 3, 'ba nguồn (PR 164, #9, #10) phải đọc cùng lúc');
  assert.match(posted[0] || '', /issues\/10\/comments/);
});

test('đường readComments (hook test) cũng lọc theo quyền', async () => {
  const dir = approvals();
  const posted = [];
  try {
    await approveSuperBoardCallback(ID, {
      approvalsDir: dir,
      ghRead: fakeGh({}, { body: '' }),
      readComments: async () => [{ ...comment('outsider', request(164, HEAD), 0), source: 34 }],
      gh: async (args) => { posted.push(args.join(' ')); },
    });
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  assert.deepEqual(posted, []);
});
