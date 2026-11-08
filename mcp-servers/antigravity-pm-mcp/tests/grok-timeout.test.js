// 04/11: audit grok THAT tren PR #977 (merge-base..75df5df3: 26 file, 1692 dong doi) bi giet dung 20 phut (han co dinh GROK_TIMEOUT_MS),
// phai chay lai voi ANTIGRAVITY_PM_GROK_TIMEOUT_MS dat tay ~3000000. Han mac dinh nay tinh theo kich thuoc diff (san 20 phut, +1 phut moi
// 100 dong doi, khong biet so dong thi +1 phut moi file, tran 60 phut); env dat hop le van thang nhu cu; han da dung ghi vao log + thong bao.
// Khong chay grok that: grok gia qua ANTIGRAVITY_PM_GROK.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { loadConfig } from '../src/config.js';
import { createTask, updateTask } from '../src/tasks.js';
import { TOOLS_BY_NAME } from '../src/tools.js';
import * as agentapi from '../src/agentapi.js';
import { tmpDir, tmpProject, cleanup, writeFile, sampleTaskArgs } from './helpers.js';

const ENV = 'ANTIGRAVITY_PM_GROK_TIMEOUT_MS';
delete process.env[ENV];   // chu repo hay dat tay ~3000000 trong shell: test han tu tinh khong duoc phu thuoc no
delete process.env.DEVKIT_AGENT_ID;
for (const k of ['GROK_SESSION_ID', 'GROK_WORKSPACE_ROOT', 'GROK_HOOK_EVENT']) delete process.env[k];
const MIN = 60 * 1000;

/** grok gia: ngu `sleep` giay roi in VERDICT: PASS. */
function fakeGrok(sleep = 0) {
  const d = tmpDir('agpm-fake-grok-');
  const bin = path.join(d, 'grok');
  fs.writeFileSync(bin, ['#!/bin/bash', ...(sleep ? [`sleep ${sleep}`] : []), 'echo "VERDICT: PASS"', ''].join('\n'));
  fs.chmodSync(bin, 0o755);
  return bin;
}

test('GT1 grokTimeoutMs: san 20 phut, +1 phut moi 100 dong (khong biet dong: +1 phut moi file), tran 60 phut, env hop le thang', () => {
  const f = agentapi.grokTimeoutMs;
  assert.equal(typeof f, 'function', 'agentapi phai export grokTimeoutMs');
  const env = {};
  assert.equal(f({ env }), 20 * MIN, 'khong biet kich thuoc: giu han cu');
  assert.equal(f({ lines: 0, files: 0, env }), 20 * MIN);
  assert.equal(f({ lines: 99, files: 3, env }), 20 * MIN, 'diff nho giu dung 20 phut');
  assert.equal(f({ lines: 1692, files: 26, env }), 36 * MIN, 'PR #977 (luot qua han): 20 + 16');
  assert.equal(f({ lines: 4106, files: 39, env }), 60 * MIN, 'tran 60 phut');
  assert.equal(f({ lines: null, files: 26, env }), 46 * MIN, 'loi git: tinh theo so file');
  assert.equal(f({ files: 500, env }), 60 * MIN, 'theo file cung co tran');
  assert.equal(f({ lines: 1692, files: 26, env: { [ENV]: '3000000' } }), 3000000, 'env hop le thang, khong bi tran');
  assert.equal(f({ lines: 10, env: { [ENV]: '7200000' } }), 7200000);
  for (const bad of ['', 'abc', '0', '-5']) {
    assert.equal(f({ lines: 1692, files: 26, env: { [ENV]: bad } }), 36 * MIN, `env khong hop le "${bad}" -> tu tinh`);
  }
});

test('GT2 runGrokAudit nhan timeoutMs: grok qua han bi giet theo han truyen vao; khong truyen thi van theo env nhu cu', async () => {
  const grok = fakeGrok(3);
  const cwd = tmpDir('agpm-grok-cwd-');
  let t0 = Date.now();
  const r = await agentapi.runGrokAudit({ grok, cwd, prompt: 'x', timeoutMs: 500 });
  assert.equal(r.timedOut, true, 'han 500 ms phai giet grok ngu 3 s');
  assert.ok(Date.now() - t0 < 2500, `giet dung han (${Date.now() - t0} ms)`);
  process.env[ENV] = '500';
  try {
    t0 = Date.now();
    const r2 = await agentapi.runGrokAudit({ grok, cwd, prompt: 'x' });
    assert.equal(r2.timedOut, true, 'chu ky cu (khong timeoutMs) van doc env');
    assert.ok(Date.now() - t0 < 2500);
  } finally {
    delete process.env[ENV];
  }
});

test('GT3 pm_dispatch audit grok: han tinh tu git diff --shortstat merge-base..head, ghi o dong dau log va trong thong bao', async () => {
  const dir = tmpProject({ projectName: 'grok-timeout', testCommand: 'echo ok' });
  const savedGrok = process.env.ANTIGRAVITY_PM_GROK;
  try {
    const git = (...a) => execFileSync('git', a, { cwd: dir, encoding: 'utf8' }).trim();
    git('init', '-q', '-b', 'main');
    writeFile(path.join(dir, '.gitignore'), '.antigravity-pm/\n');
    writeFile(path.join(dir, 'a.txt'), 'a\n');
    git('add', '-A');
    git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'init');
    git('checkout', '-q', '-b', 'feat');
    writeFile(path.join(dir, 'big.txt'), Array.from({ length: 2000 }, (_, i) => `dong ${i}`).join('\n') + '\n');
    writeFile(path.join(dir, 'a.txt'), 'b\n');
    git('add', '-A');
    git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'feat');
    const cfg = loadConfig(dir);
    const task = createTask(cfg, sampleTaskArgs());
    process.env.ANTIGRAVITY_PM_GROK = fakeGrok();
    const msg = await TOOLS_BY_NAME.get('pm_dispatch').handler({ project: dir, taskId: task.id, kind: 'audit', agent: 'grok' });
    const text = typeof msg === 'string' ? msg : JSON.stringify(msg);
    // 2002 dong doi (2000 them + 1 them + 1 xoa), 2 file -> 20 + 20 = 40 phut
    assert.match(text, /Han grok: 2400000 ms \(40 phut; 2002 dong doi, 2 file\)/);
    const logFile = text.match(/Log grok: (\S+)/)[1];
    assert.match(fs.readFileSync(logFile, 'utf8').split('\n')[0], /Han grok: 2400000 ms \(40 phut; 2002 dong doi, 2 file\)/);
  } finally {
    if (savedGrok === undefined) delete process.env.ANTIGRAVITY_PM_GROK; else process.env.ANTIGRAVITY_PM_GROK = savedGrok;
    cleanup(dir);
  }
});

test('GT4 git khong dem duoc diff (goc khong ton tai, khong co nhanh dich): khong vo, giu san 20 phut, log stderr kem ngu canh', async () => {
  const dir = tmpProject({ projectName: 'grok-timeout-loi', testCommand: 'echo ok' });
  const savedGrok = process.env.ANTIGRAVITY_PM_GROK;
  const write = process.stderr.write;
  let err = '';
  try {
    const git = (...a) => execFileSync('git', a, { cwd: dir, encoding: 'utf8' }).trim();
    git('init', '-q', '-b', 'dev');
    writeFile(path.join(dir, '.gitignore'), '.antigravity-pm/\n');
    git('add', '-A');
    git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'init');
    const cfg = loadConfig(dir);
    const task = createTask(cfg, sampleTaskArgs());
    updateTask(cfg, task, (t) => { t.baseCommit = 'f'.repeat(40); });
    process.env.ANTIGRAVITY_PM_GROK = fakeGrok();
    process.stderr.write = (s, ...rest) => { err += String(s); return write.call(process.stderr, s, ...rest); };
    const msg = await TOOLS_BY_NAME.get('pm_dispatch').handler({ project: dir, taskId: task.id, kind: 'audit', agent: 'grok' });
    process.stderr.write = write;
    assert.match(String(msg), /Han grok: 1200000 ms \(20 phut; khong dem duoc diff\)/);
    assert.match(err, new RegExp(`grok audit ${task.id}: khong dem duoc dong doi \\(git diff --shortstat f{40}`));
  } finally {
    process.stderr.write = write;
    if (savedGrok === undefined) delete process.env.ANTIGRAVITY_PM_GROK; else process.env.ANTIGRAVITY_PM_GROK = savedGrok;
    cleanup(dir);
  }
});
