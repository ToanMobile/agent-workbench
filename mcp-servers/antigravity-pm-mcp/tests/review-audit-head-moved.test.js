// card #756 F8 — pm-review-audit: (1) a commit made during the audit left both trees clean, tree1 === tree0, and an
// audit-agent.json naming the OLD head still came back 'ok'; (2) the task files pm_task_create writes under .antigravity-pm/
// (untracked in a repo that does not gitignore it) changed the hash after tree0 => a false 'worktree hash differs'.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { judgeAudit, treeHash } from '../bin/pm-review-audit.js';
import { tmpDir, cleanup } from './helpers.js';

function repo(prefix) {
  const dir = tmpDir(prefix);
  const g = (...a) => execFileSync('git', ['-C', dir, ...a]).toString().trim();
  const commit = (msg) => g('-c', 'user.email=t@t', '-c', 'user.name=t', '-c', 'commit.gpgsign=false', 'commit', '-qm', msg);
  g('init', '-q'); fs.writeFileSync(path.join(dir, 'a.txt'), '1'); g('add', '-A'); commit('i');
  return { dir, g, commit };
}

test('F8: HEAD moved during the audit (both trees clean) is never ok for the old head', () => {
  const { dir, g, commit } = repo('agpm-head-moved-');
  try {
    const head0 = g('rev-parse', 'HEAD');
    const tree0 = treeHash(dir);
    fs.writeFileSync(path.join(dir, 'a.txt'), '2'); g('add', '-A'); commit('moved during the audit');
    assert.equal(g('status', '--porcelain'), '', 'fixture: the tree is clean against the new HEAD');
    const tree1 = treeHash(dir);
    const r = judgeAudit({ verdict: 'pass', auditedHead: head0 }, { head: head0, tree0, tree1 });
    assert.notEqual(r.status, 'ok', `audit of ${head0} accepted after HEAD moved: ${JSON.stringify(r)}`);
  } finally { cleanup(dir); }
});

test('F8: untracked .antigravity-pm/ task files created after tree0 do not change the hash; other untracked files still do', () => {
  const { dir, g } = repo('agpm-statedir-');
  try {
    const head0 = g('rev-parse', 'HEAD');
    const tree0 = treeHash(dir);
    const taskDir = path.join(dir, '.antigravity-pm', 'tasks', 'T0001-review');
    fs.mkdirSync(taskDir, { recursive: true });
    fs.writeFileSync(path.join(taskDir, 'brief.md'), 'CHI DOC');
    fs.writeFileSync(path.join(taskDir, 'audit-agent.json'), JSON.stringify({ verdict: 'pass', auditedHead: head0 }));
    const tree1 = treeHash(dir);
    assert.equal(tree1, tree0, 'the PM state dir counted as a working-tree change');
    assert.equal(judgeAudit({ verdict: 'pass', auditedHead: head0 }, { head: head0, tree0, tree1 }).status, 'ok');
    fs.writeFileSync(path.join(dir, '.antigravity-pm-other.txt'), 'x');   // only the state dir itself is left out
    assert.notEqual(treeHash(dir), tree0);
  } finally { cleanup(dir); }
});
