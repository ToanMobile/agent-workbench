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
    [{ DEVKIT_AGENT_ID: 'codex', GROK_SESSION_ID: 's' }, 'codex'],
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
