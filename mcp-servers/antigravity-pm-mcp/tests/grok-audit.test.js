// 13/11/2026 (PR #1163, chu repo bo Grok): cac ca grok da go; file nay giu cac ca kiem phan PM van dung de bat tu duyet, khong lien quan Grok:
// danh tinh nguoi goi (callerAgent / callerAgents), chuan hoa ten agent (normalizeAgent khop push_gate.normalize_reviewer), lan giao audit
// cu khong co agent = Antigravity, reviewer tu khai la bi bo qua (theo agent cua lan giao), va verdicts.auditHistory chi-them.
// Chep lai tu grok-audit.test.js (F1, F2, G5, G7, H3, H4), F1 doi sang lan giao audit Antigravity (khong chay grok).
import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { loadConfig } from '../src/config.js';
import { createTask, recordDispatch, taskFile } from '../src/tasks.js';
import { TOOLS_BY_NAME } from '../src/tools.js';
import * as tools from '../src/tools.js';
import { tmpProject, cleanup, writeFile, sampleTaskArgs } from './helpers.js';

const call = (name, args) => TOOLS_BY_NAME.get(name).handler(args);
delete process.env.DEVKIT_AGENT_ID;   // builder mac dinh claude, khong phu thuoc agent dang chay test
for (const k of ['GROK_SESSION_ID', 'GROK_WORKSPACE_ROOT', 'GROK_HOOK_EVENT']) delete process.env[k];

function repo() {
  const dir = tmpProject({ projectName: 'agent-identity', testCommand: 'echo ok' });
  execFileSync('git', ['init', '-q'], { cwd: dir });
  writeFile(path.join(dir, '.gitignore'), '.antigravity-pm/\n');
  writeFile(path.join(dir, 'a.txt'), 'a\n');
  execFileSync('git', ['add', '-A'], { cwd: dir });
  execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'init'], { cwd: dir });
  const head = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: dir, encoding: 'utf8' }).trim();
  const cfg = loadConfig(dir);
  const task = createTask(cfg, sampleTaskArgs());
  return { dir, cfg, task, head };
}

function commitFile(dir, name, body) {
  writeFile(path.join(dir, name), body);
  execFileSync('git', ['add', '-A'], { cwd: dir });
  execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', name], { cwd: dir });
  return execFileSync('git', ['rev-parse', 'HEAD'], { cwd: dir, encoding: 'utf8' }).trim();
}

const disk = (cfg, task) => JSON.parse(fs.readFileSync(taskFile(cfg, task.id), 'utf8'));
const repOf = (dir, task) => path.join(dir, '.antigravity-pm', 'tasks', task.id, 'audit-agent.json');

test('F2 callerAgent: DEVKIT_AGENT_ID chuan hoa > env phien Grok > env phien Claude > ""', () => {
  const f = tools.callerAgent;
  assert.equal(typeof f, 'function', 'tools.js phai export callerAgent(env)');
  const cases = [
    [{ DEVKIT_AGENT_ID: 'Grok-Build ', CLAUDECODE: '1' }, 'grok'],
    [{ DEVKIT_AGENT_ID: 'Antigravity' }, 'antigravity'],
    [{ DEVKIT_AGENT_ID: 'codex', GROK_SESSION_ID: 's' }, 'codex'],
    [{ DEVKIT_AGENT_ID: '  ', GROK_SESSION_ID: 's' }, 'grok'],
    [{ GROK_HOOK_EVENT: 'PreToolUse', CLAUDE_CODE_SESSION_ID: 'x' }, 'grok'],
    [{ GROK_SESSION_ID: '', CLAUDECODE: '1' }, 'claude'],
    [{ CLAUDECODE: '1' }, 'claude'],
    [{ CLAUDE_CODE_SESSION_ID: 'abc' }, 'claude'],
    [{ CLAUDECODE: '0' }, ''],
    [{}, ''],
  ];
  for (const [env, want] of cases) assert.equal(f(env), want, JSON.stringify(env));
});

test('H3 normalizeAgent khop push_gate.normalize_reviewer: antigravity + - _ . ; cung tap ky tu strip (\\ufeff, \\x1f)', () => {
  const f = tools.callerAgent;
  const cases = [
    ['Antigravity_2', 'antigravity'], ['antigravity.x', 'antigravity'], ['antigravity-pro', 'antigravity'], ['Antigravity-Pro', 'antigravity'],
    ['antigravityx', 'antigravityx'], [' antigravity_2﻿', 'antigravity'], ['\x1fcodex\x85', 'codex'],
    ['﻿grok', 'grok'], ['grok build', 'grok'], ['Grok4', 'grok4'],
  ];
  for (const [id, want] of cases) assert.equal(f({ DEVKIT_AGENT_ID: id }), want, JSON.stringify(id));
});

test('H4 callerAgents: tap danh tinh phien = {DEVKIT_AGENT_ID chuan hoa} + {grok khi GROK_*} + {claude khi CLAUDECODE=1/CLAUDE_CODE_SESSION_ID}', () => {
  const f = tools.callerAgents;
  assert.equal(typeof f, 'function', 'tools.js phai export callerAgents(env)');
  const cases = [
    [{ DEVKIT_AGENT_ID: 'codex', GROK_SESSION_ID: 's' }, ['codex', 'grok']],
    [{ DEVKIT_AGENT_ID: 'Codex', GROK_HOOK_EVENT: 'Stop', CLAUDECODE: '1' }, ['claude', 'codex', 'grok']],
    [{ DEVKIT_AGENT_ID: 'Antigravity-Pro', CLAUDE_CODE_SESSION_ID: 'x' }, ['antigravity', 'claude']],
    [{ DEVKIT_AGENT_ID: '  ', CLAUDECODE: '0' }, []],
    [{}, []],
  ];
  for (const [env, want] of cases) assert.deepEqual([...f(env)].sort(), want, JSON.stringify(env));
});

test('G5 lan giao audit cu khong co agent = Antigravity: reviewer antigravity; bao cao tu khai grok bi tu choi', async () => {
  const { dir, cfg, task, head } = repo();
  try {
    recordDispatch(cfg, task, { kind: 'audit', conversationId: 'c-audit' });
    writeFile(repOf(dir, task), JSON.stringify({ verdict: 'pass', reviewer: 'grok', auditedHead: head }));
    await assert.rejects(call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head }), /grok/);
    writeFile(repOf(dir, task), JSON.stringify({ verdict: 'pass', reviewer: 'antigravity', auditedHead: head }));
    await call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head });
    const a = disk(cfg, task).verdicts.audit;
    assert.equal(a.reviewer, 'antigravity');
    assert.equal(a.auditedHead, head);
  } finally {
    cleanup(dir);
  }
});

test('G7 Antigravity build roi Antigravity audit, bao cao tu khai reviewer la chuoi la: van la tu duyet (theo agent cua lan giao PM)', async () => {
  const { dir, cfg, task, head } = repo();
  try {
    recordDispatch(cfg, task, { kind: 'implement', conversationId: 'c-impl', headCommit: null });
    recordDispatch(cfg, task, { kind: 'audit', conversationId: 'c-audit' });
    writeFile(repOf(dir, task), JSON.stringify({ verdict: 'pass', reviewer: 'gemini-3', auditedHead: head }));
    await call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head });
    const a = disk(cfg, task).verdicts.audit;
    assert.equal(a.reviewer, 'antigravity');
    assert.equal(a.auditedHead, undefined, 'agent lan giao audit (antigravity) trung builder: khong ghi auditedHead');
  } finally {
    cleanup(dir);
  }
});

test('F1 audit pass co auditedHead noi vao verdicts.auditHistory (chi-them); verdict fail sau khong xoa head pass cu', async () => {
  const { dir, cfg, task, head } = repo();
  try {
    recordDispatch(cfg, task, { kind: 'audit', conversationId: 'c-audit-1' });
    writeFile(repOf(dir, task), JSON.stringify({ verdict: 'pass', reviewer: 'antigravity', auditedHead: head }));
    await call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head, notes: 'ok' });
    const h1 = disk(cfg, task).verdicts.auditHistory;
    assert.ok(Array.isArray(h1), 'verdicts.auditHistory phai la mang');
    assert.equal(h1.length, 1);
    assert.deepEqual(Object.keys(h1[0]).sort(), ['at', 'auditedHead', 'reviewer']);
    assert.equal(h1[0].auditedHead, head);
    assert.equal(h1[0].reviewer, 'antigravity');
    assert.ok(Date.parse(h1[0].at) > 0);
    await call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'fail', findings: ['a.txt:1 sai'] });
    let t = disk(cfg, task);
    assert.equal(t.verdicts.audit.verdict, 'fail');
    assert.deepEqual(t.verdicts.auditHistory, h1);
    const head2 = commitFile(dir, 'b.txt', 'b\n');
    recordDispatch(cfg, disk(cfg, task), { kind: 'audit', conversationId: 'c-audit-2' });
    writeFile(repOf(dir, task), JSON.stringify({ verdict: 'pass', reviewer: 'antigravity', auditedHead: head2 }));
    await call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head2 });
    t = disk(cfg, task);
    assert.deepEqual(t.verdicts.auditHistory.map((x) => x.auditedHead), [head, head2]);
    assert.equal(t.verdicts.audit.auditedHead, head2);
  } finally {
    cleanup(dir);
  }
});
