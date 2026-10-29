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
// #629: builder mac dinh lay tu DEVKIT_AGENT_ID; test khong phu thuoc agent dang chay no (vd Antigravity).
delete process.env.DEVKIT_AGENT_ID;

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
// Bao cao pass cua auditor cho dung head (pm_verdict chi ghi auditedHead khi co no, AH6).
const passReport = (dir, task, sha) =>
  writeFile(path.join(dir, '.antigravity-pm', 'tasks', task.id, 'audit-agent.json'), JSON.stringify({ verdict: 'pass', reviewer: 'antigravity', auditedHead: sha }));
const auditOf = (cfg, task) => JSON.parse(fs.readFileSync(taskFile(cfg, task.id), 'utf8')).verdicts?.audit;

test('AH1 task chi audit: pm_verdict audit pass voi auditedHead ghi verdicts.audit.auditedHead', async () => {
  const { dir, cfg, task } = auditOnlyTask();
  try {
    passReport(dir, task, SHA);
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
    passReport(dir, task, sha);
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

// #629 (review context sach 29/10 sau merge #609): pm_verdict audit pass + auditedHead phai dua tren bao cao that cua auditor
// (audit-agent.json cua dung task, viet sau lan giao audit, verdict pass, cung auditedHead, reviewer khac builder) — PM khong tu
// ghi pass cho cay chua ai audit (dispatch roi bo qua ket qua). Moi ca bi tu choi thi KHONG ghi gi (gate DevKit exit 2).
test('AH6 #629: auditedHead chi ghi khi audit-agent.json cua Antigravity pass dung head', async () => {
  const { dir, cfg, task } = auditOnlyTask();
  const rep = path.join(dir, '.antigravity-pm', 'tasks', task.id, 'audit-agent.json');
  const pass = (a) => verdict({ project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: SHA, ...a });
  const saved = process.env.DEVKIT_AGENT_ID;
  delete process.env.DEVKIT_AGENT_ID;
  try {
    // 1. verdict gia: khong co audit-agent.json
    await assert.rejects(pass(), /audit-agent\.json/);
    // 2. task_id khong ton tai
    await assert.rejects(pass({ taskId: 'T9999-khong-co' }), /T9999/);
    // 3. auditor bao cao fail
    writeFile(rep, JSON.stringify({ verdict: 'fail', reviewer: 'antigravity', auditedHead: SHA }));
    await assert.rejects(pass(), /verdict/);
    // 4. auditor audit head khac
    writeFile(rep, JSON.stringify({ verdict: 'pass', reviewer: 'antigravity', auditedHead: 'c'.repeat(40) }));
    await assert.rejects(pass(), /auditedHead/);
    // 5. thieu reviewer (reviewer = builder: AH8 — ghi ket luan nhung khong auditedHead)
    writeFile(rep, JSON.stringify({ verdict: 'pass', auditedHead: SHA }));
    await assert.rejects(pass(), /reviewer/);
    // bao cao cu hon lan giao audit gan nhat (bao cao cua lan truoc)
    writeFile(rep, JSON.stringify({ verdict: 'pass', reviewer: 'antigravity', auditedHead: SHA }));
    fs.utimesSync(rep, new Date(0), new Date(0));
    await assert.rejects(pass(), /cu hon lan giao audit/);
    assert.equal(auditOf(cfg, task), undefined);
    // doi chung: bao cao that, auditedHead trong notes
    writeFile(rep, JSON.stringify({ verdict: 'pass', reviewer: 'antigravity', notes: `ok\nauditedHead: ${SHA}` }));
    await pass();
    assert.equal(auditOf(cfg, task).auditedHead, SHA);
  } finally {
    if (saved === undefined) delete process.env.DEVKIT_AGENT_ID; else process.env.DEVKIT_AGENT_ID = saved;
    cleanup(dir);
  }
});

// #629 review: (a) notes ghi auditedHead KHAC tham so -> tu choi (gate doc ca hai, sha trong notes chua ai audit);
// (b) task da giao implement cho Antigravity -> Antigravity la builder, bao cao reviewer=antigravity khong phai duyet cheo.
test('AH7 #629: notes lech tham so auditedHead, va Antigravity vua build vua audit, deu bi tu choi', async () => {
  const { dir, cfg, task } = auditOnlyTask();
  const rep = path.join(dir, '.antigravity-pm', 'tasks', task.id, 'audit-agent.json');
  try {
    writeFile(rep, JSON.stringify({ verdict: 'pass', reviewer: 'antigravity', auditedHead: SHA }));
    await assert.rejects(verdict({ project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: SHA,
      notes: `ok\nauditedHead: ${'d'.repeat(40)}` }), /notes/);
    // nhieu dong `auditedHead:`: dong thu hai lech tham so cung bi tu choi (gate co the doc dong khac dong dau)
    await assert.rejects(verdict({ project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: SHA,
      notes: `ok\nauditedHead: ${SHA}\nauditedHead: ${'e'.repeat(40)}` }), /notes/);
    // khoang trang ngoai [ \t\n\r\f\v] (NBSP): ca hai ben deu khong coi la auditedHead, khong lech
    await assert.rejects(verdict({ project: dir, taskId: task.id, kind: 'audit', verdict: 'pass',
      notes: `ok\nauditedHead: ${SHA}\nauditedHead: ${'f'.repeat(40)}` }), /audit-agent\.json ghi auditedHead/);
    assert.equal(auditOf(cfg, task), undefined);
  } finally {
    cleanup(dir);
  }
});

// #629 case 5 reviewer = builder: luong /giao (Antigravity build roi audit) khong ket — ket luan audit van ghi, nhung KHONG co
// auditedHead (ca truong lan dong `auditedHead:` trong notes, push_gate doc ca hai) nen gate DevKit exit 2 voi test bi sua.
test('AH8 #629: reviewer trung builder — ghi ket luan, khong ghi auditedHead, notes bi go dong auditedHead', async () => {
  const saved = process.env.DEVKIT_AGENT_ID;
  const cases = [
    { env: undefined, reviewer: 'claude', implement: false },          // builder mac dinh claude
    { env: 'antigravity', reviewer: 'Antigravity', implement: false }, // DEVKIT_AGENT_ID, khac hoa thuong
    { env: undefined, reviewer: 'antigravity', implement: true },      // da giao implement: Antigravity la builder
  ];
  try {
    for (const c of cases) {
      const { dir, cfg, task } = auditOnlyTask();
      try {
        if (c.env === undefined) delete process.env.DEVKIT_AGENT_ID; else process.env.DEVKIT_AGENT_ID = c.env;
        if (c.implement) recordDispatch(cfg, loadTask(cfg, task.id), { kind: 'implement', conversationId: 'c-impl', headCommit: null });
        writeFile(path.join(dir, '.antigravity-pm', 'tasks', task.id, 'audit-agent.json'),
          JSON.stringify({ verdict: 'pass', reviewer: c.reviewer, auditedHead: SHA }));
        const out = await verdict({ project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', auditedHead: SHA, notes: `ok\nauditedHead: ${SHA}` });
        const a = auditOf(cfg, task);
        assert.equal(a.verdict, 'pass', JSON.stringify(c));
        assert.equal(a.auditedHead, undefined, JSON.stringify(c));
        assert.doesNotMatch(a.notes, /auditedHead:\s*[0-9a-f]{40}/, JSON.stringify(c));
        assert.match(out, /trung builder/);
      } finally {
        cleanup(dir);
      }
    }
  } finally {
    if (saved === undefined) delete process.env.DEVKIT_AGENT_ID; else process.env.DEVKIT_AGENT_ID = saved;
  }
});
