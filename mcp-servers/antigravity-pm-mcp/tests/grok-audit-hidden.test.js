// #909 (hau #988, ba muc P3 con lai cua grok audit): (1) sparse-checkout / skip-worktree / assume-unchanged che file khoi git status nen audit
// van PASS du grok khong doc duoc file; (2) projectRoot la thu muc con cua repo: change set tinh path tu goc repo con existsSync tinh theo
// projectRoot; (3) `git worktree add` loi: thu muc tam agpm-grok-* phai bi don. Grok that khong chay: grok gia qua ANTIGRAVITY_PM_GROK.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { loadConfig } from '../src/config.js';
import { createTask } from '../src/tasks.js';
import { TOOLS_BY_NAME } from '../src/tools.js';
import { tmpDir, tmpProject, cleanup, writeFile, sampleTaskArgs } from './helpers.js';

const call = (name, args) => TOOLS_BY_NAME.get(name).handler(args);
delete process.env.DEVKIT_AGENT_ID;
for (const k of ['GROK_SESSION_ID', 'GROK_WORKSPACE_ROOT', 'GROK_HOOK_EVENT']) delete process.env[k];

const git = (cwd, ...args) => execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', ...args], { cwd, encoding: 'utf8' });
function commitFile(cwd, rel, content, msg = rel) {
  writeFile(path.join(cwd, rel), content);
  git(cwd, 'add', '-A', '--', rel);
  git(cwd, 'commit', '-qm', msg);
  return git(cwd, 'rev-parse', 'HEAD').trim();
}
function fakeGrok(sh = '') {
  const d = tmpDir('agpm-fake-grok-');
  const bin = path.join(d, 'grok');
  fs.writeFileSync(bin, ['#!/bin/bash', ...(sh ? [sh] : []), 'echo "VERDICT: PASS"', 'exit 0', ''].join('\n'));
  fs.chmodSync(bin, 0o755);
  return bin;
}
async function withGrok(bin, fn) {
  const saved = process.env.ANTIGRAVITY_PM_GROK;
  process.env.ANTIGRAVITY_PM_GROK = bin;
  try { return await fn(); } finally {
    if (saved === undefined) delete process.env.ANTIGRAVITY_PM_GROK; else process.env.ANTIGRAVITY_PM_GROK = saved;
  }
}
function repo() {
  const dir = tmpProject({ projectName: 'grok-hidden', testCommand: 'echo ok' });
  git(dir, 'init', '-q');
  writeFile(path.join(dir, '.gitignore'), '.antigravity-pm/\n');
  commitFile(dir, 'a.txt', 'a\n', 'init');
  return dir;
}
const repOf = (dir, task) => JSON.parse(fs.readFileSync(path.join(dir, '.antigravity-pm', 'tasks', task.id, 'audit-agent.json'), 'utf8'));

test('I1 #909 sparse-checkout: file ngoai cone khong co tren dia (worktree tam commit=<sha> ke thua pattern) => bao cao fail, khong PASS', async () => {
  const dir = repo();
  try {
    commitFile(dir, 'out/x.txt', 'ngoai cone\n');
    const head = git(dir, 'rev-parse', 'HEAD').trim();
    git(dir, 'sparse-checkout', 'set', '--no-cone', '/a.txt', '/.gitignore', '/.antigravity-pm.json');
    assert.equal(fs.existsSync(path.join(dir, 'out', 'x.txt')), false, 'dieu kien: file ngoai cone khong co tren dia');
    const task = createTask(loadConfig(dir), sampleTaskArgs());
    await withGrok(fakeGrok(), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok', commit: head }));
    const rep = repOf(dir, task);
    assert.equal(rep.verdict, 'fail', rep.notes);
    assert.match(rep.notes, /sparse|skip-worktree/i);
  } finally { cleanup(dir); }
});

test('I2 #909 cay chinh: skip-worktree / assume-unchanged che ban sua chua commit khoi git status => bao cao fail', async () => {
  for (const flag of ['--skip-worktree', '--assume-unchanged']) {
    const dir = repo();
    try {
      const task = createTask(loadConfig(dir), sampleTaskArgs());
      git(dir, 'update-index', flag, 'a.txt');
      writeFile(path.join(dir, 'a.txt'), 'ban sua chua commit\n');
      assert.equal(git(dir, 'status', '--porcelain', '--untracked-files=no').trim(), '', `dieu kien: ${flag} che a.txt khoi git status`);
      await withGrok(fakeGrok(), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
      const rep = repOf(dir, task);
      assert.equal(rep.verdict, 'fail', `${flag}: ${rep.notes}`);
      assert.match(rep.notes, /skip-worktree|assume-unchanged/i, flag);
    } finally { cleanup(dir); }
  }
});

test('I3 #909 projectRoot la thu muc con cua repo: commit xoa AGENTS.md o goc repo, hook sinh lai => bao cao fail', async () => {
  const parent = tmpDir('agpm-test-parent-');
  try {
    git(parent, 'init', '-q');
    const proj = path.join(parent, 'proj');
    writeFile(path.join(proj, '.antigravity-pm.json'), JSON.stringify({ projectName: 'sub', testCommand: 'echo ok' }));
    writeFile(path.join(parent, '.gitignore'), 'proj/.antigravity-pm/\n');
    commitFile(parent, 'AGENTS.md', 'goc\n', 'init');
    commitFile(parent, 'proj/b.txt', 'b\n', 'b');
    const task = createTask(loadConfig(proj), sampleTaskArgs());
    git(parent, 'rm', '-q', 'AGENTS.md');
    git(parent, 'commit', '-qm', 'xoa AGENTS.md');
    await withGrok(fakeGrok('echo sinh-lai > ../AGENTS.md'), () => call('pm_dispatch', { project: proj, taskId: task.id, kind: 'audit', agent: 'grok' }));
    const rep = repOf(proj, task);
    assert.equal(rep.verdict, 'fail', rep.notes);
    assert.match(rep.notes, /AGENTS\.md/);
  } finally { cleanup(parent); }
});

test('I4 #909 git worktree add loi: thu muc tam agpm-grok-* cua TMPDIR rieng rong (khong bo thu muc mo coi)', async () => {
  const dir = repo();
  const head = git(dir, 'rev-parse', 'HEAD').trim();
  const priv = tmpDir('agpm-priv-tmp-');
  const shim = tmpDir('agpm-git-shim-');
  const realGit = execFileSync('which', ['git'], { encoding: 'utf8' }).trim();
  fs.writeFileSync(path.join(shim, 'git'), `#!/bin/bash\nfor a in "$@"; do [ "$a" = worktree ] && for b in "$@"; do [ "$b" = add ] && { echo "shim: worktree add loi" >&2; exit 1; }; done; done\nexec ${JSON.stringify(realGit)} "$@"\n`);
  fs.chmodSync(path.join(shim, 'git'), 0o755);
  const task = createTask(loadConfig(dir), sampleTaskArgs());
  const saved = { PATH: process.env.PATH, TMPDIR: process.env.TMPDIR };
  const bin = fakeGrok();
  try {
    process.env.PATH = `${shim}:${process.env.PATH}`;
    process.env.TMPDIR = priv;
    await assert.rejects(withGrok(bin, () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok', commit: head })), /worktree tam/);
  } finally {
    process.env.PATH = saved.PATH;
    if (saved.TMPDIR === undefined) delete process.env.TMPDIR; else process.env.TMPDIR = saved.TMPDIR;
    cleanup(dir);
  }
  assert.deepEqual(fs.readdirSync(priv), [], 'thu muc tam cua lan audit loi phai bi don');
});
