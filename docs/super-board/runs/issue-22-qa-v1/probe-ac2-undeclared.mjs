// QA probe #22 AC2 — chạy với: WT=<gốc mcp-servers/antigravity-pm-mcp> node --test probe-ac2-undeclared.mjs
// Không phải test của bộ (tên .mjs để không gate nào nhặt). ĐỎ = gate cho nghiệm thu dù worker sửa file CẤM mà không khai.
import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const WT = process.env.WT;
const { loadConfig } = await import(path.join(WT, 'src/config.js'));
const T = await import(path.join(WT, 'src/tasks.js'));
const { gateCtx } = await import(path.join(WT, 'src/worktree.js'));
const H = await import(path.join(WT, 'tests/helpers.js'));
const EV_OK = { source: 'stdout', weak: true, noop: false, ok: true, reason: 'test' };

function gitRepo(config, files) {
  const dir = H.tmpProject({ testCommand: 'echo ok', ...config });
  const git = (...a) => execFileSync('git', a, { cwd: dir, stdio: 'pipe' });
  git('init', '-q'); git('config', 'user.email', 't@e.com'); git('config', 'user.name', 'T');
  H.writeFile(path.join(dir, '.gitignore'), '.antigravity-pm/\n');
  for (const [f, c] of Object.entries(files)) H.writeFile(path.join(dir, f), c);
  git('add', '-A'); git('commit', '-qm', 'init');
  return dir;
}

// Kịch bản AC2: worker sửa file forbiddenPaths, KHÔNG khai trong files_changed, đủ bằng chứng PM còn lại.
async function chay({ commitPolicy, commit }) {
  const dir = gitRepo({ commitPolicy }, { 'src/Kinh.kt': 'class Kinh\n', 'gradle/libs.versions.toml': 'a=1\n' });
  const cfg = loadConfig(dir);
  let task = T.updateTask(cfg, T.createTask(cfg, H.sampleTaskArgs()), (t) => { t.forbiddenPaths = ['gradle/libs.versions.toml']; });
  const p = T.contractPaths(cfg, task);
  H.writeFile(p.plan, '# Ke hoach');
  T.recordVerdict(cfg, task, { kind: 'plan', verdict: 'pass' });
  T.recordDispatch(cfg, T.loadTask(cfg, task.id), { kind: 'implement', conversationId: 'c-test' });
  H.tick();
  const sua = { 'src/Kinh.kt': 'class Kinh { fun ha() = 1 }\n', 'src/test/KinhTest.kt': 'class KinhTest\n', 'gradle/libs.versions.toml': 'a=2\n' };
  for (const [f, c] of Object.entries(sua)) H.writeFile(path.join(dir, f), c);
  if (commit) { execFileSync('git', ['add', '-A'], { cwd: dir }); execFileSync('git', ['commit', '-qm', 'w'], { cwd: dir }); }
  // Khai THIẾU file CẤM.
  H.writeFile(p.result, JSON.stringify({ phase: 'IMPLEMENT', summary: 'da lam', files_changed: ['src/Kinh.kt', 'src/test/KinhTest.kt'] }));
  H.tick();
  T.recordVerdict(cfg, task, { kind: 'audit', verdict: 'pass' });
  T.recordVerdict(cfg, task, { kind: 'review', verdict: 'pass' });
  T.recordRun(cfg, task, { kind: 'test', command: 'echo ok', exitCode: 0, durationMs: 5, evidence: EV_OK, startedAt: new Date().toISOString() });
  const img = H.writeFile(path.join(p.proofDir, 'shot.png'), H.PNG_1PX);
  T.recordProof(cfg, task, { label: 'anh', provider: 'adb', file: img, bytes: H.PNG_1PX.length });
  const ctx = await gateCtx(cfg, T.loadTask(cfg, task.id));
  const g = T.gate(cfg, T.loadTask(cfg, task.id), ctx);
  let accepted = false;
  try { T.accept(cfg, T.loadTask(cfg, task.id), ctx); accepted = true; } catch { accepted = false; }
  H.cleanup(dir);
  return { ok: g.ok, accepted, cam: g.missing.filter((m) => m.includes('CAM')), canhBao: (g.warnings || []).filter((w) => String(w.text || w).includes('CAM')), missing: g.missing };
}

for (const commitPolicy of ['forbid', 'allow']) {
  for (const commit of [false, true]) {
    test(`AC2 khong khai file CAM: commitPolicy=${commitPolicy} commit=${commit} => phai CHAN nghiem thu`, async (t) => {
      const r = await chay({ commitPolicy, commit });
      t.diagnostic(JSON.stringify({ commitPolicy, commit, ok: r.ok, accepted: r.accepted, camMissing: r.cam, camWarn: r.canhBao, missing: r.missing }));
      assert.equal(r.accepted, false, `accept() THANH CONG du worker sua file CAM gradle/libs.versions.toml khong khai`);
    });
  }
}

// Kịch bản d1: `git mv` file CẤM, CHƯA commit, khai cả tên cũ lẫn tên mới (forbid mặc định).
test('AC2 git mv file CAM chua commit, khai ca ten cu => phai CHAN nghiem thu', async (t) => {
  const dir = gitRepo({}, { 'src/Kinh.kt': 'class Kinh\n', 'gradle/libs.versions.toml': 'a=1\n' });
  const cfg = loadConfig(dir);
  const task = T.updateTask(cfg, T.createTask(cfg, H.sampleTaskArgs()), (x) => { x.forbiddenPaths = ['gradle/libs.versions.toml']; });
  const p = T.contractPaths(cfg, task);
  H.writeFile(p.plan, '# Ke hoach');
  T.recordVerdict(cfg, task, { kind: 'plan', verdict: 'pass' });
  T.recordDispatch(cfg, T.loadTask(cfg, task.id), { kind: 'implement', conversationId: 'c-test' });
  H.tick();
  H.writeFile(path.join(dir, 'src/Kinh.kt'), 'class Kinh { fun ha() = 1 }\n');
  H.writeFile(path.join(dir, 'src/test/KinhTest.kt'), 'class KinhTest\n');
  execFileSync('git', ['mv', 'gradle/libs.versions.toml', 'gradle/x.toml'], { cwd: dir });
  H.writeFile(p.result, JSON.stringify({ phase: 'IMPLEMENT', summary: 'da lam', files_changed: ['src/Kinh.kt', 'src/test/KinhTest.kt', 'gradle/libs.versions.toml', 'gradle/x.toml'] }));
  H.tick();
  T.recordVerdict(cfg, task, { kind: 'audit', verdict: 'pass' });
  T.recordVerdict(cfg, task, { kind: 'review', verdict: 'pass' });
  T.recordRun(cfg, task, { kind: 'test', command: 'echo ok', exitCode: 0, durationMs: 5, evidence: EV_OK, startedAt: new Date().toISOString() });
  const img = H.writeFile(path.join(p.proofDir, 'shot.png'), H.PNG_1PX);
  T.recordProof(cfg, task, { label: 'anh', provider: 'adb', file: img, bytes: H.PNG_1PX.length });
  const ctx = await gateCtx(cfg, T.loadTask(cfg, task.id));
  const g = T.gate(cfg, T.loadTask(cfg, task.id), ctx);
  let accepted = false;
  try { T.accept(cfg, T.loadTask(cfg, task.id), ctx); accepted = true; } catch { accepted = false; }
  t.diagnostic(JSON.stringify({ case: 'git-mv-uncommitted', ok: g.ok, accepted, changedFiles: ctx.changedFiles, warnings: g.warnings, missing: g.missing }));
  H.cleanup(dir);
  assert.equal(accepted, false, 'accept() THANH CONG du worker git mv file CAM gradle/libs.versions.toml');
});
