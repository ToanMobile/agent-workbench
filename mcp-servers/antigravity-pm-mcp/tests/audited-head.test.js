// Audit T0066 vong 2 (#605, PR #609): pm_verdict kind=audit verdict=pass ghi verdicts.audit.auditedHead (sha40 cua cay da audit) —
// DevKit push_gate.audited_head doc truong nay truoc notes. Task chi audit (audit cheo PR co san: co lan giao audit, khong giao trien
// khai) ghi duoc ket luan audit; review van can da giao trien khai.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { loadConfig } from '../src/config.js';
import { createTask, loadTask, recordDispatch, taskFile } from '../src/tasks.js';
import { TOOLS_BY_NAME } from '../src/tools.js';
import { tmpProject, cleanup, writeFile, sampleTaskArgs } from './helpers.js';

const SHA = 'a'.repeat(40);
const verdict = (args) => TOOLS_BY_NAME.get('pm_verdict').handler(args);

function auditOnlyTask() {
  const dir = tmpProject({ projectName: 'audited-head', testCommand: 'echo ok' });
  execFileSync('git', ['init', '-q'], { cwd: dir });
  writeFile(path.join(dir, '.gitignore'), '.antigravity-pm/\n');
  execFileSync('git', ['add', '-A'], { cwd: dir });
  execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'init'], { cwd: dir });
  const cfg = loadConfig(dir);
  const task = createTask(cfg, sampleTaskArgs());
  recordDispatch(cfg, task, { kind: 'audit', conversationId: 'c-audit' });
  return { dir, cfg, task };
}
const auditOf = (cfg, task) => JSON.parse(fs.readFileSync(taskFile(cfg, task.id), 'utf8')).verdicts?.audit;

test('AH1 task chi audit: pm_verdict audit pass voi auditedHead ghi verdicts.audit.auditedHead', async () => {
  const { dir, cfg, task } = auditOnlyTask();
  try {
    await verdict({ project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', notes: 'ok', auditedHead: SHA });
    assert.equal(auditOf(cfg, task).auditedHead, SHA);
    assert.equal(auditOf(cfg, task).verdict, 'pass');
  } finally {
    cleanup(dir);
  }
});

test('AH2 khong co tham so auditedHead: lay `auditedHead: <sha40>` trong notes', async () => {
  const { dir, cfg, task } = auditOnlyTask();
  try {
    const sha = 'b1'.repeat(20);
    await verdict({ project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', notes: `audit ok\nauditedHead: ${sha}` });
    assert.equal(auditOf(cfg, task).auditedHead, sha);
  } finally {
    cleanup(dir);
  }
});

test('AH3 auditedHead sai khuon hoac dung sai cho bi tu choi, khong ghi gi', async () => {
  const { dir, cfg, task } = auditOnlyTask();
  try {
    await assert.rejects(verdict({ project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: 'HEAD' }), /sha 40/);
    await assert.rejects(verdict({ project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: SHA.toUpperCase() }), /sha 40/);
    await assert.rejects(verdict({ project: dir, taskId: task.id, kind: 'audit', verdict: 'fail', auditedHead: SHA }), /kind=audit verdict=pass/);
    assert.equal(auditOf(cfg, task), undefined);
  } finally {
    cleanup(dir);
  }
});

test('AH4 task chi audit: review van bi tu choi (can giao trien khai); khong co lan giao nao thi audit cung bi tu choi', async () => {
  const { dir, task } = auditOnlyTask();
  try {
    await assert.rejects(verdict({ project: dir, taskId: task.id, kind: 'review', verdict: 'pass' }), /Chua giao trien khai/);
  } finally {
    cleanup(dir);
  }
  const dir2 = tmpProject({ testCommand: 'echo ok' });
  try {
    const t2 = createTask(loadConfig(dir2), sampleTaskArgs());
    await assert.rejects(verdict({ project: dir2, taskId: t2.id, kind: 'audit', verdict: 'pass', auditedHead: SHA }), /Chua giao trien khai/);
  } finally {
    cleanup(dir2);
  }
});

test('AH5 audit pass khong auditedHead: khong ghi truong (gate DevKit se khong duyet)', async () => {
  const { dir, cfg, task } = auditOnlyTask();
  try {
    const out = await verdict({ project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', notes: 'ok' });
    assert.equal(auditOf(cfg, task).auditedHead, undefined);
    assert.match(out, /khong co auditedHead/);
    assert.ok(loadTask(cfg, task.id));
  } finally {
    cleanup(dir);
  }
});
