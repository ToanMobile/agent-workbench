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
import * as tools from '../src/tools.js';
import { tmpDir, tmpProject, cleanup, writeFile, sampleTaskArgs } from './helpers.js';

const call = (name, args) => TOOLS_BY_NAME.get(name).handler(args);
delete process.env.DEVKIT_AGENT_ID;   // builder mac dinh claude, khong phu thuoc agent dang chay test
// F2: danh tinh nguoi goi doc ca env cua phien Grok; test chay trong phien Grok khong duoc thanh "nguoi goi grok" ngoai y muon.
for (const k of ['GROK_SESSION_ID', 'GROK_WORKSPACE_ROOT', 'GROK_HOOK_EVENT']) delete process.env[k];

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

/** grok gia: ghi argv + env ra file, chay `sh` (lenh shell them, vd sua file trong luc audit), in `out` ra stdout, thoat voi `code`. */
function fakeGrok({ out = 'Khong thay loi.\nVERDICT: PASS\n', code = 0, sh = '' } = {}) {
  const d = tmpDir('agpm-fake-grok-');
  const bin = path.join(d, 'grok');
  fs.writeFileSync(path.join(d, 'out.txt'), out);
  fs.writeFileSync(bin, [
    '#!/bin/bash',
    `D=${JSON.stringify(d)}`,
    'printf "%s\\n" "$@" > "$D/argv.txt"',
    'env > "$D/env.txt"',
    ...(sh ? [sh] : []),
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

test('G7 OCR P2: Antigravity build roi Antigravity audit, bao cao tu khai reviewer la chuoi la: van la tu duyet (theo agent cua lan giao PM)', async () => {
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

// ---- Dot 2 sua sau review (F1, F2, G3, F5) ----------------------------------------------------------------------------------

/** Dat tam env (undefined = xoa) trong luc chay fn, tra lai nhu cu sau do. */
async function withEnv(vars, fn) {
  const saved = Object.fromEntries(Object.keys(vars).map((k) => [k, process.env[k]]));
  for (const [k, v] of Object.entries(vars)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; }
  try { return await fn(); } finally {
    for (const [k, v] of Object.entries(saved)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; }
  }
}
const grokRan = (fake) => fs.existsSync(path.join(fake.d, 'argv.txt'));
const commitFile = (dir, name, body) => {
  writeFile(path.join(dir, name), body);
  execFileSync('git', ['add', name], { cwd: dir });
  execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', name], { cwd: dir });
  return execFileSync('git', ['rev-parse', 'HEAD'], { cwd: dir, encoding: 'utf8' }).trim();
};

test('F1 audit pass co auditedHead noi vao verdicts.auditHistory (chi-them); verdict fail sau khong xoa head pass cu', async () => {
  const { dir, cfg, task, head } = repo();
  try {
    await withGrok(fakeGrok(), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    await call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head, notes: 'ok' });
    const h1 = disk(cfg, task).verdicts.auditHistory;
    assert.ok(Array.isArray(h1), 'verdicts.auditHistory phai la mang');
    assert.equal(h1.length, 1);
    assert.deepEqual(Object.keys(h1[0]).sort(), ['at', 'auditedHead', 'reviewer']);
    assert.equal(h1[0].auditedHead, head);
    assert.equal(h1[0].reviewer, 'grok');
    assert.ok(Date.parse(h1[0].at) > 0);
    // verdict fail sau do: verdicts.audit thanh fail nhung head pass cu van trong lich su
    await call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'fail', findings: ['a.txt:1 sai'] });
    let t = disk(cfg, task);
    assert.equal(t.verdicts.audit.verdict, 'fail');
    assert.deepEqual(t.verdicts.auditHistory, h1);
    // commit moi, audit pass lan hai: noi them, giu thu tu
    const head2 = commitFile(dir, 'b.txt', 'b\n');
    await withGrok(fakeGrok(), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    await call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head2 });
    t = disk(cfg, task);
    assert.deepEqual(t.verdicts.auditHistory.map((x) => x.auditedHead), [head, head2]);
    assert.equal(t.verdicts.audit.auditedHead, head2);
  } finally {
    cleanup(dir);
  }
});

test('F2 callerAgent: DEVKIT_AGENT_ID chuan hoa > env phien Grok > env phien Claude > ""', () => {
  const f = tools.callerAgent;
  assert.equal(typeof f, 'function', 'tools.js phai export callerAgent(env)');
  const cases = [
    [{ DEVKIT_AGENT_ID: 'Grok-Build ', CLAUDECODE: '1' }, 'grok'],
    [{ DEVKIT_AGENT_ID: 'grok-4.7' }, 'grok'],
    [{ DEVKIT_AGENT_ID: 'Antigravity' }, 'antigravity'],
    [{ DEVKIT_AGENT_ID: 'codex', GROK_SESSION_ID: 's' }, 'codex'],   // author (mot gia tri); tap danh tinh callerAgents (H4) = {codex, grok}
    [{ DEVKIT_AGENT_ID: '  ', GROK_SESSION_ID: 's' }, 'grok'],
    [{ GROK_WORKSPACE_ROOT: '/w', CLAUDECODE: '1' }, 'grok'],
    [{ GROK_HOOK_EVENT: 'PreToolUse', CLAUDE_CODE_SESSION_ID: 'x' }, 'grok'],
    [{ GROK_SESSION_ID: '', CLAUDECODE: '1' }, 'claude'],
    [{ CLAUDECODE: '1' }, 'claude'],
    [{ CLAUDE_CODE_SESSION_ID: 'abc' }, 'claude'],
    [{ CLAUDECODE: '0' }, ''],
    [{}, ''],
  ];
  for (const [env, want] of cases) assert.equal(f(env), want, JSON.stringify(env));
});

test('F2 pm_dispatch audit agent=grok tu choi khi nguoi goi PM la grok (tu duyet), ke ca force; grok khong chay', async () => {
  for (const env of [{ GROK_HOOK_EVENT: 'PostToolUse' }, { GROK_SESSION_ID: 's1' }, { DEVKIT_AGENT_ID: 'Grok-4.7' }]) {
    const { dir, cfg, task } = repo();
    const fake = fakeGrok();
    try {
      await withEnv(env, () => withGrok(fake, () => assert.rejects(
        call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok', force: true }), /tu duyet/, JSON.stringify(env))));
      assert.equal((disk(cfg, task).dispatches || []).length, 0, JSON.stringify(env));
      assert.equal(grokRan(fake), false, JSON.stringify(env));
      assert.equal(fs.existsSync(repOf(dir, task)), false, JSON.stringify(env));
    } finally {
      cleanup(dir);
    }
  }
});

test('F2 pm_verdict: nguoi goi la grok (env phien Grok, khong DEVKIT_AGENT_ID) + reviewer grok = tu duyet, khong auditedHead/history', async () => {
  const { dir, cfg, task, head } = repo();
  try {
    await withGrok(fakeGrok(), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    const out = await withEnv({ GROK_SESSION_ID: 's2' },
      () => call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head }));
    assert.match(out, /trung builder/);
    const t = disk(cfg, task);
    assert.equal(t.verdicts.audit.verdict, 'pass');
    assert.equal(t.verdicts.audit.auditedHead, undefined);
    assert.equal((t.verdicts.auditHistory || []).length, 0);
  } finally {
    cleanup(dir);
  }
});

test('G3 pm_verdict chuan hoa builders va reviewer (grok-build / grok-4.7 -> grok) truoc khi so tu duyet', async () => {
  const cases = [
    { agentId: 'grok-build', reviewer: 'grok' },
    { agentId: 'grok', reviewer: 'grok-4.7' },
    { agentId: 'Grok-4.7', reviewer: 'GROK-build' },
  ];
  for (const c of cases) {
    const { dir, cfg, task, head } = repo();
    try {
      // lan giao audit grok "cua PM" ghi truc tiep (pm_dispatch tu choi nguoi goi grok — F2); bao cao + sha khop
      const at = new Date(Date.now() - 2000).toISOString();
      writeFile(repOf(dir, task), JSON.stringify({ phase: 'AUDIT', verdict: 'pass', reviewer: c.reviewer, auditedHead: head }));
      recordDispatch(cfg, task, { kind: 'audit', agent: 'grok', model: 'grok-4.7', at, extra: { auditedHead: head, reportSha256: hashFile(repOf(dir, task)) } });
      const out = await withEnv({ DEVKIT_AGENT_ID: c.agentId },
        () => call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head }));
      assert.match(out, /trung builder/, JSON.stringify(c));
      const t = disk(cfg, task);
      assert.equal(t.verdicts.audit.auditedHead, undefined, JSON.stringify(c));
      assert.equal((t.verdicts.auditHistory || []).length, 0, JSON.stringify(c));
    } finally {
      cleanup(dir);
    }
  }
});

test('F5 pm_dispatch audit agent=grok tu choi khi cay lam viec co thay doi da theo doi (git status khong rong); untracked thi duoc', async () => {
  const { dir, cfg, task } = repo();
  const fake = fakeGrok();
  try {
    writeFile(path.join(dir, 'a.txt'), 'a sua chua commit\n');
    await withGrok(fake, () => assert.rejects(
      call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok', force: true }), /git status/));
    assert.equal((disk(cfg, task).dispatches || []).length, 0);
    assert.equal(grokRan(fake), false);
    assert.equal(fs.existsSync(repOf(dir, task)), false);
    // da stage cung bi tu choi
    execFileSync('git', ['add', 'a.txt'], { cwd: dir });
    await withGrok(fake, () => assert.rejects(
      call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }), /git status/));
    assert.equal(grokRan(fake), false);
    // tra cay ve sach, chi con file untracked: duoc audit
    execFileSync('git', ['reset', '-q', '--hard'], { cwd: dir });
    writeFile(path.join(dir, 'moi.txt'), 'untracked\n');
    await withGrok(fake, () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    assert.equal(grokRan(fake), true);
    assert.equal(disk(cfg, task).dispatches.at(-1).agent, 'grok');
  } finally {
    cleanup(dir);
  }
});

test('F5 thu muc trang thai PM bi repo track va da doi (vd audit-agent.json lan truoc): khong chan audit lai; file code doi van chan', async () => {
  const { dir, cfg, task } = repo();
  try {
    // repo track ca thu muc trang thai (bat chap .gitignore cua fixture)
    const st = path.join('.antigravity-pm', 'tracked.txt');
    writeFile(path.join(dir, st), 'v1\n');
    execFileSync('git', ['add', '-f', st], { cwd: dir });
    execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'track state'], { cwd: dir });
    writeFile(path.join(dir, st), 'v2\n');
    const fake = fakeGrok();
    await withGrok(fake, () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    assert.equal(grokRan(fake), true);
    writeFile(path.join(dir, 'a.txt'), 'doi\n');
    await withGrok(fakeGrok(), () => assert.rejects(
      call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }), /a\.txt/));
    assert.equal(disk(cfg, task).dispatches.length, 1);
  } finally {
    cleanup(dir);
  }
});

// ---- Vong kiem lai (H3, H4, H5) ----------------------------------------------------------------------------------------------

test('H3 normalizeAgent khop push_gate.normalize_reviewer: antigravity + - _ . ; cung tap ky tu strip (\\ufeff, \\x1f)', () => {
  const f = tools.callerAgent;
  const cases = [
    ['Antigravity_2', 'antigravity'], ['antigravity.x', 'antigravity'], ['antigravity-pro', 'antigravity'], ['antigravityx', 'antigravityx'],
    ['﻿grok', 'grok'], ['\x1fgrok-4', 'grok'], [' antigravity_2﻿', 'antigravity'], ['\x1fcodex\x85', 'codex'],
    ['grok build', 'grok'], ['grok:', 'grok'], ['Grok4', 'grok4'], ['grokker', 'grokker'],
  ];
  for (const [id, want] of cases) assert.equal(f({ DEVKIT_AGENT_ID: id }), want, JSON.stringify(id));
});

test('H4 callerAgents: tap danh tinh phien = {DEVKIT_AGENT_ID chuan hoa} + {grok khi GROK_*} + {claude khi CLAUDECODE=1/CLAUDE_CODE_SESSION_ID}', () => {
  const f = tools.callerAgents;
  assert.equal(typeof f, 'function', 'tools.js phai export callerAgents(env)');
  const cases = [
    [{ DEVKIT_AGENT_ID: 'codex', GROK_SESSION_ID: 's' }, ['codex', 'grok']],
    [{ DEVKIT_AGENT_ID: 'Codex', GROK_HOOK_EVENT: 'Stop', CLAUDECODE: '1' }, ['claude', 'codex', 'grok']],
    [{ DEVKIT_AGENT_ID: 'grok-4.7', CLAUDE_CODE_SESSION_ID: 'x' }, ['claude', 'grok']],
    [{ DEVKIT_AGENT_ID: '  ', CLAUDECODE: '0' }, []],
    [{}, []],
  ];
  for (const [env, want] of cases) assert.deepEqual([...f(env)].sort(), want, JSON.stringify(env));
});

test('H4 DEVKIT_AGENT_ID=codex nhung phien co GROK_*: pm_dispatch grok tu choi (tu duyet); pm_verdict reviewer grok = trung builder', async () => {
  const env = { DEVKIT_AGENT_ID: 'codex', GROK_SESSION_ID: 'g-1' };
  {
    const { dir, cfg, task } = repo();
    const fake = fakeGrok();
    try {
      await withEnv(env, () => withGrok(fake, () => assert.rejects(
        call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok', force: true }), /tu duyet/)));
      assert.equal((disk(cfg, task).dispatches || []).length, 0);
      assert.equal(grokRan(fake), false);
    } finally {
      cleanup(dir);
    }
  }
  const { dir, cfg, task, head } = repo();
  try {
    await withGrok(fakeGrok(), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    const out = await withEnv(env, () => call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head }));
    assert.match(out, /trung builder/);
    const t = disk(cfg, task);
    assert.equal(t.verdicts.audit.auditedHead, undefined);
    assert.equal((t.verdicts.auditHistory || []).length, 0);
  } finally {
    cleanup(dir);
  }
});

test('H5 cay lam viec doi TRONG luc grok audit (file da theo doi sua, HEAD giu nguyen): bao cao fail kem ly do; chi them untracked thi van pass', async () => {
  {
    const { dir, cfg, task, head } = repo();
    try {
      await withGrok(fakeGrok({ sh: 'echo doi >> a.txt' }), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
      assert.equal(execFileSync('git', ['rev-parse', 'HEAD'], { cwd: dir, encoding: 'utf8' }).trim(), head, 'HEAD khong doi: chi git status bat duoc');
      const rep = JSON.parse(fs.readFileSync(repOf(dir, task), 'utf8'));
      assert.equal(rep.verdict, 'fail');
      assert.match(rep.notes, /cay lam viec doi trong luc audit/);
      assert.match(rep.notes, /a\.txt/);
      assert.equal(disk(cfg, task).dispatches.at(-1).verdict, 'fail');
    } finally {
      cleanup(dir);
    }
  }
  const { dir, cfg, task } = repo();
  try {
    await withGrok(fakeGrok({ sh: 'echo moi > moi-untracked.txt' }), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    assert.equal(JSON.parse(fs.readFileSync(repOf(dir, task), 'utf8')).verdict, 'pass');
    assert.equal(disk(cfg, task).dispatches.at(-1).verdict, 'pass');
  } finally {
    cleanup(dir);
  }
});

// ---- #987: Grok trong repo app + audit mot commit chi dinh ---------------------------------------------------------------------
// Phien grok khoi dong lam hook DevKit sinh lai AGENTS.md / .agents/CHECKLIST.md ... trong cay dang audit: cay "doi" nhung khong phai
// thay doi cua nguoi. Chi cac file sinh tu dong NAY duoc bo qua; moi file khac doi van fail (H5).

test('H6 #987 grok in VERDICT: PASS va hook DevKit sinh lai AGENTS.md trong luc audit: bao cao van pass; file code doi van fail', async () => {
  {
    const { dir, cfg } = repo();
    try {
      commitFile(dir, 'AGENTS.md', 'goc\n');
      commitFile(dir, path.join('.agents', 'CHECKLIST.md'), 'goc\n');
      const task = createTask(cfg, sampleTaskArgs());   // goc cua task = commit da co 2 file nay: chung khong thuoc change set
      await withGrok(fakeGrok({ sh: 'echo sinh-lai >> AGENTS.md; echo sinh-lai >> .agents/CHECKLIST.md' }),
        () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
      const rep = JSON.parse(fs.readFileSync(repOf(dir, task), 'utf8'));
      assert.equal(rep.verdict, 'pass', rep.notes);
      assert.match(rep.notes, /file DevKit tu sinh da bo qua: (?=.*AGENTS\.md)(?=.*\.agents\/CHECKLIST\.md)/, 'notes phai ghi file da bo qua');
      assert.equal(disk(cfg, task).dispatches.at(-1).verdict, 'pass');
    } finally {
      cleanup(dir);
    }
  }
  // AGENTS.md sua tay chua commit TRUOC khi giao (review #988): la rule that chu khong chi file sinh, nen bi chan nhu moi file da theo doi —
  // audit se gan PASS vao sha cua HEAD cho bytes khac HEAD. Muon audit luc cay ban thi commit=<sha>.
  const { dir, cfg, task } = repo();
  const fake = fakeGrok();
  try {
    const headNow = commitFile(dir, 'AGENTS.md', 'goc\n');
    writeFile(path.join(dir, 'AGENTS.md'), 'sua tay chua commit\n');
    await withGrok(fake, () => assert.rejects(
      call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }), /AGENTS\.md[\s\S]*commit=<sha>/));
    assert.equal(grokRan(fake), false);
    assert.equal((disk(cfg, task).dispatches || []).length, 0);
    // commit=<sha>: audit duoc du cay chinh ban, bytes la cua commit
    await withGrok(fake, () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok', commit: headNow }));
    assert.equal(grokRan(fake), true);
    const rep = JSON.parse(fs.readFileSync(repOf(dir, task), 'utf8'));
    assert.equal(rep.verdict, 'pass', rep.notes);
    assert.equal(rep.auditedHead, headNow);
    assert.equal(fs.readFileSync(path.join(dir, 'AGENTS.md'), 'utf8'), 'sua tay chua commit\n', 'ban sua tay o cay chinh khong bi dong');
  } finally {
    cleanup(dir);
  }
});

test('H9 #987 grok qua han / thoat loi / khong spawn duoc voi commit=<sha>: bao cao fail, worktree tam bi go khoi dang ky va khoi dia', async () => {
  const cases = [
    // han 3 s (khong phai 500 ms): grok gia phai kip ghi pwd.txt truoc khi bi giet, neu khong ca nay chap chon duoi tai
    { name: 'qua han', env: { ANTIGRAVITY_PM_GROK_TIMEOUT_MS: '3000' }, sh: 'pwd -P > "$D/pwd.txt"; sleep 30' },
    { name: 'exit 7', env: {}, sh: 'pwd -P > "$D/pwd.txt"; echo doi > moi.txt', code: 7 },
    { name: 'spawn loi', env: {}, broken: true },
  ];
  for (const c of cases) {
    const { dir, cfg, task, head } = repo();
    // TMPDIR rieng cho ca nay: worktree tam cua PM nam o os.tmpdir() => day la thu muc duy nhat PM tao, khong lan voi phien khac;
    // khai bao ngoai try de finally don duoc ke ca khi assert dau tien do
    const iso = tmpDir('agpm-iso-');   // khong trung tien to agpm-grok-* cua worktree tam
    try {
      const fake = fakeGrok({ sh: c.sh || '', code: c.code || 0 });
      // spawn loi: file thuc thi duoc (qua X_OK) nhung shebang tro toi trinh thong dich khong ton tai => spawnFailed
      if (c.broken) fs.writeFileSync(fake.bin, '#!/khong/co/trinh/thong/dich\n');
      await withEnv({ ...c.env, TMPDIR: iso }, () => withGrok(fake, () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok', commit: head })));
      const rep = JSON.parse(fs.readFileSync(repOf(dir, task), 'utf8'));
      assert.equal(rep.verdict, 'fail', c.name);
      if (c.broken) assert.match(rep.notes, /khong chay duoc grok/, c.name);
      assert.doesNotMatch(execFileSync('git', ['worktree', 'list'], { cwd: dir, encoding: 'utf8' }), /agpm-grok/, c.name);
      // thu muc worktree tam khong con tren dia: TMPDIR rieng phai rong (bao ca ca spawn loi khong kip ghi pwd.txt)
      assert.deepEqual(fs.readdirSync(iso), [], `${c.name}: thu muc worktree tam con tren dia`);
      // ca grok that su chay: bat buoc da vao worktree tam (pwd.txt), khong im lang bo qua
      if (!c.broken) {
        const pwdFile = path.join(fake.d, 'pwd.txt');
        assert.equal(fs.existsSync(pwdFile), true, `${c.name}: grok khong chay trong worktree tam`);
        // chung minh TMPDIR co tac dung: worktree tam that su nam trong iso (pwd -P tra duong dan da giai symlink)
        assert.ok(fs.readFileSync(pwdFile, 'utf8').trim().startsWith(fs.realpathSync(iso)), `${c.name}: worktree tam khong nam trong TMPDIR rieng`);
      }
      assert.equal(disk(cfg, task).dispatches.at(-1).auditedHead, head, c.name);
    } finally {
      cleanup(dir);
      cleanup(iso);
    }
  }
});

// Review #988 (lan 2): file DevKit tu sinh chi duoc bo qua khi KHONG nam trong change set dang audit (base..head). Neu chinh commit do sua
// AGENTS.md ma hook sinh lai no trong worktree tam thi grok doc bytes khac commit: cay doi => fail (hook sinh dung noi dung cu thi git
// status khong bao ban, khong mat gi).
test('H10 #987 commit=<sha>: AGENTS.md KHONG thuoc change set + hook sinh lai => pass, notes ghi file bo qua; AGENTS.md thuoc change set => fail', async () => {
  const regen = { sh: 'echo sinh-lai >> AGENTS.md' };
  {
    const { dir, cfg } = repo();
    try {
      commitFile(dir, 'AGENTS.md', 'goc\n');
      const task2 = createTask(cfg, sampleTaskArgs());   // goc cua task = commit da co AGENTS.md
      const headB = commitFile(dir, 'b.txt', 'b\n');
      await withGrok(fakeGrok(regen), () => call('pm_dispatch', { project: dir, taskId: task2.id, kind: 'audit', agent: 'grok', commit: headB }));
      const rep = JSON.parse(fs.readFileSync(repOf(dir, task2), 'utf8'));
      assert.equal(rep.verdict, 'pass', rep.notes);
      assert.equal(rep.auditedHead, headB);
      assert.match(rep.notes, /file DevKit tu sinh da bo qua: AGENTS\.md/);
    } finally {
      cleanup(dir);
    }
  }
  const { dir, cfg } = repo();
  try {
    commitFile(dir, 'AGENTS.md', 'goc\n');
    const task2 = createTask(cfg, sampleTaskArgs());
    const headC = commitFile(dir, 'AGENTS.md', 'commit nay sua AGENTS.md\n');
    await withGrok(fakeGrok(regen), () => call('pm_dispatch', { project: dir, taskId: task2.id, kind: 'audit', agent: 'grok', commit: headC }));
    const rep = JSON.parse(fs.readFileSync(repOf(dir, task2), 'utf8'));
    assert.equal(rep.verdict, 'fail', 'grok doc AGENTS.md bi hook ghi de, khong phai bytes cua commit');
    assert.match(rep.notes, /cay lam viec doi trong luc audit[\s\S]*AGENTS\.md/);
    assert.doesNotMatch(rep.notes, /file DevKit tu sinh da bo qua/);
    await assert.rejects(call('pm_verdict', { project: dir, taskId: task2.id, kind: 'audit', verdict: 'pass', auditedHead: headC }), /verdict/);
  } finally {
    cleanup(dir);
  }
});

test('H11 #987 task khong co commit goc (khong do duoc change set): khong bo qua file DevKit tu sinh nao, grok sinh lai AGENTS.md => fail', async () => {
  const { dir, cfg } = repo();
  try {
    commitFile(dir, 'AGENTS.md', 'goc\n');
    const task2 = createTask(cfg, sampleTaskArgs());
    const f = taskFile(cfg, task2.id);
    const t = JSON.parse(fs.readFileSync(f, 'utf8'));
    delete t.baseCommit; delete t.implementBaseCommit;
    fs.writeFileSync(f, JSON.stringify(t, null, 2));
    const headB = commitFile(dir, 'b.txt', 'b\n');
    await withGrok(fakeGrok({ sh: 'echo sinh-lai >> AGENTS.md' }), () => call('pm_dispatch', { project: dir, taskId: task2.id, kind: 'audit', agent: 'grok', commit: headB }));
    const rep = JSON.parse(fs.readFileSync(repOf(dir, task2), 'utf8'));
    assert.equal(rep.verdict, 'fail', rep.notes);
    assert.match(rep.notes, /cay lam viec doi trong luc audit[\s\S]*AGENTS\.md/);
  } finally {
    cleanup(dir);
  }
});

// Review #988 (vong 3): commit XOA / DOI TEN file DevKit roi hook sinh lai no => file thanh untracked, `git status --untracked-files=no`
// khong thay, grok doc bytes ma commit noi la khong ton tai. Phai fail.
test('H12 #987 commit=<sha> xoa hoac doi ten AGENTS.md, hook sinh lai: bao cao fail (file untracked khong duoc lot khoi kiem tra)', async () => {
  for (const how of ['xoa', 'doi ten']) {
    const { dir, cfg } = repo();
    try {
      commitFile(dir, 'AGENTS.md', 'goc\n');
      const task2 = createTask(cfg, sampleTaskArgs());
      if (how === 'xoa') execFileSync('git', ['rm', '-q', 'AGENTS.md'], { cwd: dir });
      else execFileSync('git', ['mv', 'AGENTS.md', 'RULES.md'], { cwd: dir });
      execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', how], { cwd: dir });
      const headD = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: dir, encoding: 'utf8' }).trim();
      await withGrok(fakeGrok({ sh: 'echo sinh-lai > AGENTS.md' }), () => call('pm_dispatch', { project: dir, taskId: task2.id, kind: 'audit', agent: 'grok', commit: headD }));
      const rep = JSON.parse(fs.readFileSync(repOf(dir, task2), 'utf8'));
      assert.equal(rep.verdict, 'fail', `${how}: ${rep.notes}`);
      assert.match(rep.notes, /AGENTS\.md/, how);
      assert.doesNotMatch(rep.notes, /file DevKit tu sinh da bo qua: [^;]*AGENTS\.md/, how);
    } finally {
      cleanup(dir);
    }
  }
});

// OCR vong 3: khong do duoc change set (task khong co goc) van phai bat file DevKit bi commit xoa roi sinh lai.
test('H13 #987 task khong co commit goc + commit xoa AGENTS.md + hook sinh lai: bao cao fail', async () => {
  const { dir, cfg } = repo();
  try {
    commitFile(dir, 'AGENTS.md', 'goc\n');
    const task2 = createTask(cfg, sampleTaskArgs());
    const f = taskFile(cfg, task2.id);
    const t = JSON.parse(fs.readFileSync(f, 'utf8'));
    delete t.baseCommit; delete t.implementBaseCommit;
    fs.writeFileSync(f, JSON.stringify(t, null, 2));
    execFileSync('git', ['rm', '-q', 'AGENTS.md'], { cwd: dir });
    execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'xoa'], { cwd: dir });
    const headD = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: dir, encoding: 'utf8' }).trim();
    await withGrok(fakeGrok({ sh: 'echo sinh-lai > AGENTS.md' }), () => call('pm_dispatch', { project: dir, taskId: task2.id, kind: 'audit', agent: 'grok', commit: headD }));
    const rep = JSON.parse(fs.readFileSync(repOf(dir, task2), 'utf8'));
    assert.equal(rep.verdict, 'fail', rep.notes);
    assert.match(rep.notes, /AGENTS\.md/);
  } finally {
    cleanup(dir);
  }
});

// Review cuoi: audit tren CAY CHINH, task khong co goc, AGENTS.md untracked co san tu TRUOC khi grok chay (khong phai hook vua sinh ra):
// khong duoc bao "commit da xoa/doi ten" sai — chi file xuat hien SAU khi grok chay moi dang ngo.
test('H14 #987 cay chinh + task khong co goc + AGENTS.md untracked co san truoc audit: khong bao fail oan', async () => {
  const { dir, cfg, task } = repo();
  try {
    const f = taskFile(cfg, task.id);
    const t = JSON.parse(fs.readFileSync(f, 'utf8'));
    delete t.baseCommit; delete t.implementBaseCommit;
    fs.writeFileSync(f, JSON.stringify(t, null, 2));
    writeFile(path.join(dir, 'AGENTS.md'), 'untracked co san\n');   // chua tung duoc commit; untracked thi F5 cho qua
    await withGrok(fakeGrok(), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    const rep = JSON.parse(fs.readFileSync(repOf(dir, task), 'utf8'));
    assert.equal(rep.verdict, 'pass', rep.notes);
  } finally {
    cleanup(dir);
  }
});

// Mat kia cua H14: cung cay chinh, cung task khong co goc, nhung AGENTS.md CHUA co tren dia truoc audit va hook sinh no TRONG luc grok
// chay => fail (grok doc file khong thuoc commit). Pin vi tri tinh coSan: phai tinh TRUOC khi grok chay.
test('H15 #987 cay chinh + task khong co goc + AGENTS.md chua co truoc audit, hook sinh trong luc grok chay: bao cao fail', async () => {
  const { dir, cfg, task } = repo();
  try {
    const f = taskFile(cfg, task.id);
    const t = JSON.parse(fs.readFileSync(f, 'utf8'));
    delete t.baseCommit; delete t.implementBaseCommit;
    fs.writeFileSync(f, JSON.stringify(t, null, 2));
    await withGrok(fakeGrok({ sh: 'echo sinh-lai > AGENTS.md' }), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    const rep = JSON.parse(fs.readFileSync(repOf(dir, task), 'utf8'));
    assert.equal(rep.verdict, 'fail', rep.notes);
    assert.match(rep.notes, /bi sinh lai/);
  } finally {
    cleanup(dir);
  }
});

test('H7 #987 commit=<sha>: grok audit commit do trong worktree tam (khong can cay chinh sach), auditedHead = sha, worktree tam bi go', async () => {
  const { dir, cfg, task, head } = repo();
  try {
    commitFile(dir, 'AGENTS.md', 'goc\n');
    const head2 = commitFile(dir, 'b.txt', 'b\n');
    assert.notEqual(head2, head);
    writeFile(path.join(dir, 'a.txt'), 'cay chinh dang ban\n');   // cay chinh khac HEAD: voi commit=<sha> khong duoc chan
    // hook sinh lai AGENTS.md duoc H6/H10/H12 phu; o day chi kiem worktree tam (commit audit la commit init, chua co AGENTS.md)
    const fake = fakeGrok({ sh: 'pwd -P > "$D/pwd.txt"; git rev-parse HEAD > "$D/head.txt"' });
    await withGrok(fake, () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok', commit: head }));
    const argv = fake.argv();
    const wt = fs.readFileSync(path.join(fake.d, 'pwd.txt'), 'utf8').trim();
    // worktree tam da bi go (khong realpath duoc): so ten thu muc, pwd -P va --cwd co the khac tien to /var vs /private/var
    assert.match(path.basename(wt), /^agpm-grok-/, 'grok phai chay trong worktree tam, khong phai cay chinh');
    assert.equal(path.basename(argv[argv.indexOf('--cwd') + 1]), path.basename(wt), '--cwd phai la worktree tam');
    assert.equal(fs.readFileSync(path.join(fake.d, 'head.txt'), 'utf8').trim(), head, 'worktree tam o dung commit chi dinh');
    assert.match(argv.slice(7).join('\n'), new RegExp(head));
    assert.equal(fs.existsSync(wt), false, 'worktree tam phai bi go sau audit');
    assert.doesNotMatch(execFileSync('git', ['worktree', 'list'], { cwd: dir, encoding: 'utf8' }), /agpm-grok/);
    const rep = JSON.parse(fs.readFileSync(repOf(dir, task), 'utf8'));
    assert.equal(rep.verdict, 'pass', rep.notes);
    assert.equal(rep.auditedHead, head);
    assert.equal(disk(cfg, task).dispatches.at(-1).auditedHead, head);
    assert.equal(fs.readFileSync(path.join(dir, 'a.txt'), 'utf8'), 'cay chinh dang ban\n', 'cay chinh khong bi dong');
    await call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head, notes: 'ok' });
    assert.equal(disk(cfg, task).verdicts.audit.auditedHead, head);
  } finally {
    cleanup(dir);
  }
});

test('H8 #987 commit=<sha>: sha khong phai commit / khong ton tai / khong phai sha: tu choi, grok khong chay; file code doi trong worktree tam van fail', async () => {
  const { dir, cfg, task, head } = repo();
  const fake = fakeGrok();
  try {
    for (const bad of ['0'.repeat(40), 'khong-co-nhanh-nay', '--help', `${head}; touch pwned`, 42]) {
      await withGrok(fake, () => assert.rejects(call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok', commit: bad }), /commit/, String(bad)));
    }
    assert.equal(grokRan(fake), false);
    assert.equal((disk(cfg, task).dispatches || []).length, 0);
    assert.equal(fs.existsSync(repOf(dir, task)), false);
    // tag/nhanh chi cho phep khi phan giai ra DUNG mot commit; auditedHead luon la sha40 da phan giai
    execFileSync('git', ['tag', 'diem-audit'], { cwd: dir });
    await withGrok(fakeGrok(), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok', commit: 'diem-audit' }));
    assert.equal(JSON.parse(fs.readFileSync(repOf(dir, task), 'utf8')).auditedHead, head);
    // grok sua file code trong worktree tam => van fail (khong chi bo qua file sinh tu dong)
    await withGrok(fakeGrok({ sh: 'echo doi >> a.txt' }), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok', commit: head }));
    const rep = JSON.parse(fs.readFileSync(repOf(dir, task), 'utf8'));
    assert.equal(rep.verdict, 'fail');
    assert.match(rep.notes, /cay lam viec doi trong luc audit/);
  } finally {
    cleanup(dir);
  }
});
