// audit 31/10 — BUG-REV-agy-audit-head-failclosed: pm-review-audit passed an audit without auditedHead and ignored edits made
// to the working tree during the audit.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { judgeAudit, treeHash, pollDelay } from '../bin/pm-review-audit.js';
import { tmpDir, cleanup } from './helpers.js';

const H = 'b'.repeat(40);
test('judgeAudit: missing or different auditedHead is an error, never a vote', () => {
  assert.equal(judgeAudit({ verdict: 'pass' }, { head: H, tree0: 't', tree1: 't' }).status, 'error');
  assert.equal(judgeAudit({ verdict: 'pass', auditedHead: 'c'.repeat(40) }, { head: H, tree0: 't', tree1: 't' }).status, 'error');
});
test('judgeAudit: a working tree changed during the audit is an error; same head + tree is ok and carries the model', () => {
  assert.equal(judgeAudit({ verdict: 'pass', auditedHead: H }, { head: H, tree0: 't', tree1: 'u' }).status, 'error');
  const ok = judgeAudit({ verdict: 'pass', auditedHead: H, model: 'gemini-3.5-pro' }, { head: H, tree0: 't', tree1: 't' });
  assert.deepEqual([ok.status, ok.verdict, ok.model, ok.worktree_hash], ['ok', 'pass', 'gemini-3.5-pro', 't']);
});
test('treeHash: changes with an uncommitted edit and with an untracked file', () => {
  const dir = tmpDir('agpm-tree-');
  try {
    const g = (...a) => execFileSync('git', ['-C', dir, ...a]);
    g('init', '-q'); fs.writeFileSync(path.join(dir, 'a.txt'), '1'); g('add', '-A');
    g('-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'i');
    const h0 = treeHash(dir);
    fs.writeFileSync(path.join(dir, 'a.txt'), '2');
    const h1 = treeHash(dir);
    fs.writeFileSync(path.join(dir, 'new.txt'), 'x');
    const h2 = treeHash(dir);
    assert.notEqual(h0, h1); assert.notEqual(h1, h2);
  } finally { cleanup(dir); }
});

test('BUG-REV-agy-audit-poll: result poll is 0.5 s early, 1 s later, never the old flat 5 s; PM_AUDIT_POLL_MS overrides', () => {
  const saved = process.env.PM_AUDIT_POLL_MS;
  delete process.env.PM_AUDIT_POLL_MS;
  try {
    assert.equal(pollDelay(0), 500);
    assert.equal(pollDelay(119000), 500);
    assert.equal(pollDelay(600000), 1000);
    process.env.PM_AUDIT_POLL_MS = '50';
    assert.equal(pollDelay(600000), 50);
  } finally {
    if (saved === undefined) delete process.env.PM_AUDIT_POLL_MS; else process.env.PM_AUDIT_POLL_MS = saved;
  }
});
