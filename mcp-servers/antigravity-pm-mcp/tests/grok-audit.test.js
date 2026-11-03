// Dot 2 lane A2 (03/11/2026): Grok tam thay Antigravity duyet (audit) test sua khi agy bi gioi han (429). Reviewer chi duoc tin khi PM
// TU chay reviewer: pm_dispatch kind=audit agent=grok chay grok o che do plan (chi doc), PM tu ghi audit-agent.json tu dong `VERDICT:`
// va luu sha256 cua file vao lan giao; pm_verdict chep reviewer vao verdicts.audit.reviewer, tu choi auditedHead khi chua co lan giao
// audit nao, va voi grok doi sha audit-agent.json khop sha PM da luu (chan ghi de tay). Khong chay grok that: grok gia qua ANTIGRAVITY_PM_GROK.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { loadConfig } from '../src/config.js';
import { createTask, recordDispatch, taskFile, hashFile } from '../src/tasks.js';
import { TOOLS_BY_NAME } from '../src/tools.js';
import { tmpDir, tmpProject, cleanup, writeFile, sampleTaskArgs } from './helpers.js';

const call = (name, args) => TOOLS_BY_NAME.get(name).handler(args);
delete process.env.DEVKIT_AGENT_ID;   // builder mac dinh claude, khong phu thuoc agent dang chay test

function repo() {
  const dir = tmpProject({ projectName: 'grok-audit', testCommand: 'echo ok' });
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

/** grok gia: ghi argv + env ra file, in `out` ra stdout, thoat voi `code`. */
function fakeGrok({ out = 'Khong thay loi.\nVERDICT: PASS\n', code = 0 } = {}) {
  const d = tmpDir('agpm-fake-grok-');
  const bin = path.join(d, 'grok');
  fs.writeFileSync(path.join(d, 'out.txt'), out);
  fs.writeFileSync(bin, [
    '#!/bin/bash',
    `D=${JSON.stringify(d)}`,
    'printf "%s\\n" "$@" > "$D/argv.txt"',
    'env > "$D/env.txt"',
    'cat "$D/out.txt"',
    `exit ${code}`,
    '',
  ].join('\n'));
  fs.chmodSync(bin, 0o755);
  return { d, bin, argv: () => fs.readFileSync(path.join(d, 'argv.txt'), 'utf8').split('\n').slice(0, -1), env: () => fs.readFileSync(path.join(d, 'env.txt'), 'utf8') };
}

function withGrok(fake, fn) {
  const saved = process.env.ANTIGRAVITY_PM_GROK;
  process.env.ANTIGRAVITY_PM_GROK = fake.bin;
  return Promise.resolve(fn()).finally(() => {
    if (saved === undefined) delete process.env.ANTIGRAVITY_PM_GROK; else process.env.ANTIGRAVITY_PM_GROK = saved;
  });
}

const SESSION_VAR = 'CLAUDE_CODE_MESSAGING_TOKEN';   // bien messaging cua phien Claude (#734)
const disk = (cfg, task) => JSON.parse(fs.readFileSync(taskFile(cfg, task.id), 'utf8'));
const repOf = (dir, task) => path.join(dir, '.antigravity-pm', 'tasks', task.id, 'audit-agent.json');

test('G1 pm_dispatch audit agent=grok: PM chay grok plan mode, ghi dispatch + audit-agent.json + sha; pm_verdict ghi reviewer grok', async () => {
  const { dir, cfg, task, head } = repo();
  const fake = fakeGrok();
  process.env[SESSION_VAR] = `gia-${process.pid}`;
  try {
    await withGrok(fake, () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    const argv = fake.argv();
    assert.deepEqual(argv.slice(0, 7), ['-m', 'grok-4.7', '--permission-mode', 'plan', '--cwd', cfg.projectRoot, '-p']);
    assert.match(argv.slice(7).join('\n'), /VERDICT/);
    assert.doesNotMatch(fake.env(), new RegExp(SESSION_VAR), 'bien messaging cua phien Claude khong duoc xuong grok');
    const t = disk(cfg, task);
    const d = t.dispatches.at(-1);
    assert.equal(d.kind, 'audit');
    assert.equal(d.agent, 'grok');
    assert.equal(d.model, 'grok-4.7');
    assert.equal(d.auditedHead, head);
    assert.equal(d.verdict, 'pass');
    const rep = JSON.parse(fs.readFileSync(repOf(dir, task), 'utf8'));
    assert.equal(rep.verdict, 'pass');
    assert.equal(rep.reviewer, 'grok');
    assert.equal(rep.auditedHead, head);
    assert.match(rep.notes, /Grok thay Antigravity/);
    assert.equal(d.reportSha256, hashFile(repOf(dir, task)));
    assert.ok(Date.parse(d.at) <= fs.statSync(repOf(dir, task)).mtimeMs, 'moc giao phai truoc luc ghi bao cao');
    await call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head, notes: 'ok' });
    const a = disk(cfg, task).verdicts.audit;
    assert.equal(a.reviewer, 'grok');
    assert.equal(a.auditedHead, head);
  } finally {
    delete process.env[SESSION_VAR];
    cleanup(dir);
  }
});

test('G2 audit-agent.json bi ghi de tay sau lan grok: pm_verdict tu choi (sha khong khop / reviewer khac grok)', async () => {
  const { dir, cfg, task, head } = repo();
  try {
    await withGrok(fakeGrok(), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    const rep = repOf(dir, task);
    const orig = fs.readFileSync(rep, 'utf8');
    fs.writeFileSync(rep, `${orig} `);
    await assert.rejects(call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head }), /sha256/);
    fs.writeFileSync(rep, JSON.stringify({ verdict: 'pass', reviewer: 'antigravity', auditedHead: head }));
    await assert.rejects(call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head }), /grok/);
    assert.equal(disk(cfg, task).verdicts?.audit, undefined);
  } finally {
    cleanup(dir);
  }
});

test('G3 grok REVISE / FAIL / khong VERDICT / VERDICT mau thuan / exit khac 0: bao cao fail, auditedHead bi tu choi', async () => {
  const cases = [
    { out: 'co loi\nVERDICT: REVISE\n' },
    { out: 'hong\nVERDICT: FAIL\n' },
    { out: 'quen ket luan\n' },
    { out: 'VERDICT: PASS\nnghi lai\nVERDICT: FAIL\n' },
    { out: 'Chon mot: VERDICT: PASS|REVISE|FAIL\n' },
    { out: 'VERDICT: PASS\n', code: 3 },
  ];
  for (const c of cases) {
    const { dir, cfg, task, head } = repo();
    try {
      await withGrok(fakeGrok(c), async () => {
        try { await call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }); } catch { /* loi duoc: chi xet bao cao */ }
      });
      const rep = JSON.parse(fs.readFileSync(repOf(dir, task), 'utf8'));
      assert.equal(rep.verdict, 'fail', JSON.stringify(c));
      assert.equal(disk(cfg, task).dispatches.at(-1).agent, 'grok', JSON.stringify(c));
      await assert.rejects(call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head }), /verdict/, JSON.stringify(c));
      assert.equal(disk(cfg, task).verdicts?.audit, undefined, JSON.stringify(c));
    } finally {
      cleanup(dir);
    }
  }
});

test('G4 chua co lan giao audit nao (chi giao implement): bao cao ghi tay khong duoc ghi auditedHead', async () => {
  const { dir, cfg, task, head } = repo();
  try {
    recordDispatch(cfg, task, { kind: 'implement', conversationId: 'c-impl', headCommit: null });
    // reviewer khong phai builder (claude, antigravity) cung khong phai grok: chi luat "chua co lan giao audit" chan duoc
    writeFile(repOf(dir, task), JSON.stringify({ verdict: 'pass', reviewer: 'codex', auditedHead: head }));
    await assert.rejects(call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head }), /Chua co lan giao audit nao/);
    assert.equal(disk(cfg, task).verdicts?.audit, undefined);
    // tu khai grok khi chua co lan giao grok nao cung bi chan
    writeFile(repOf(dir, task), JSON.stringify({ verdict: 'pass', reviewer: 'grok', auditedHead: head }));
    await assert.rejects(call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head }), /giao audit/);
    assert.equal(disk(cfg, task).verdicts?.audit, undefined);
  } finally {
    cleanup(dir);
  }
});

test('G5 luong cu (lan giao audit khong co agent = Antigravity): reviewer antigravity; bao cao tu khai grok bi tu choi', async () => {
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

test('G6 khong co grok: pm_dispatch tu choi, khong ghi lan giao; agent=grok chi cho kind=audit', async () => {
  const { dir, cfg, task } = repo();
  try {
    await withGrok({ bin: path.join(tmpDir('agpm-no-grok-'), 'grok') }, async () => {
      await assert.rejects(call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }), /grok/);
    });
    await withGrok(fakeGrok(), async () => {
      await assert.rejects(call('pm_dispatch', { project: dir, taskId: task.id, kind: 'implement', agent: 'grok', force: true }), /grok/);
    });
    assert.equal((disk(cfg, task).dispatches || []).length, 0);
    assert.equal(fs.existsSync(repOf(dir, task)), false);
  } finally {
    cleanup(dir);
  }
});
