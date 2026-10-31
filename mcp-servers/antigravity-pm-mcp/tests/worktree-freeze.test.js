// critical scan 31/10 — BUG-REV-agpm-worktree-leak: a throw after `git worktree add` in dongBangCay left the worktree behind.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { loadConfig } from '../src/config.js';
import { dongBangCay } from '../src/worktree.js';
import { tmpProject, cleanup } from './helpers.js';

const git = (cwd, ...a) => execFileSync('git', a, { cwd, encoding: 'utf8', env: { ...process.env, GIT_DIR: undefined, GIT_WORK_TREE: undefined } });

test('dongBangCay: an error while copying untracked files removes the frozen worktree again', { skip: process.getuid?.() === 0 }, async () => {
  const dir = tmpProject({});
  try {
    git(dir, 'init', '-q', '.');
    git(dir, '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-q', '--allow-empty', '-m', 'i');
    const secret = path.join(dir, 'unreadable.txt');
    fs.writeFileSync(secret, 'x');
    fs.chmodSync(secret, 0o000);
    const cfg = loadConfig(dir);
    await assert.rejects(dongBangCay(cfg));
    const list = git(dir, 'worktree', 'list', '--porcelain').split('\n').filter((l) => l.startsWith('worktree '));
    assert.equal(list.length, 1, list.join('\n'));
    fs.chmodSync(secret, 0o600);
  } finally { cleanup(dir); }
});
