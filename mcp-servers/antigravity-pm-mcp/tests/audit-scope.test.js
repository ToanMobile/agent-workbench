// 13/11/2026 (chu repo bo Grok): pm_dispatch kind=audit agent=grok bi tu choi; audit Antigravity ghi pham vi PR (auditedHead, auditBase =
// merge-base nhanh dich, edited = file da co bi sua/xoa) vao lan giao, va pm_verdict kind=audit ghi ket luan vao CHINH lan giao do — gate
// DevKit (push_gate.audit_scope / scoped_audit_runs) tra thang bien ban nay de duyet test sua thay cho luot grok cu.
// agy that khong bao gio duoc goi: ANTIGRAVITY_PM_AGY tro vao script gia.
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

test('S1 agent=grok bi tu choi (Grok da go 13/11), khong ghi lan giao nao', async (t) => {
  const { dir } = prRepo(t);
  const id = await newTask(dir);
  await assert.rejects(call('pm_dispatch', { project: dir, taskId: id, kind: 'audit', agent: 'grok' }), /Grok da bi go/);
  assert.equal(audits(dir, id).length, 0);
});

test('S2 audit Antigravity tren cay sach: lan giao ghi auditedHead, auditBase = merge-base, edited = file da co bi sua; prompt neu pham vi', async (t) => {
  fakeAgy(t);
  const { dir, base, head } = prRepo(t);
  const id = await newTask(dir);
  await call('pm_dispatch', { project: dir, taskId: id, kind: 'audit' });
  const [d] = audits(dir, id);
  assert.equal(d.agent, 'antigravity');
  assert.equal(d.auditedHead, head);
  assert.equal(d.auditBase, base);
  assert.deepEqual(d.edited, ['t.sh']);
  assert.equal(d.verdict, undefined, 'chua co ket luan luc giao');
  const prompt = fs.readFileSync(d.promptFile, 'utf8');
  assert.ok(prompt.includes(`${base}..${head}`), 'prompt khong neu pham vi base..head');
  assert.ok(prompt.includes('t.sh'), 'prompt khong liet ke test da sua');
});

test('S3 cay ban hoac co message: khong ghi pham vi (gate khong duyet test sua qua bien ban nay)', async (t) => {
  fakeAgy(t);
  const { dir } = prRepo(t);
  const id = await newTask(dir);
  await call('pm_dispatch', { project: dir, taskId: id, kind: 'audit', message: 'soi ky file x' });
  writeFile(path.join(dir, 'a.txt'), 'sua chua commit\n');
  await call('pm_dispatch', { project: dir, taskId: id, kind: 'audit' });
  for (const d of audits(dir, id)) {
    assert.equal(d.auditBase, undefined);
    assert.equal(d.edited, undefined);
    assert.equal(d.auditedHead, undefined);
  }
});

test('S4 pm_verdict audit pass dung head: lan giao co pham vi nhan verdict pass + finishedAt; fail -> verdict fail', async (t) => {
  fakeAgy(t);
  const { dir, head } = prRepo(t);
  const id = await newTask(dir);
  await call('pm_dispatch', { project: dir, taskId: id, kind: 'audit' });
  report(dir, id, head);
  await call('pm_verdict', { project: dir, taskId: id, kind: 'audit', verdict: 'pass', auditedHead: head, notes: 'ok' });
  const [d] = audits(dir, id);
  assert.equal(d.verdict, 'pass');
  assert.ok(d.finishedAt, 'thieu finishedAt');
  assert.equal(loadTask(loadConfig(dir), id).verdicts.audit.reviewer, 'antigravity');
  await call('pm_dispatch', { project: dir, taskId: id, kind: 'audit' });
  report(dir, id, head, 'fail');
  await call('pm_verdict', { project: dir, taskId: id, kind: 'audit', verdict: 'fail', findings: ['x:1 sai'] });
  assert.equal(audits(dir, id)[1].verdict, 'fail');
});

test('S5 lan giao audit gan nhat la grok (bien ban cu): pm_verdict audit pass bi tu choi', async (t) => {
  const { dir, head } = prRepo(t);
  const id = await newTask(dir);
  const cfg = loadConfig(dir);
  const f = taskFile(cfg, id);
  const tk = JSON.parse(fs.readFileSync(f, 'utf8'));
  tk.dispatches = [...(tk.dispatches || []), { kind: 'audit', agent: 'grok', at: new Date(Date.now() - 1000).toISOString(), auditedHead: head }];
  fs.writeFileSync(f, JSON.stringify(tk));
  report(dir, id, head);
  await assert.rejects(call('pm_verdict', { project: dir, taskId: id, kind: 'audit', verdict: 'pass', auditedHead: head }), /grok/i);
});
