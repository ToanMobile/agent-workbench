// #672: pm_verdict chap nhan head moi neu la merge commit cua origin/main vao auditedHead ma diff cua PR khong doi
// (gate merge tu gop main vao nhanh PR nen head doi, auditedHead cu het hieu luc).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { loadConfig } from '../src/config.js';
import { createTask, recordDispatch, taskFile } from '../src/tasks.js';
import { TOOLS_BY_NAME } from '../src/tools.js';
import { tmpProject, cleanup, writeFile, sampleTaskArgs } from './helpers.js';

const verdict = (args) => TOOLS_BY_NAME.get('pm_verdict').handler(args);
delete process.env.DEVKIT_AGENT_ID;

const git = (dir, ...a) => execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', ...a], { cwd: dir, encoding: 'utf8' }).trim();
const commit = (dir, file, text, msg) => { writeFile(path.join(dir, file), text); git(dir, 'add', '-A'); git(dir, 'commit', '-qm', msg); return git(dir, 'rev-parse', 'HEAD'); };

// Repo: main = base; nhanh pr = base + sua pr.txt (A); origin/main tien them main.txt (M).
function setup() {
  const dir = tmpProject({ projectName: 'merge-head', testCommand: 'echo ok' });
  git(dir, 'init', '-q', '-b', 'main');
  writeFile(path.join(dir, '.gitignore'), '.antigravity-pm/\n');
  commit(dir, 'pr.txt', 'base\n', 'base');
  git(dir, 'checkout', '-q', '-b', 'pr');
  const A = commit(dir, 'pr.txt', 'pr change\n', 'pr');
  git(dir, 'checkout', '-q', 'main');
  const M = commit(dir, 'main.txt', 'from main\n', 'main moves');
  git(dir, 'update-ref', 'refs/remotes/origin/main', M);
  git(dir, 'checkout', '-q', 'pr');
  const cfg = loadConfig(dir);
  const task = createTask(cfg, sampleTaskArgs());
  recordDispatch(cfg, task, { kind: 'audit', conversationId: 'c-audit' });
  writeFile(path.join(dir, '.antigravity-pm', 'tasks', task.id, 'audit-agent.json'),
    JSON.stringify({ verdict: 'pass', reviewer: 'antigravity', auditedHead: A }));
  return { dir, cfg, task, A, M };
}
const auditOf = (cfg, task) => JSON.parse(fs.readFileSync(taskFile(cfg, task.id), 'utf8')).verdicts?.audit;
const run = (dir, task, H) => verdict({ project: dir, taskId: task.id, kind: 'audit', verdict: 'pass', notes: 'ok', auditedHead: H });

test('MH1 merge commit hop le (parent1=A, parent2 trong origin/main, diff PR rong) duoc chap nhan, notes ghi ly do', async () => {
  const { dir, cfg, task, A, M } = setup();
  try {
    git(dir, 'merge', '--no-ff', '-q', '-m', 'merge main', M);
    const H = git(dir, 'rev-parse', 'HEAD');
    await run(dir, task, H);
    const a = auditOf(cfg, task);
    assert.equal(a.auditedHead, H);
    assert.match(a.notes, new RegExp(`parent1=${A}`));
    assert.match(a.notes, new RegExp(`parent2=${M}`));
    assert.match(a.notes, /diff-pr-files=empty/);
    assert.match(a.notes, /diff-from-main=ok/);
  } finally { cleanup(dir); }
});

test('MH2 merge commit co thay doi la (sua file cua PR, hoac them file khong tu main) bi tu choi', async () => {
  const { dir, cfg, task, M } = setup();
  try {
    git(dir, 'merge', '--no-ff', '--no-commit', '-q', M);
    writeFile(path.join(dir, 'pr.txt'), 'sneaky\n');
    git(dir, 'add', '-A'); git(dir, 'commit', '-qm', 'merge with evil');
    await assert.rejects(run(dir, task, git(dir, 'rev-parse', 'HEAD')), /merge/i);
    assert.equal(auditOf(cfg, task), undefined);
  } finally { cleanup(dir); }
  const s = setup();
  try {
    git(s.dir, 'merge', '--no-ff', '--no-commit', '-q', s.M);
    writeFile(path.join(s.dir, 'extra.txt'), 'not from main\n');
    git(s.dir, 'add', '-A'); git(s.dir, 'commit', '-qm', 'merge with extra');
    await assert.rejects(run(s.dir, s.task, git(s.dir, 'rev-parse', 'HEAD')), /merge/i);
  } finally { cleanup(s.dir); }
});

test('MH3 head khong phai merge commit cua auditedHead (commit thuong, hoac merge parent1 khac A) bi tu choi', async () => {
  const { dir, task, A, M } = setup();
  try {
    const H = commit(dir, 'main.txt', 'from main\n', 'plain child');
    await assert.rejects(run(dir, task, H), /merge/i);
    git(dir, 'checkout', '-q', '-b', 'other', 'origin/main');
    commit(dir, 'o.txt', 'o\n', 'other');
    git(dir, 'merge', '--no-ff', '-q', '-m', 'merge pr into other', A);
    await assert.rejects(run(dir, task, git(dir, 'rev-parse', 'HEAD')), /merge/i);
    assert.ok(M);
  } finally { cleanup(dir); }
});

test('MH4 evil merge: sua noi dung file trung ten voi file main doi, hoac `-s ours` bo thay doi cua main, bi tu choi', async () => {
  const s = setup();
  try {
    // main doi them pr2.txt; merge tay sua noi dung pr2.txt (ten trung voi thay doi tu main)
    git(s.dir, 'checkout', '-q', 'main');
    const M2 = commit(s.dir, 'main2.txt', 'm2\n', 'main moves again');
    git(s.dir, 'update-ref', 'refs/remotes/origin/main', M2);
    git(s.dir, 'checkout', '-q', 'pr');
    git(s.dir, 'merge', '--no-ff', '--no-commit', '-q', M2);
    writeFile(path.join(s.dir, 'main2.txt'), 'tampered\n');
    git(s.dir, 'add', '-A'); git(s.dir, 'commit', '-qm', 'tampered merge');
    await assert.rejects(run(s.dir, s.task, git(s.dir, 'rev-parse', 'HEAD')), /merge/i);
  } finally { cleanup(s.dir); }
  const o = setup();
  try {
    git(o.dir, 'merge', '--no-ff', '-s', 'ours', '-q', '-m', 'ours', o.M);
    await assert.rejects(run(o.dir, o.task, git(o.dir, 'rev-parse', 'HEAD')), /merge/i);
  } finally { cleanup(o.dir); }
});

test('MH5 ten file co dau tieng Viet va dau cach trong PR van doi chieu dung', async () => {
  const s = setup();
  try {
    git(s.dir, 'checkout', '-q', '-b', 'vn', s.A);
    const A2 = commit(s.dir, 'tài liệu mới.md', 'x\n', 'vn file');
    writeFile(path.join(s.dir, '.antigravity-pm', 'tasks', s.task.id, 'audit-agent.json'),
      JSON.stringify({ verdict: 'pass', reviewer: 'antigravity', auditedHead: A2 }));
    git(s.dir, 'merge', '--no-ff', '-q', '-m', 'merge main', s.M);
    await run(s.dir, s.task, git(s.dir, 'rev-parse', 'HEAD'));
    assert.equal(auditOf(s.cfg, s.task).auditedHead, git(s.dir, 'rev-parse', 'HEAD'));
  } finally { cleanup(s.dir); }
});
