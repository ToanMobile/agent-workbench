// #236: Approve finds the approval-request on the issue the PR closes, and a stale message names the head change.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { approveSuperBoardCallback } from '../src/telegram.js';

const OLD = 'ab'.repeat(20);
const NEW = 'cd'.repeat(20);
const ID = '0123456789abcdef';

function approvals(head) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sb-approve-head-'));
  fs.writeFileSync(path.join(dir, `${ID}.json`), JSON.stringify({ repo: 'owner/repo', pr: 164, head, source: 164 }));
  return dir;
}

// Fake `gh`: the PR closes issue 236 and the request is posted on that issue, not on the PR.
function fakeGh(prHead, calls) {
  const request = (head) => `approval-request: {"head":"${head}","pr":164,"repo":"owner/repo","scope":"${'0'.repeat(64)}"}`;
  return async (args) => {
    calls.push(args);
    const flat = args.join(' ');
    if (args[0] === 'pr' && args[1] === 'view') {
      return JSON.stringify({
        headRefOid: prHead,
        body: 'Closes #236',
        closingIssuesReferences: [{ number: 236, repository: { nameWithOwner: 'owner/repo' } }],
      });
    }
    if (flat.includes('issues/164/comments?')) return JSON.stringify([[{ body: 'status comment' }]]);
    if (flat.includes('issues/236/comments?')) return JSON.stringify([[{ author_association: 'OWNER', body: request(prHead) }]]);
    return '';
  };
}

test('request on the linked issue is found and done is commented there', async () => {
  const dir = approvals(NEW);
  const calls = [];
  const posted = [];
  const ghRead = fakeGh(NEW, calls);
  const result = await approveSuperBoardCallback(ID, {
    approvalsDir: dir,
    ghRead,
    gh: async (args) => { posted.push(args); },
  });
  assert.equal(result.showAlert, false, result.toastText);
  assert.match(posted[0].join(' '), /repos\/owner\/repo\/issues\/236\/comments/);
  assert.match(posted[0].join(' '), /body=done/);
  fs.rmSync(dir, { recursive: true, force: true });
});

test('stale message after the head changed names the change and comments nothing', async () => {
  const dir = approvals(OLD);
  const posted = [];
  const result = await approveSuperBoardCallback(ID, {
    approvalsDir: dir,
    ghRead: fakeGh(NEW, []),
    gh: async (args) => { posted.push(args); },
  });
  assert.equal(result.showAlert, true);
  assert.match(result.toastText, /head đã đổi/i);
  assert.match(result.toastText, /tin mới nhất/);
  assert.equal(posted.length, 0);
  fs.rmSync(dir, { recursive: true, force: true });
});

test('current head without a request says the request is not posted yet', async () => {
  const dir = approvals(NEW);
  const posted = [];
  const ghRead = async (args) => {
    if (args[0] === 'pr') return JSON.stringify({ headRefOid: NEW, body: '', closingIssuesReferences: [] });
    return JSON.stringify([[{ body: 'status comment' }]]);
  };
  const result = await approveSuperBoardCallback(ID, { approvalsDir: dir, ghRead, gh: async (a) => { posted.push(a); } });
  assert.equal(result.showAlert, true);
  assert.match(result.toastText, /chưa có approval-request/i);
  assert.equal(posted.length, 0);
  fs.rmSync(dir, { recursive: true, force: true });
});

test('unreadable PR head refuses instead of commenting', async () => {
  const dir = approvals(NEW);
  const posted = [];
  const result = await approveSuperBoardCallback(ID, {
    approvalsDir: dir,
    ghRead: async () => { throw new Error('gh down'); },
    gh: async (a) => { posted.push(a); },
  });
  assert.equal(result.showAlert, true);
  assert.equal(posted.length, 0);
  fs.rmSync(dir, { recursive: true, force: true });
});
