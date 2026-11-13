// 13/11/2026 (chu repo bo Grok, PR #1163): duong audit grok va han GROK_TIMEOUT_MS tinh theo diff (04/11) da bi go. File nay giu lenh cua
// rule REG-PM-GROK-TIMEOUT-01 trong ma tran (gate chi tin ma tran chi-them: xoa rule giua danh sach = "regression matrix khong tin duoc")
// va kiem dieu thay the: khong con han / bien env / duong chay grok nao, pm_dispatch agent=grok bi tu choi truoc khi ghi lan giao.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as agentapi from '../src/agentapi.js';
import * as tools from '../src/tools.js';
import { loadConfig } from '../src/config.js';
import { createTask, loadTask } from '../src/tasks.js';
import { tmpProject, cleanup, sampleTaskArgs } from './helpers.js';

const SRC = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'src');
const call = (name, args) => tools.TOOLS_BY_NAME.get(name).handler(args);

test('khong con export han / duong chay grok nao trong agentapi.js va tools.js', () => {
  for (const mod of [agentapi, tools]) {
    const left = Object.keys(mod).filter((k) => /grok/i.test(k));
    assert.deepEqual(left, [], `export grok con sot: ${left.join(', ')}`);
  }
});

test('ma nguon PM khong con doc ANTIGRAVITY_PM_GROK / ANTIGRAVITY_PM_GROK_TIMEOUT_MS', () => {
  for (const f of fs.readdirSync(SRC).filter((n) => n.endsWith('.js'))) {
    const body = fs.readFileSync(path.join(SRC, f), 'utf8');
    assert.ok(!/ANTIGRAVITY_PM_GROK/.test(body), `${f} con doc bien env ANTIGRAVITY_PM_GROK*`);
  }
});

test('pm_dispatch kind=audit agent=grok bi tu choi, khong ghi lan giao', async () => {
  const dir = tmpProject({ projectName: 'grok-timeout-gone', testCommand: 'echo ok' });
  try {
    const cfg = loadConfig(dir);
    const task = createTask(cfg, sampleTaskArgs());
    await assert.rejects(call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }), /Grok da bi go/);
    assert.deepEqual(loadTask(cfg, task.id).dispatches || [], []);
  } finally {
    cleanup(dir);
  }
});
