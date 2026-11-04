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
  execFileSync('git', ['branch', '-M', 'dev'], { cwd: dir });   // 04/11: khong co nhanh dich -> grok PASS khong tu ghi verdict (luong pm_verdict cu)
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
  execFileSync('git', ['branch', '-M', 'dev'], { cwd: dir });   // 04/11: khong co nhanh dich -> grok PASS khong tu ghi verdict (luong pm_verdict cu)
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
  execFileSync('git', ['branch', '-M', 'dev'], { cwd: dir });   // 04/11: khong co nhanh dich -> grok PASS khong tu ghi verdict (luong pm_verdict cu)
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

// 04/11 (khong buoc nguoi): grok PASS + khong loi -> PM tu ghi verdicts.audit (pass, reviewer grok, actor pm, auditedHead) NGAY SAU lan
// giao; dung khuon push_gate.audit_reviewer(legacy=False) doc: verdicts.audit.reviewer grok + lan audit gan nhat trong dispatches la grok.
// Prompt grok so voi merge-base(nhanh dich, head) va liet ke file da co bi sua/xoa: task chi-audit tao tren worktree PR co baseCommit = head.
function repoPr() {
  const dir = tmpProject({ projectName: 'grok-audit-pr', testCommand: 'echo ok' });
  const g = (...a) => execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', ...a], { cwd: dir, encoding: 'utf8' }).trim();
  g('init', '-q', '-b', 'main');
  writeFile(path.join(dir, '.gitignore'), '.antigravity-pm/\n');
  writeFile(path.join(dir, 'tests', 'old.test.js'), 'assert(1)\n');
  writeFile(path.join(dir, 'a.txt'), 'a\n');
  g('add', '-A'); g('commit', '-qm', 'init');
  const mb = g('rev-parse', 'HEAD');
  g('checkout', '-q', '-b', 'feat');
  writeFile(path.join(dir, 'tests', 'old.test.js'), 'assert(2)\n');
  writeFile(path.join(dir, 'new.txt'), 'n\n');
  g('add', '-A'); g('commit', '-qm', 'PR sua test');
  const head = g('rev-parse', 'HEAD');
  const cfg = loadConfig(dir);
  const task = createTask(cfg, sampleTaskArgs());   // task chi-audit: baseCommit = head PR
  return { dir, cfg, task, head, mb };
}

test('AV1 grok PASS: PM tu ghi verdicts.audit pass (reviewer grok, auditedHead) + auditHistory ngay sau lan giao, khong can pm_verdict', async () => {
  const { dir, cfg, task, head } = repo();
  execFileSync('git', ['branch', '-M', 'main'], { cwd: dir });   // nhanh dich co that, khong phu thuoc init.defaultBranch cua may
  try {
    const out = await withGrok(fakeGrok(), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    const t = disk(cfg, task);
    const a = t.verdicts.audit;
    assert.equal(a.verdict, 'pass');
    assert.equal(a.reviewer, 'grok');
    assert.equal(a.auditedHead, head);
    assert.deepEqual(t.verdicts.auditHistory.map((h) => [h.auditedHead, h.reviewer]), [[head, 'grok']]);
    const d = t.dispatches.filter((x) => x.kind === 'audit').at(-1);
    assert.equal(d.agent, 'grok');
    assert.equal(d.auditBase, head, 'pham vi grok da xem: merge-base(main, head) = head (khong co commit PR)');
    assert.deepEqual(d.edited, []);
    assert.ok(Date.parse(d.at) <= Date.parse(a.at), 'lan giao ghi truoc ket luan (audit_reviewer doc lan giao gan nhat)');
    const h = (t.history || []).filter((x) => x.event === 'verdict_audit').at(-1);
    assert.equal(h?.actor, 'pm');
    assert.match(out, /auditedHead = [0-9a-f]{40}/);
  } finally {
    cleanup(dir);
  }
});

test('AV2 grok REVISE / exit khac 0 / HEAD doi / cay ban: KHONG ghi verdicts.audit', async () => {
  for (const opt of [{ out: 'VERDICT: REVISE\n' }, { code: 3 }, { sh: 'echo doi >> a.txt' },
    { sh: 'git -c user.name=t -c user.email=t@t commit -qm x --allow-empty' }]) {
    const { dir, cfg, task } = repo();
    try {
      await withGrok(fakeGrok(opt), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
      const t = disk(cfg, task);
      assert.equal(t.dispatches.at(-1).verdict, 'fail', JSON.stringify(opt));
      assert.equal(t.verdicts?.audit, undefined, JSON.stringify(opt));
      assert.equal(t.verdicts?.auditHistory, undefined, JSON.stringify(opt));
    } finally {
      cleanup(dir);
    }
  }
});

test('AV3 nguoi goi PM la grok: tu choi truoc khi chay, khong ghi verdict', async () => {
  const { dir, cfg, task } = repo();
  try {
    await withEnv({ GROK_SESSION_ID: 's9' }, () => withGrok(fakeGrok(), () => assert.rejects(
      call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }), /tu duyet/)));
    assert.equal(disk(cfg, task).verdicts?.audit, undefined);
  } finally {
    cleanup(dir);
  }
});

test('AV4 task chi-audit tren worktree PR (baseCommit = head): prompt grok so voi merge-base(main, head) va liet ke test da co bi sua', async () => {
  const { dir, task, head, mb } = repoPr();
  assert.equal(task.baseCommit, head, 'tien de: task tao tren head PR');
  const fake = fakeGrok();
  try {
    await withGrok(fake, () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    const prompt = fake.argv().slice(7).join('\n');
    assert.match(prompt, new RegExp(`git diff ${mb} ${head}`));
    assert.match(prompt, /tests\/old\.test\.js/);
    assert.match(prompt, /bo qua va ghi lai la phat hien/);
    assert.doesNotMatch(prompt, /brief\.md/, 'audit pham vi day du: khong tro toi ho so tac gia');
    const d = disk(loadConfig(dir), task).dispatches.at(-1);
    assert.equal(d.auditBase, mb);
    assert.deepEqual(d.edited, ['tests/old.test.js'], 'chi file da co o goc bi sua/xoa, khong co new.txt');
    assert.doesNotMatch(prompt, /new\.txt.*da co/, 'file moi khong nam trong danh sach file da co bi sua');
  } finally {
    cleanup(dir);
  }
});

test('AV5 grok PASS nhung pm_dispatch co message (chu tac gia trong prompt) hoac khong co nhanh dich: KHONG tu ghi verdict', async () => {
  {
    const { dir, cfg, task } = repo();
    try {
      const out = await withGrok(fakeGrok(), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok', message: 'chi xem a.txt' }));
      assert.equal(disk(cfg, task).dispatches.at(-1).verdict, 'pass');
      assert.equal(disk(cfg, task).dispatches.at(-1).auditBase, undefined, 'co message: khong ghi pham vi, gate khong tra thang');
      assert.equal(disk(cfg, task).verdicts?.audit, undefined);
      assert.match(out, /Khong tu ghi verdict/);
    } finally {
      cleanup(dir);
    }
  }
  const dir = tmpProject({ projectName: 'grok-audit-notrunk', testCommand: 'echo ok' });
  try {
    execFileSync('git', ['init', '-q', '-b', 'dev'], { cwd: dir });
    writeFile(path.join(dir, '.gitignore'), '.antigravity-pm/\n');
    writeFile(path.join(dir, 'a.txt'), 'a\n');
    execFileSync('git', ['add', '-A'], { cwd: dir });
    execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'init'], { cwd: dir });
    const cfg = loadConfig(dir);
    const task = createTask(cfg, sampleTaskArgs());
    await withGrok(fakeGrok(), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    assert.equal(disk(cfg, task).verdicts?.audit, undefined, 'khong co main/master/trunk: khong tu ghi');
  } finally {
    cleanup(dir);
  }
});

test('AV6 sau khi grok PASS tu ghi verdict: pm_verdict voi bao cao bi sua bi tu choi va khong doi gi', async () => {
  const { dir, cfg, task, head } = repo();
  execFileSync('git', ['branch', '-M', 'main'], { cwd: dir });
  try {
    await withGrok(fakeGrok(), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    const before = disk(cfg, task).verdicts;
    assert.equal(before.audit.auditedHead, head);
    const rep = repOf(dir, task);
    fs.writeFileSync(rep, `${fs.readFileSync(rep, 'utf8')} `);
    await assert.rejects(call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head }), /sha256/);
    assert.deepEqual(disk(cfg, task).verdicts, before);
  } finally {
    cleanup(dir);
  }
});

test('AV7 sau khi grok PASS tu ghi verdict: pm_verdict cua phien grok (tu duyet) ghi de verdict KHONG auditedHead, khong them history', async () => {
  const { dir, cfg, task, head } = repo();
  execFileSync('git', ['branch', '-M', 'main'], { cwd: dir });
  try {
    await withGrok(fakeGrok(), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    assert.equal(disk(cfg, task).verdicts.auditHistory.length, 1);
    const out = await withEnv({ GROK_SESSION_ID: 's7' },
      () => call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head }));
    assert.match(out, /trung builder/);
    const t = disk(cfg, task);
    assert.equal(t.verdicts.audit.auditedHead, undefined, 'tu duyet: verdict hien tai khong con head -> audited_head None');
    assert.equal(t.verdicts.auditHistory.length, 1);
  } finally {
    cleanup(dir);
  }
});

test('AV8 sau khi grok PASS tu ghi verdict: audit-agent.json bi ghi lai voi reviewer khac grok -> pm_verdict tu choi, khong doi gi', async () => {
  const { dir, cfg, task, head } = repo();
  execFileSync('git', ['branch', '-M', 'main'], { cwd: dir });
  try {
    await withGrok(fakeGrok(), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    const before = disk(cfg, task).verdicts;
    fs.writeFileSync(repOf(dir, task), JSON.stringify({ verdict: 'pass', reviewer: 'antigravity', auditedHead: head }));
    await assert.rejects(call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head }), /grok/);
    assert.deepEqual(disk(cfg, task).verdicts, before);
  } finally {
    cleanup(dir);
  }
});

test('AV9 sau khi grok PASS tu ghi verdict: DEVKIT_AGENT_ID=codex + GROK_* goi pm_verdict = trung builder, verdict mat auditedHead', async () => {
  const { dir, cfg, task, head } = repo();
  execFileSync('git', ['branch', '-M', 'main'], { cwd: dir });
  try {
    await withGrok(fakeGrok(), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    const out = await withEnv({ DEVKIT_AGENT_ID: 'codex', GROK_SESSION_ID: 'g-9' },
      () => call('pm_verdict', { project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: head }));
    assert.match(out, /trung builder/);
    const t = disk(cfg, task);
    assert.equal(t.verdicts.audit.auditedHead, undefined);
    assert.equal(t.verdicts.auditHistory.length, 1, 'chi con ban ghi cua lan grok PM tu chay');
  } finally {
    cleanup(dir);
  }
});

test('AV10 audit pham vi day du: prompt khong co tieu de / brief / DoD cua tac gia; co message thi van co. PASS roi REVISE cung head: lan sau khong mang pham vi', async () => {
  const { dir, cfg, task } = repoPr();
  const fake = fakeGrok();
  try {
    await withGrok(fake, () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    const scoped = fake.argv().slice(7).join('\n');
    assert.doesNotMatch(scoped, new RegExp(sampleTaskArgs().title));
    assert.doesNotMatch(scoped, /brief\.md|Definition of Done/);
    assert.equal(disk(cfg, task).dispatches.at(-1).verdict, 'pass');
    assert.ok(disk(cfg, task).dispatches.at(-1).auditBase);
    await withGrok(fakeGrok({ out: 'VERDICT: REVISE\n' }), () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok' }));
    const d = disk(cfg, task).dispatches.at(-1);
    assert.equal(d.verdict, 'fail');
    assert.equal(d.auditBase, undefined, 'lan fail khong ghi pham vi: audit_scope cua gate doi lan cuoi pass');
    const fake2 = fakeGrok();
    await withGrok(fake2, () => call('pm_dispatch', { project: dir, taskId: task.id, kind: 'audit', agent: 'grok', message: 'soi them a.txt' }));
    assert.match(fake2.argv().slice(7).join('\n'), new RegExp(sampleTaskArgs().title), 'co message: prompt task day du nhu cu');
  } finally {
    cleanup(dir);
  }
});
