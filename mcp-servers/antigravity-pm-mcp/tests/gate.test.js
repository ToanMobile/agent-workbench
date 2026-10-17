// Cong nghiem thu la thu duy nhat khong duoc phep lam mem => test ky nhat o day.
import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { loadConfig, withGateSnapshot } from '../src/config.js';
import {
  createTask, recordVerdict, recordRun, recordProof, recordDispatch, markRework, gate, accept, contractPaths, loadTask,
  updateTask,
} from '../src/tasks.js';
import { gateCtx } from '../src/worktree.js';
import { TOOLS_BY_NAME } from '../src/tools.js';
import { tmpProject, cleanup, writeFile, sampleTaskArgs, PNG_1PX, tick } from './helpers.js';

// Luat bat buoc: thay doi phai kem file test. Moi test "phai dat" deu phai dua ctx nay vao.
const CO_FILE_TEST = { changedFiles: ['src/Kinh.kt', 'src/test/java/KinhTest.kt'] };
// ...va file test do phai nam trong files_changed agent khai.
const KHAI_DU = ['src/Kinh.kt', 'src/test/java/KinhTest.kt'];
// Bang chung test da chay that (src/evidence.js). Run khong co evidence = khong xanh.
const EV_OK = { source: 'stdout', weak: true, noop: false, ok: true, reason: 'test' };

function setupTask(cfgOver = {}) {
  const dir = tmpProject({ testCommand: 'echo ok', ...cfgOver });
  const cfg = loadConfig(dir);
  const task = createTask(cfg, sampleTaskArgs());
  return { dir, cfg, task };
}

/** Dua task ve trang thai "du bang chung" theo tung buoc. */
function makeEverythingGreen(cfg, task) {
  const p = contractPaths(cfg, task);
  writeFile(p.plan, '# Ke hoach\n- Buoc 1');
  recordVerdict(cfg, task, { kind: 'plan', verdict: 'pass' });
  recordDispatch(cfg, task, { kind: 'implement', conversationId: 'c-test' });
  tick();
  writeFile(p.result, JSON.stringify({ phase: 'IMPLEMENT', summary: 'da lam', files_changed: KHAI_DU }));
  recordVerdict(cfg, task, { kind: 'audit', verdict: 'pass' });
  recordVerdict(cfg, task, { kind: 'review', verdict: 'pass' });
  recordRun(cfg, task, { kind: 'test', command: 'echo ok', exitCode: 0, durationMs: 10, evidence: EV_OK });
  const img = path.join(p.proofDir, 'shot.png');
  writeFile(img, PNG_1PX);
  recordProof(cfg, task, { label: 'man hinh xac nhan', provider: 'adb', file: img, bytes: PNG_1PX.length });
  return task;
}

test('task moi thi cong chan chan het, va liet ke du thu con thieu', () => {
  const { dir, cfg, task } = setupTask();
  const g = gate(cfg, task, CO_FILE_TEST);
  assert.equal(g.ok, false);
  const joined = g.missing.join('\n');
  for (const phrase of ['plan.md', 'chot ke hoach', 'result.json', 'AUDIT', 'CODE REVIEW', 'test', 'anh nghiem thu']) {
    assert.ok(joined.includes(phrase), `thieu canh bao ve "${phrase}" trong:\n${joined}`);
  }
  assert.throws(() => accept(cfg, task, CO_FILE_TEST), /CHUA DU BANG CHUNG/);
  cleanup(dir);
});

test('du het bang chung thi nghiem thu duoc', () => {
  const { dir, cfg, task } = setupTask();
  makeEverythingGreen(cfg, task);
  const g = gate(cfg, task, CO_FILE_TEST);
  assert.equal(g.ok, true, `van con thieu: ${g.missing.join(' | ')}`);
  const accepted = accept(cfg, task, CO_FILE_TEST);
  assert.equal(accepted.phase, 'ACCEPTED');
  assert.ok(accepted.acceptedAt);
  cleanup(dir);
});

test('test do (exit != 0) thi KHONG duoc nghiem thu', () => {
  const { dir, cfg, task } = setupTask();
  makeEverythingGreen(cfg, task);
  task.runs = task.runs.filter((r) => r.kind !== 'test');
  recordRun(cfg, task, { kind: 'test', command: './gradlew test', exitCode: 1, durationMs: 10 });
  const g = gate(cfg, task, CO_FILE_TEST);
  assert.equal(g.ok, false);
  assert.ok(g.missing.some((m) => m.includes('exit 0')), g.missing.join(' | '));
  cleanup(dir);
});

test('test qua han thi khong tinh la xanh', () => {
  const { dir, cfg, task } = setupTask();
  makeEverythingGreen(cfg, task);
  task.runs = [];
  recordRun(cfg, task, { kind: 'test', command: './gradlew test', exitCode: 0, durationMs: 10, timedOut: true });
  assert.equal(gate(cfg, task, CO_FILE_TEST).ok, false);
  cleanup(dir);
});

test('thieu anh nghiem thu thi khong nghiem thu duoc, du code xanh', () => {
  const { dir, cfg, task } = setupTask();
  makeEverythingGreen(cfg, task);
  task.proofs = [];
  const g = gate(cfg, task, CO_FILE_TEST);
  assert.equal(g.ok, false);
  assert.ok(g.missing.some((m) => m.includes('anh nghiem thu')));
  cleanup(dir);
});

test('anh bi xoa khoi dia thi khong con tinh la bang chung', () => {
  const { dir, cfg, task } = setupTask();
  makeEverythingGreen(cfg, task);
  fs.rmSync(task.proofs[0].file);
  assert.equal(gate(cfg, task, CO_FILE_TEST).ok, false);
  cleanup(dir);
});

test('rework huy bang chung cua vong truoc: audit/review/test/anh deu khong con tinh', () => {
  const { dir, cfg, task } = setupTask();
  makeEverythingGreen(cfg, task);
  assert.equal(gate(cfg, task, CO_FILE_TEST).ok, true);

  markRework(cfg, task, 'thieu xu ly truong hop kinh dang keo');
  assert.equal(task.round, 1);
  assert.equal(task.phase, 'IMPLEMENT');
  assert.equal(task.verdicts.audit, undefined);
  assert.equal(task.verdicts.review, undefined);
  // Plan van con hieu luc (ke hoach chua bi bac).
  assert.equal(task.verdicts.plan.verdict, 'pass');

  const g = gate(cfg, task, CO_FILE_TEST);
  assert.equal(g.ok, false);
  const joined = g.missing.join('\n');
  assert.ok(joined.includes('vong 1'), joined);
  assert.ok(joined.includes('result.json cu hon lan rework') || joined.includes('result.json'), joined);
  cleanup(dir);
});

test('sau rework: result.json ghi lai + bang chung moi thi nghiem thu lai duoc', () => {
  const { dir, cfg, task } = setupTask();
  makeEverythingGreen(cfg, task);
  markRework(cfg, task, 'sua lai di');

  const p = contractPaths(cfg, task);
  writeFile(p.result, JSON.stringify({ phase: 'IMPLEMENT', summary: 'da sua theo phat hien', files_changed: KHAI_DU }));
  // Agent that mat vai giay/phut moi bao cao lai; test chay trong 1ms nen phai gia lap moc thoi gian.
  const later = new Date(Date.now() + 2000);
  fs.utimesSync(p.result, later, later);
  recordVerdict(cfg, task, { kind: 'audit', verdict: 'pass' });
  recordVerdict(cfg, task, { kind: 'review', verdict: 'pass' });
  recordRun(cfg, task, { kind: 'test', command: 'echo ok', exitCode: 0, durationMs: 5, evidence: EV_OK });
  const img = writeFile(path.join(p.proofDir, 'shot2.png'), PNG_1PX);
  recordProof(cfg, task, { label: 'lan 2', provider: 'adb', file: img, bytes: PNG_1PX.length });

  const g = gate(cfg, task, CO_FILE_TEST);
  assert.equal(g.ok, true, g.missing.join(' | '));
  cleanup(dir);
});

test('rework rong feedback thi bi chan', () => {
  const { dir, cfg, task } = setupTask();
  assert.throws(() => markRework(cfg, task, '   '), /feedback rong/);
  cleanup(dir);
});

test('project yeu cau 2 anh thi 1 anh la chua du', () => {
  const { dir, cfg, task } = setupTask({ proof: { require: 2 } });
  makeEverythingGreen(cfg, task);
  assert.equal(gate(cfg, task, CO_FILE_TEST).ok, false);
  const p = contractPaths(cfg, task);
  const img = writeFile(path.join(p.proofDir, 'shot-b.png'), PNG_1PX);
  recordProof(cfg, task, { label: 'anh 2', provider: 'adb', file: img, bytes: PNG_1PX.length });
  assert.equal(gate(cfg, task, CO_FILE_TEST).ok, true);
  cleanup(dir);
});

test('ho so task doc lai duoc tu dia (khong mat trang thai giua cac phien)', () => {
  const { dir, cfg, task } = setupTask();
  makeEverythingGreen(cfg, task);
  const again = loadTask(loadConfig(dir), task.id);
  assert.equal(again.id, task.id);
  assert.equal(again.verdicts.review.verdict, 'pass');
  assert.equal(gate(loadConfig(dir), again, CO_FILE_TEST).ok, true);
  cleanup(dir);
});

test('KHONG duoc nghiem thu bang result.json cua giai doan PLAN (agent khong lam gi)', () => {
  const { dir, cfg, task } = setupTask();
  const p = contractPaths(cfg, task);
  // Agent lap ke hoach xong, bao cao phase=PLAN.
  writeFile(p.plan, '# Ke hoach');
  writeFile(p.result, JSON.stringify({ phase: 'PLAN', summary: 'se lam', files_to_change: ['a.kt'] }));
  recordVerdict(cfg, task, { kind: 'plan', verdict: 'pass' });
  // PM giao trien khai...
  recordDispatch(cfg, task, { kind: 'implement' });
  // ...nhung agent KHONG lam gi. PM (hoac mot PM lo la) van chay test tren code cu va chup anh.
  recordVerdict(cfg, task, { kind: 'audit', verdict: 'pass' });
  recordVerdict(cfg, task, { kind: 'review', verdict: 'pass' });
  recordRun(cfg, task, { kind: 'test', command: 'echo ok', exitCode: 0, durationMs: 5 });
  const img = writeFile(path.join(p.proofDir, 'shot.png'), PNG_1PX);
  recordProof(cfg, task, { label: 'anh', provider: 'adb', file: img, bytes: PNG_1PX.length });

  const g = gate(cfg, task, CO_FILE_TEST);
  assert.equal(g.ok, false, 'khong duoc nghiem thu khi agent chua trien khai');
  const joined = g.missing.join('\n');
  assert.ok(joined.includes('van la bao cao "PLAN"'), joined);
  assert.ok(joined.includes('TRUOC luc giao trien khai'), joined);
  assert.throws(() => accept(cfg, task, CO_FILE_TEST), /CHUA DU BANG CHUNG/);
  cleanup(dir);
});

test('result.json thieu truong phase cung khong duoc tinh la da trien khai', () => {
  const { dir, cfg, task } = setupTask();
  makeEverythingGreen(cfg, task);
  const p = contractPaths(cfg, task);
  writeFile(p.result, JSON.stringify({ summary: 'xong roi ma' }));
  assert.equal(gate(cfg, task, CO_FILE_TEST).ok, false);
  assert.ok(gate(cfg, task, CO_FILE_TEST).missing.join('\n').includes('khong ro phase'));
  cleanup(dir);
});

test('agent trien khai THAT sau khi duoc giao thi nghiem thu duoc', () => {
  const { dir, cfg, task } = setupTask();
  const p = contractPaths(cfg, task);
  writeFile(p.plan, '# Ke hoach');
  recordVerdict(cfg, task, { kind: 'plan', verdict: 'pass' });
  recordDispatch(cfg, task, { kind: 'implement' });

  // Agent bao cao SAU khi duoc giao (test chay trong 1ms nen phai gia lap moc thoi gian).
  writeFile(p.result, JSON.stringify({ phase: 'IMPLEMENT', summary: 'da sua', files_changed: KHAI_DU }));
  const later = new Date(Date.now() + 2000);
  fs.utimesSync(p.result, later, later);

  recordVerdict(cfg, task, { kind: 'audit', verdict: 'pass' });
  recordVerdict(cfg, task, { kind: 'review', verdict: 'pass' });
  recordRun(cfg, task, { kind: 'test', command: 'echo ok', exitCode: 0, durationMs: 5, evidence: EV_OK });
  const img = writeFile(path.join(p.proofDir, 'shot.png'), PNG_1PX);
  recordProof(cfg, task, { label: 'anh', provider: 'adb', file: img, bytes: PNG_1PX.length });

  const g = gate(cfg, task, CO_FILE_TEST);
  assert.equal(g.ok, true, g.missing.join(' | '));
  cleanup(dir);
});

// ---------------------------------------------------------------- #22 file DA COMMIT ke tu commit goc
// Worker tu `git commit` => `git status` sach (cay lam viec rong). Cong phai do ca file da commit ke tu baseCommit:
// commitPolicy=forbid chan commit cua task, soi lint va moc "sua file lan cuoi" khong duoc mu voi file da commit.

function gitRepo(config = {}, files = {}) {
  const dir = tmpProject({ testCommand: 'echo ok', ...config });
  const git = (...a) => execFileSync('git', a, { cwd: dir, stdio: 'pipe' });
  git('init', '-q');
  git('config', 'user.email', 'test@example.com');
  git('config', 'user.name', 'Test');
  writeFile(path.join(dir, '.gitignore'), '.antigravity-pm/\n');
  for (const [f, c] of Object.entries(files)) writeFile(path.join(dir, f), c);
  git('add', '-A');
  git('commit', '-qm', 'init');
  return dir;
}

/** Sua file roi commit (vai worker trai luat, hoac phien khac dung chung cay). */
function suaVaCommit(dir, files, msg = 'agent tu commit') {
  for (const [f, c] of Object.entries(files)) writeFile(path.join(dir, f), c);
  execFileSync('git', ['add', '-A'], { cwd: dir, stdio: 'pipe' });
  execFileSync('git', ['commit', '-qm', msg], { cwd: dir, stdio: 'pipe' });
}

function khaiResult(cfg, task, filesChanged) {
  writeFile(contractPaths(cfg, task).result, JSON.stringify({ phase: 'IMPLEMENT', summary: 'da lam', files_changed: filesChanged }));
}

const SUA_KINH = { 'src/Kinh.kt': 'class Kinh { fun ha() = 1 }\n', 'src/test/KinhTest.kt': 'class KinhTest\n' };

test('#22 AC1: worker tu git commit khi commitPolicy=forbid => cong CHAN du git status sach; allow thi khong', async () => {
  for (const commitPolicy of ['forbid', 'allow']) {
    const dir = gitRepo({ commitPolicy }, { 'src/Kinh.kt': 'class Kinh\n' });
    const cfg = loadConfig(dir);
    const task = createTask(cfg, sampleTaskArgs());
    khaiResult(cfg, task, Object.keys(SUA_KINH));
    suaVaCommit(dir, SUA_KINH);
    const g = gate(cfg, loadTask(cfg, task.id), await gateCtx(cfg, loadTask(cfg, task.id)));
    const chan = g.missing.find((m) => m.includes('commitPolicy'));
    if (commitPolicy === 'allow') assert.equal(chan, undefined, chan);
    else assert.ok(chan?.includes('src/Kinh.kt') && chan.includes('src/test/KinhTest.kt'), g.missing.join('\n'));
    cleanup(dir);
  }
});

test('#22 AC1: agent doi commitPolicy=allow trong .antigravity-pm.json SAU khi tao task => van CHAN (ban chup luc tao)', async () => {
  const dir = gitRepo({}, { 'src/Kinh.kt': 'class Kinh\n' });
  const task = createTask(loadConfig(dir), sampleTaskArgs());
  writeFile(path.join(dir, '.antigravity-pm.json'), JSON.stringify({ testCommand: 'echo ok', commitPolicy: 'allow' }));
  const cfg = withGateSnapshot(loadConfig(dir), loadTask(loadConfig(dir), task.id));
  khaiResult(cfg, task, Object.keys(SUA_KINH));
  suaVaCommit(dir, SUA_KINH);
  const g = gate(cfg, loadTask(cfg, task.id), await gateCtx(cfg, loadTask(cfg, task.id)));
  assert.ok(g.missing.some((m) => m.includes('commitPolicy=forbid') && m.includes('src/Kinh.kt')), g.missing.join('\n'));
  cleanup(dir);
});

test('#22 AC1: worker commit file KHONG khai (chi khai file test chua commit, khong scopeFiles) => van CHAN, khong chi canh bao', async () => {
  const dir = gitRepo({}, { 'src/Kinh.kt': 'class Kinh\n' });
  const cfg = loadConfig(dir);
  const task = createTask(cfg, sampleTaskArgs());
  recordDispatch(cfg, loadTask(cfg, task.id), { kind: 'implement', conversationId: 'c-test' });
  suaVaCommit(dir, { 'src/Kinh.kt': 'class Kinh { fun ha() = 7 }\n' });
  writeFile(path.join(dir, 'src/test/KinhTest.kt'), 'class KinhTest\n');
  khaiResult(cfg, task, ['src/test/KinhTest.kt']);
  const g = gate(cfg, loadTask(cfg, task.id), await gateCtx(cfg, loadTask(cfg, task.id)));
  assert.ok(g.missing.some((m) => m.includes('commitPolicy=forbid') && m.includes('src/Kinh.kt')), g.missing.join('\n'));
  cleanup(dir);
});

test('#22 AC2: sua file forbiddenPaths — commit hay khong commit deu bi CHAN', async () => {
  for (const commit of [false, true]) {
    const dir = gitRepo({ commitPolicy: 'allow' }, { 'src/Kinh.kt': 'class Kinh\n', 'gradle/libs.versions.toml': 'a=1\n' });
    const cfg = loadConfig(dir);
    const task = updateTask(cfg, createTask(cfg, sampleTaskArgs()), (t) => { t.forbiddenPaths = ['gradle/libs.versions.toml']; });
    const sua = { ...SUA_KINH, 'gradle/libs.versions.toml': 'a=2\n' };
    khaiResult(cfg, task, Object.keys(sua));
    if (commit) suaVaCommit(dir, sua);
    else for (const [f, c] of Object.entries(sua)) writeFile(path.join(dir, f), c);
    const g = gate(cfg, loadTask(cfg, task.id), await gateCtx(cfg, loadTask(cfg, task.id)));
    assert.ok(g.missing.some((m) => m.includes('CAM sua') && m.includes('gradle/libs.versions.toml')), `commit=${commit}: ${g.missing.join('\n')}`);
    cleanup(dir);
  }
});

test('#22 soi lint tren file DA COMMIT: SQL create table trung bi CHAN, guard bi xoa bi CANH BAO', async () => {
  const dir = gitRepo({ commitPolicy: 'allow' }, { 'src/Kinh.kt': 'fun ha(ok: Boolean) {\n  if (!ok) return\n  chay()\n}\n' });
  const cfg = loadConfig(dir);
  const task = createTask(cfg, sampleTaskArgs());
  const sua = {
    'db/schema.sql': 'create table xe (id int);\ncreate table xe (id int);\n',
    'src/Kinh.kt': 'fun ha(ok: Boolean) {\n  chay()\n}\n',
    'src/test/KinhTest.kt': 'class KinhTest\n',
  };
  khaiResult(cfg, task, Object.keys(sua));
  suaVaCommit(dir, sua);
  const ctx = await gateCtx(cfg, loadTask(cfg, task.id));
  assert.ok(ctx.lintBlockers.some((b) => b.includes('db/schema.sql') && b.includes('create table trung')), JSON.stringify(ctx.lintBlockers));
  assert.ok(ctx.lintWarnings.some((w) => w.key === 'guard-xoa:src/Kinh.kt'), ctx.lintWarnings.map((w) => w.key).join(', '));
  assert.ok(gate(cfg, loadTask(cfg, task.id), ctx).missing.some((m) => m.startsWith('Nhan doi noi dung') && m.includes('db/schema.sql')));
  cleanup(dir);
});

/** Agent sua SUA_KINH (KHONG commit) + lam() them + du bang chung PM (plan, audit, review, test xanh sau bao cao, anh). Tra ve ctx da do. */
async function duBangChung(dir, cfg, task, lam = () => {}) {
  const p = contractPaths(cfg, task);
  writeFile(p.plan, '# Ke hoach');
  recordVerdict(cfg, task, { kind: 'plan', verdict: 'pass' });
  recordDispatch(cfg, task, { kind: 'implement', conversationId: 'c-test' });
  tick();
  for (const [f, c] of Object.entries(SUA_KINH)) writeFile(path.join(dir, f), c);
  await lam();
  khaiResult(cfg, task, Object.keys(SUA_KINH));
  tick();
  recordVerdict(cfg, task, { kind: 'audit', verdict: 'pass' });
  recordVerdict(cfg, task, { kind: 'review', verdict: 'pass' });
  recordRun(cfg, task, { kind: 'test', command: 'echo ok', exitCode: 0, durationMs: 5, evidence: EV_OK, startedAt: new Date().toISOString() });
  const img = writeFile(path.join(p.proofDir, 'shot.png'), PNG_1PX);
  recordProof(cfg, task, { label: 'anh', provider: 'adb', file: img, bytes: PNG_1PX.length });
  return gateCtx(cfg, loadTask(cfg, task.id));
}

// #22 AC2 (QA v1): file CAM doi SAU luc giao trien khai => CHINH luat forbiddenPaths CHAN, du task khong khai, moi commitPolicy.
const TOML = 'gradle/libs.versions.toml';
const LAM_CAM = {
  sua: (dir) => writeFile(path.join(dir, TOML), 'a=2\n'),
  'git mv': (dir) => execFileSync('git', ['mv', TOML, 'gradle/x.toml'], { cwd: dir, stdio: 'pipe' }),
};
const camRepo = (config = {}) => gitRepo(config, { 'src/Kinh.kt': 'class Kinh\n', [TOML]: 'a=1\n' });
const datCam = (cfg) => updateTask(cfg, createTask(cfg, sampleTaskArgs()), (t) => { t.forbiddenPaths = [TOML]; });
const chanCam = (g) => g.missing.some((m) => m.includes('CAM sua') && m.includes(TOML));

test('#22 AC2: file CAM doi sau luc giao, KHONG khai (sua / git mv) x forbid/allow x commit/khong => luat forbiddenPaths CHAN, accept tu choi', async () => {
  for (const commitPolicy of ['forbid', 'allow']) for (const commit of [false, true]) for (const [cach, lam] of Object.entries(LAM_CAM)) {
    const ten = `${commitPolicy} commit=${commit} ${cach}`;
    const dir = camRepo({ commitPolicy });
    const cfg = loadConfig(dir);
    const task = datCam(cfg);
    const ctx = await duBangChung(dir, cfg, task, () => { lam(dir); if (commit) suaVaCommit(dir, {}); });
    assert.ok(chanCam(gate(cfg, loadTask(cfg, task.id), ctx)), `${ten}: ${gate(cfg, loadTask(cfg, task.id), ctx).missing.join('\n')}`);
    assert.throws(() => accept(cfg, loadTask(cfg, task.id), ctx), /CAM sua/, ten);
    cleanup(dir);
  }
});

test('#22 AC2: file CAM da ban TRUOC luc giao: khong dong toi / chi bi CAM sau luc giao => CANH BAO; sua tiep / hoan tac ve HEAD => CHAN', async () => {
  // [forbiddenPaths luc giao, TOML ban truoc luc giao?, cac buoc sau luc giao (chuoi = agent ghi TOML, mang = PM pm_plan forbidden),
  // ket qua chan | canh bao | qua]. Duong CAM them SAU luc giao: doi truoc luc them la hop le, doi SAU luc them => CHAN; file da CAM
  // tu luc giao thi them duong moi khong xoa duoc dau vet; go CAM roi them lai thi doi trong luc duoc phep la hop le.
  const CA = {
    'khong dong': [[TOML], true, [], 'canh bao'],
    'cam sau giao': [[], true, [[TOML]], 'canh bao'],
    'cam sau giao roi sua': [[], true, [[TOML], 'a=agent\n'], 'chan'],
    'sua tiep': [[TOML], true, ['a=agent\n'], 'chan'],
    'hoan tac ve HEAD': [[TOML], true, ['a=1\n'], 'chan'],
    'sua file sach roi them thu muc cam': [[TOML], false, ['a=agent\n', [TOML, 'gradle/']], 'chan'],
    'go cam, sua, cam lai': [[TOML], true, [[], 'a=agent\n', [TOML]], 'canh bao'],
    'go cam, hoan tac ve HEAD, cam lai': [[TOML], true, [[], 'a=1\n', [TOML]], 'qua'],
  };
  for (const [ca, [giao, banTruoc, buoc, kq]] of Object.entries(CA)) {
    const dir = camRepo();
    const cfg = loadConfig(dir);
    const task = updateTask(cfg, createTask(cfg, sampleTaskArgs()), (t) => { t.forbiddenPaths = giao; });
    if (banTruoc) writeFile(path.join(dir, TOML), 'a=phien-khac\n');
    const ctx = await duBangChung(dir, cfg, task, async () => {
      for (const b of buoc) {
        if (typeof b === 'string') { writeFile(path.join(dir, TOML), b); continue; }
        await TOOLS_BY_NAME.get('pm_plan').handler({ project: dir, taskId: task.id, content: '# Ke hoach v2', forbidden: b });
        recordVerdict(cfg, loadTask(cfg, task.id), { kind: 'plan', verdict: 'pass' });
      }
    });
    const g = gate(cfg, loadTask(cfg, task.id), ctx);
    const canhBao = g.warnings.some((w) => w.includes('File CAM') && w.includes(TOML));
    if (kq === 'chan') assert.ok(chanCam(g), `${ca}: ${g.missing.join('\n')}`);
    else assert.ok(g.ok && canhBao === (kq === 'canh bao'), `${ca}: ${g.missing.join(' | ')} || ${g.warnings.join(' | ')}`);
    if (ca === 'khong dong') {
      // Da nghiem thu: file CAM doi sau do (PM / phien khac) khong lam task ACCEPTED bao CHUA DAT.
      accept(cfg, loadTask(cfg, task.id), ctx);
      writeFile(path.join(dir, TOML), 'a=sau-nghiem-thu\n');
      assert.ok(!chanCam(gate(cfg, loadTask(cfg, task.id), await gateCtx(cfg, loadTask(cfg, task.id)))));
    }
    cleanup(dir);
  }
});

test('#22 thu tu thoi gian: agent sua + commit file SAU lan test xanh => cong CHAN (test chua chay tren code moi nhat)', async () => {
  const dir = gitRepo({ commitPolicy: 'allow' }, { 'src/Kinh.kt': 'class Kinh\n' });
  const cfg = loadConfig(dir);
  const task = createTask(cfg, sampleTaskArgs());
  // Truoc khi agent len lut sua: du bang chung.
  const ctx0 = await duBangChung(dir, cfg, task);
  const truoc = gate(cfg, loadTask(cfg, task.id), ctx0);
  assert.equal(truoc.ok, true, truoc.missing.join(' | '));
  // Agent sua code SAU lan test xanh roi commit => git status sach.
  tick(20);
  suaVaCommit(dir, { 'src/Kinh.kt': 'class Kinh { fun ha() = 2 }\n' });
  const ctx = await gateCtx(cfg, loadTask(cfg, task.id));
  assert.ok(ctx.lastChangeAt >= fs.statSync(path.join(dir, 'src/Kinh.kt')).mtimeMs, `lastChangeAt=${ctx.lastChangeAt}`);
  const sau = gate(cfg, loadTask(cfg, task.id), ctx);
  assert.ok(sau.missing.some((m) => m.includes('chay TRUOC')), sau.missing.join('\n'));
  cleanup(dir);
});

test('#22 baseCommit dung khuon nhung git khong doc duoc (commit da mat) => CHUA XAC MINH, khong coi la "chua commit gi"', async () => {
  const dir = gitRepo({}, { 'src/Kinh.kt': 'class Kinh\n' });
  const cfg = loadConfig(dir);
  const task = updateTask(cfg, createTask(cfg, sampleTaskArgs()), (t) => { t.baseCommit = 'deadbeef'.repeat(5); });
  for (const [f, c] of Object.entries(SUA_KINH)) writeFile(path.join(dir, f), c);
  khaiResult(cfg, task, Object.keys(SUA_KINH));
  const ctx = await gateCtx(cfg, loadTask(cfg, task.id));
  assert.equal(ctx.committedFiles, undefined);
  assert.equal(ctx.changedFiles, undefined, 'git diff loi khong duoc lui ve "chi cay lam viec"');
  const g = gate(cfg, loadTask(cfg, task.id), ctx);
  assert.ok(g.missing.some((m) => m.startsWith('CHUA XAC MINH duoc file da commit')), g.missing.join('\n'));
  cleanup(dir);
});

test('#22 file da commit doc bang -z --no-renames: ten tieng Viet van bi CHAN, rename file CAM van lo ten cu', async () => {
  const dir = gitRepo({}, { 'src/Kính.kt': 'class Kinh\n', 'gradle/libs.versions.toml': 'a=1\n' });
  const cfg = loadConfig(dir);
  const task = updateTask(cfg, createTask(cfg, sampleTaskArgs()), (t) => { t.forbiddenPaths = ['gradle/libs.versions.toml']; });
  recordDispatch(cfg, loadTask(cfg, task.id), { kind: 'implement', conversationId: 'c-test' });
  khaiResult(cfg, task, ['src/Kính.kt', 'gradle/libs.versions.toml', 'gradle/x.toml']);
  writeFile(path.join(dir, 'src/Kính.kt'), 'class Kinh { fun ha() = 1 }\n');
  execFileSync('git', ['mv', 'gradle/libs.versions.toml', 'gradle/x.toml'], { cwd: dir, stdio: 'pipe' });
  suaVaCommit(dir, {});
  const ctx = await gateCtx(cfg, loadTask(cfg, task.id));
  assert.ok(ctx.committedFiles.includes('src/Kính.kt'), JSON.stringify(ctx.committedFiles));
  const g = gate(cfg, loadTask(cfg, task.id), ctx);
  assert.ok(g.missing.some((m) => m.includes('commitPolicy=forbid') && m.includes('src/Kính.kt')), g.missing.join('\n'));
  assert.ok(g.missing.some((m) => m.includes('CAM sua') && m.includes('gradle/libs.versions.toml')), g.missing.join('\n'));
  cleanup(dir);
});

test('#22 commit cuu ho cua PM TRUOC khi giao trien khai khong tinh la agent commit; commit SAU khi giao (ke ca qua rework) van CHAN', async () => {
  const dir = gitRepo({}, { 'src/Kinh.kt': 'class Kinh\n' });
  const cfg = loadConfig(dir);
  const task = createTask(cfg, sampleTaskArgs());
  // dispatch-guard khuyen PM commit moc cuu ho truoc khi giao khi cay ban va commitPolicy=forbid.
  suaVaCommit(dir, { 'src/Kinh.kt': 'class Kinh // WIP chu du an\n' }, 'PM: moc cuu ho');
  recordDispatch(cfg, loadTask(cfg, task.id), { kind: 'implement', conversationId: 'c-test' });
  for (const [f, c] of Object.entries(SUA_KINH)) writeFile(path.join(dir, f), c);
  khaiResult(cfg, task, Object.keys(SUA_KINH));
  const g1 = gate(cfg, loadTask(cfg, task.id), await gateCtx(cfg, loadTask(cfg, task.id)));
  assert.ok(!g1.missing.some((m) => m.includes('commitPolicy')), g1.missing.join('\n'));
  // Agent tu commit, PM tra viec: mo giao lai (rework) KHONG duoc doi moc => van CHAN.
  suaVaCommit(dir, {});
  markRework(cfg, loadTask(cfg, task.id), 'sua lai');
  recordDispatch(cfg, loadTask(cfg, task.id), { kind: 'rework', conversationId: 'c-test' });
  const g2 = gate(cfg, loadTask(cfg, task.id), await gateCtx(cfg, loadTask(cfg, task.id)));
  assert.ok(g2.missing.some((m) => m.includes('commitPolicy=forbid') && m.includes('src/Kinh.kt')), g2.missing.join('\n'));
  cleanup(dir);
});

test('#22 moc giao: khong chup duoc HEAD truoc khi giao => lui ve commit goc (khong lay HEAD sau); lan giao implement sau KHONG dat lai moc', async () => {
  // (a) git loi luc chup HEAD truoc khi gui prompt (headCommit null), agent commit truoc khi recordDispatch ghi.
  const dir = gitRepo({}, { 'src/Kinh.kt': 'class Kinh\n' });
  const cfg = loadConfig(dir);
  const task = createTask(cfg, sampleTaskArgs());
  khaiResult(cfg, task, Object.keys(SUA_KINH));
  suaVaCommit(dir, SUA_KINH);
  recordDispatch(cfg, loadTask(cfg, task.id), { kind: 'implement', conversationId: 'c-test', headCommit: null });
  const g1 = gate(cfg, loadTask(cfg, task.id), await gateCtx(cfg, loadTask(cfg, task.id)));
  assert.ok(g1.missing.some((m) => m.includes('commitPolicy=forbid') && m.includes('src/Kinh.kt')), g1.missing.join('\n'));
  // (b) task giao TRUOC ban nay (da co dispatch implement, chua co moc): giao implement lan nua khong duoc dat moc sau commit cua agent.
  const t2 = createTask(cfg, sampleTaskArgs({ title: 'task cu' }));
  updateTask(cfg, loadTask(cfg, t2.id), (t) => { t.dispatches.push({ kind: 'implement', round: 0, at: new Date().toISOString() }); });
  khaiResult(cfg, t2, ['src/Kinh.kt']);
  suaVaCommit(dir, { 'src/Kinh.kt': 'class Kinh { fun ha() = 9 }\n' });
  recordDispatch(cfg, loadTask(cfg, t2.id), { kind: 'implement', conversationId: 'c-test' });
  const g2 = gate(cfg, loadTask(cfg, t2.id), await gateCtx(cfg, loadTask(cfg, t2.id)));
  assert.ok(g2.missing.some((m) => m.includes('commitPolicy=forbid') && m.includes('src/Kinh.kt')), g2.missing.join('\n'));
  // (c) moc da ghi TRUOC khi gui, lan giao loi (khong recordDispatch), agent commit, giao lai: recordDispatch khong ghi de moc.
  const t3 = createTask(cfg, sampleTaskArgs({ title: 'giao loi' }));
  const head0 = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: dir, encoding: 'utf8' }).trim();
  updateTask(cfg, loadTask(cfg, t3.id), (t) => { t.implementBaseCommit = head0; });
  khaiResult(cfg, t3, ['src/Kinh.kt']);
  suaVaCommit(dir, { 'src/Kinh.kt': 'class Kinh { fun ha() = 8 }\n' });
  const head1 = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: dir, encoding: 'utf8' }).trim();
  recordDispatch(cfg, loadTask(cfg, t3.id), { kind: 'implement', conversationId: 'c-test', headCommit: head1 });
  assert.equal(loadTask(cfg, t3.id).implementBaseCommit, head0);
  cleanup(dir);
});

test('#22 PM commit sau nghiem thu: task DA ACCEPTED va khi mo lai (rework) khong ket vi commit cua PM; agent commit sau do van CHAN', async () => {
  const dir = gitRepo({}, { 'src/Kinh.kt': 'class Kinh\n' });
  const cfg = loadConfig(dir);
  const task = createTask(cfg, sampleTaskArgs());
  accept(cfg, loadTask(cfg, task.id), await duBangChung(dir, cfg, task));
  suaVaCommit(dir, {}, 'PM commit sau nghiem thu');
  const g0 = gate(cfg, loadTask(cfg, task.id), await gateCtx(cfg, loadTask(cfg, task.id)));
  assert.ok(!g0.missing.some((m) => m.includes('commitPolicy')), g0.missing.join('\n'));
  markRework(cfg, loadTask(cfg, task.id), 'mo lai: con thieu');
  const g1 = gate(cfg, loadTask(cfg, task.id), await gateCtx(cfg, loadTask(cfg, task.id)));
  assert.ok(!g1.missing.some((m) => m.includes('commitPolicy')), g1.missing.join('\n'));
  suaVaCommit(dir, { 'src/Kinh.kt': 'class Kinh { fun ha() = 4 }\n' });
  const g2 = gate(cfg, loadTask(cfg, task.id), await gateCtx(cfg, loadTask(cfg, task.id)));
  assert.ok(g2.missing.some((m) => m.includes('commitPolicy=forbid') && m.includes('src/Kinh.kt')), g2.missing.join('\n'));
  cleanup(dir);
});

test('#22 commit cua PHIEN KHAC (ngoai pham vi task) khong vao soi lint / moc sua file cuoi: khong bat chay lai test, khong chan oan', async () => {
  const dir = gitRepo({ commitPolicy: 'allow' }, { 'src/Kinh.kt': 'class Kinh\n' });
  const cfg = loadConfig(dir);
  const task = createTask(cfg, sampleTaskArgs());
  const ctx0 = await duBangChung(dir, cfg, task);
  assert.equal(gate(cfg, loadTask(cfg, task.id), ctx0).ok, true);
  tick(20);
  suaVaCommit(dir, { 'other/src/test/OtherTest.kt': 'class OtherTest\n', 'other/db/x.sql': 'create table a (id int);\ncreate table a (id int);\n' }, 'phien khac');
  const ctx = await gateCtx(cfg, loadTask(cfg, task.id));
  const g = gate(cfg, loadTask(cfg, task.id), ctx);
  assert.equal(g.ok, true, g.missing.join(' | '));
  cleanup(dir);
});
