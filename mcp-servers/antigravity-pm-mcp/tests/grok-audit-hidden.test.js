// 13/11/2026 (PR #1163, chu repo bo Grok): cac ca #909 / H5 cua audit grok cu (file bi che khoi git status, cay doi trong luc audit) chuyen
// sang audit Antigravity co pham vi (auditScopeOf): gate DevKit duyet test sua tu bien ban nay, nen ban sua bi che hoac cay ban luc giao /
// luc chot khong duoc ra mot lan giao co pham vi dat 'pass'. agy that khong bao gio duoc goi: ANTIGRAVITY_PM_AGY tro vao script gia.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { loadConfig } from '../src/config.js';
import { loadTask, taskFile } from '../src/tasks.js';
import { TOOLS_BY_NAME } from '../src/tools.js';
import { homeStateDir } from '../src/util.js';
import { tmpProject, tmpDir, cleanup, writeFile } from './helpers.js';

const ARGON = 'gemini-4-argon-high';
const FAKE = `#!/usr/bin/env node
const out = (o) => console.log(JSON.stringify(o));
out({ event: 'init', conversation_id: 'c0c0c0c0-1111-2222-3333-444444444444', init: { cwd: process.cwd() } });
out({ event: 'result', result: { conversation_id: 'c0c0c0c0-1111-2222-3333-444444444444', status: 'SUCCESS' } });
`;
const KEYS = ['ANTIGRAVITY_PM_AGY', 'ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS', 'ANTIGRAVITY_PM_AGENTAPI', 'DEVKIT_AGENT_ID'];
delete process.env.DEVKIT_AGENT_ID;
for (const k of ['GROK_SESSION_ID', 'GROK_WORKSPACE_ROOT', 'GROK_HOOK_EVENT']) delete process.env[k];

function fakeAgy(t) {
  const d = tmpDir('agpm-scope-');
  const bin = path.join(d, 'agy');
  fs.writeFileSync(bin, FAKE, { mode: 0o755 });
  const agentapi = path.join(d, 'agentapi');
  fs.writeFileSync(agentapi, `#!/bin/sh\necho '{"response": {}, "error": "rpc error: code = Unavailable"}'\nexit 1\n`, { mode: 0o755 });
  const prev = { ...process.env };
  Object.assign(process.env, { ANTIGRAVITY_PM_AGY: bin, ANTIGRAVITY_PM_AGY_SKIP_PERMISSIONS: '1', ANTIGRAVITY_PM_AGENTAPI: agentapi });
  t.after(() => {
    for (const k of KEYS) { if (prev[k] === undefined) delete process.env[k]; else process.env[k] = prev[k]; }
    fs.rmSync(path.join(homeStateDir(), 'agy-conversations.json'), { force: true });
    cleanup(d);
  });
}

const git = (dir, ...a) => execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', ...a], { cwd: dir, encoding: 'utf8' }).trim();
/** Repo: main co a.txt + t.sh; nhanh feat sua t.sh, them b.txt. Tra { dir, head, base }. */
function prRepo(t) {
  const dir = tmpProject({ projectName: 'audit-scope', testCommand: 'echo ok', defaultModel: ARGON });
  t.after(() => cleanup(dir));
  git(dir, 'init', '-q', '-b', 'main');
  writeFile(path.join(dir, '.gitignore'), '.antigravity-pm/\n');
  writeFile(path.join(dir, 'a.txt'), 'a\n');
  writeFile(path.join(dir, 't.sh'), 'echo 1\n');
  git(dir, 'add', '-A');
  git(dir, 'commit', '-qm', 'init');
  const base = git(dir, 'rev-parse', 'HEAD');
  git(dir, 'checkout', '-q', '-b', 'feat');
  writeFile(path.join(dir, 't.sh'), 'echo 2\n');
  writeFile(path.join(dir, 'b.txt'), 'b\n');
  git(dir, 'add', '-A');
  git(dir, 'commit', '-qm', 'pr');
  return { dir, base, head: git(dir, 'rev-parse', 'HEAD') };
}
const call = async (name, args) => { const out = await TOOLS_BY_NAME.get(name).handler(args); return typeof out === 'string' ? out : out.text; };
const newTask = async (dir) => /T\d{4}-[a-z0-9-]+/.exec(await call('pm_task_create', { project: dir, title: 'a', brief: 'b', definitionOfDone: ['c'] }))[0];
const audits = (dir, id) => JSON.parse(fs.readFileSync(taskFile(loadConfig(dir), id), 'utf8')).dispatches.filter((d) => d.kind === 'audit');
const report = (dir, id, head, verdict = 'pass') => writeFile(path.join(dir, '.antigravity-pm', 'tasks', id, 'audit-agent.json'),
  JSON.stringify({ phase: 'AUDIT', verdict, reviewer: 'antigravity', auditedHead: head, findings: [] }));

test('I2 skip-worktree / assume-unchanged che ban sua chua commit cua test khoi git status: lan giao audit KHONG ghi pham vi', async (t) => {
  fakeAgy(t);
  for (const flag of ['--skip-worktree', '--assume-unchanged']) {
    const { dir } = prRepo(t);
    const id = await newTask(dir);
    writeFile(path.join(dir, 't.sh'), 'echo yeu hon\n');
    git(dir, 'update-index', flag, 't.sh');
    assert.equal(git(dir, 'status', '--porcelain', '--untracked-files=no'), '', `${flag}: git status phai rong (ban sua bi che)`);
    await call('pm_dispatch', { project: dir, taskId: id, kind: 'audit' });
    const [d] = audits(dir, id);
    assert.equal(d.auditedHead, undefined, `${flag}: khong duoc ghi auditedHead khi co file bi che`);
    assert.equal(d.edited, undefined, `${flag}: khong duoc ghi pham vi khi co file bi che`);
  }
});

test('H5 HEAD doi sau lan giao (commit them truoc khi chot): pm_verdict khong cho lan giao co pham vi dat pass voi head moi', async (t) => {
  fakeAgy(t);
  const { dir, head } = prRepo(t);
  const id = await newTask(dir);
  await call('pm_dispatch', { project: dir, taskId: id, kind: 'audit' });
  writeFile(path.join(dir, 't.sh'), 'echo yeu hon\n');
  git(dir, 'commit', '-qam', 'sua test sau lan giao');
  const head2 = git(dir, 'rev-parse', 'HEAD');
  report(dir, id, head2);
  await call('pm_verdict', { project: dir, taskId: id, kind: 'audit', verdict: 'pass', auditedHead: head2 });
  assert.equal(loadTask(loadConfig(dir), id).verdicts.audit.auditedHead, head2, 'pm_verdict phai chay het (ghi verdicts.audit), khong nem som');
  const [d] = audits(dir, id);
  assert.equal(d.auditedHead, head, 'lan giao giu head luc giao');
  assert.notEqual(d.verdict, 'pass', 'lan giao co pham vi khong duoc dat pass khi bao cao/chot o head khac head luc giao');
});
