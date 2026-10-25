// Nút Approve chỉ tin approval-request của người có quyền (OWNER/MEMBER/COLLABORATOR, cùng luật approved-head của runner)
// và đúng PR/head của phiếu. Thân PR (`closes #N`) do tác giả PR sửa được, ai cũng comment được trên issue: comment của
// người ngoài không được quyết định `done` của chủ repo rơi vào đâu (rơi lên issue chung thì duyệt hộ PR khác — kiểm bằng
// validate() của super-board-approval.py: request tin cậy của PR B + `done` sau nó trên cùng issue ⇒ PR B được duyệt).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { approveSuperBoardCallback } from '../src/telegram.js';

const HEAD = 'ab'.repeat(20);
const OTHER = 'cd'.repeat(20);
const ID = '0123456789abcdef';
const request = (pr, head) => `approval-request: {"head":"${head}","pr":${pr},"repo":"owner/repo","scope":"${'0'.repeat(64)}"}`;

function approvals() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sb-approve-trust-'));
  // Phiếu đúng như needs_you_notify của merge gate ghi: source = PR.
  fs.writeFileSync(path.join(dir, `${ID}.json`), JSON.stringify({ repo: 'owner/repo', pr: 164, head: HEAD, source: 164 }));
  return dir;
}

// gh giả: thân PR đóng #9 (issue chung với PR #20 khác); comments[n] = comment của issue/PR n.
function fakeGh(comments, body = 'Closes #9') {
  return async (args) => {
    if (args[0] === 'pr' && args[1] === 'view') {
      return JSON.stringify({ headRefOid: HEAD, body, closingIssuesReferences: [] });
    }
    const m = args.join(' ').match(/issues\/(\d+)\/comments\?/);
    return JSON.stringify([comments[m ? Number(m[1]) : 0] || []]);
  };
}

async function press(comments, body) {
  const dir = approvals();
  const posted = [];
  try {
    const result = await approveSuperBoardCallback(ID, {
      approvalsDir: dir,
      ghRead: fakeGh(comments, body),
      gh: async (args) => { posted.push(args.join(' ')); },
    });
    return { result, posted };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test('request đúng head nhưng của người ngoài (NONE) trên issue thân PR đóng: không ghi done', async () => {
  const { result, posted } = await press({
    9: [{ author_association: 'NONE', body: request(164, HEAD) }],
  });
  assert.deepEqual(posted, []);
  assert.equal(result.showAlert, true);
});

test('issue chung có request tin cậy của PR khác: request giả của CONTRIBUTOR không kéo done sang đó', async () => {
  const { posted } = await press({
    9: [
      { author_association: 'OWNER', body: request(20, OTHER) },
      { author_association: 'CONTRIBUTOR', body: request(164, HEAD) },
    ],
  });
  assert.deepEqual(posted, []);
});

test('request giả đặt trên PR (đọc trước) không cướp chỗ request tin cậy trên issue: done ghi lên issue', async () => {
  const { result, posted } = await press({
    164: [{ author_association: 'FIRST_TIME_CONTRIBUTOR', body: request(164, HEAD) }],
    9: [{ author_association: 'MEMBER', body: request(164, HEAD) }],
  });
  assert.equal(result.showAlert, false, result.toastText);
  assert.equal(posted.length, 1);
  assert.match(posted[0], /repos\/owner\/repo\/issues\/9\/comments/);
  assert.match(posted[0], /body=done/);
});

test('comment tin cậy chỉ nhắc head nhưng request là của PR khác: không ghi done', async () => {
  const { posted } = await press({
    9: [{ author_association: 'OWNER', body: request(999, HEAD) }],
  });
  assert.deepEqual(posted, []);
});

test('COLLABORATOR đăng request đúng PR và head: done ghi đúng nguồn', async () => {
  const { result, posted } = await press({
    9: [{ author_association: 'COLLABORATOR', body: request(164, HEAD) }],
  });
  assert.equal(result.showAlert, false, result.toastText);
  assert.equal(posted.length, 1);
  assert.match(posted[0], /issues\/9\/comments/);
});

test('comment của các nguồn được đọc song song, không cộng dồn timeout 15 s từng lời gọi gh', async () => {
  const dir = approvals();
  let inFlight = 0;
  let maxInFlight = 0;
  const ghRead = async (args) => {
    if (args[0] === 'pr') return JSON.stringify({ headRefOid: HEAD, body: 'Closes #9 fixes #10', closingIssuesReferences: [] });
    inFlight += 1;
    maxInFlight = Math.max(maxInFlight, inFlight);
    await new Promise((resolve) => setTimeout(resolve, 20));
    inFlight -= 1;
    return JSON.stringify([args.join(' ').includes('issues/10/comments?')
      ? [{ author_association: 'OWNER', body: request(164, HEAD) }] : []]);
  };
  const posted = [];
  try {
    await approveSuperBoardCallback(ID, { approvalsDir: dir, ghRead, gh: async (a) => { posted.push(a.join(' ')); } });
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  assert.equal(maxInFlight, 3, 'ba nguồn (PR 164, #9, #10) phải đọc cùng lúc');
  assert.match(posted[0] || '', /issues\/10\/comments/);
});

test('đường readComments (hook test) cũng lọc người ngoài', async () => {
  const dir = approvals();
  const posted = [];
  try {
    await approveSuperBoardCallback(ID, {
      approvalsDir: dir,
      ghRead: fakeGh({}, ''),
      readComments: async () => [{ source: 34, author_association: 'NONE', body: request(164, HEAD) }],
      gh: async (args) => { posted.push(args.join(' ')); },
    });
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  assert.deepEqual(posted, []);
});
