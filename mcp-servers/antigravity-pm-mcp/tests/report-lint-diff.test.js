// #24: bao cao nghiem thu phai dung CHINH ctx cong da xet; phanTichDiff khong cat sai duong dan chua "b/".
import test from 'node:test';
import assert from 'node:assert/strict';
import { loadConfig } from '../src/config.js';
import { createTask, loadTask } from '../src/tasks.js';
import { renderReport } from '../src/report.js';
import { phanTichDiff } from '../src/lint-diff.js';
import { tmpProject, cleanup, sampleTaskArgs } from './helpers.js';

test('#24 AC1: renderReport dung gateCtx truyen vao — chan lint hien trong bao cao', () => {
  const dir = tmpProject({ testCommand: 'echo ok' });
  const cfg = loadConfig(dir);
  const task = createTask(cfg, sampleTaskArgs());
  const ctx = { changedFiles: [], lintBlockers: ['db/schema.sql: create table trung "xe" — dinh nghia bang 2 lan'], lintWarnings: [] };
  const rep = renderReport(cfg, loadTask(cfg, task.id), { gateCtx: ctx });
  assert.ok(rep.gate.missing.some((m) => m.includes('db/schema.sql')), JSON.stringify(rep.gate.missing));
  assert.ok(rep.markdown.includes('db/schema.sql'));
  cleanup(dir);
});

test('#24 AC2: phanTichDiff giu nguyen duong dan co thu muc ket thuc bang b (lib/, web/, db/)', () => {
  const diff = ['src/lib/foo.js', 'app/web/x.js', 'db/schema.sql', 'plain.js']
    .map((f) => `diff --git a/${f} b/${f}\n--- a/${f}\n+++ b/${f}\n@@ -1 +1 @@\n-a\n+b`).join('\n');
  assert.deepEqual(phanTichDiff(diff).map((f) => f.file), ['src/lib/foo.js', 'app/web/x.js', 'db/schema.sql', 'plain.js']);
});
