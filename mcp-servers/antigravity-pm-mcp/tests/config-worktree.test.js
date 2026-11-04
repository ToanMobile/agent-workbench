// 04/11: worktree PR (git worktree add duoi checkout chinh) la goc project cua chinh no (audit grok dung cay PR), nhung khi chinh no
// khong co .antigravity-pm.json (file nay thuong khong duoc track) thi KE THUA cau hinh cua checkout chinh — mat testCommand / proof
// providers thi /giao trong worktree hong (pm_run kind=test bao "Chua khai testCommand").
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { loadConfig } from '../src/config.js';
import { tmpProject, cleanup, writeFile } from './helpers.js';

const g = (cwd, ...a) => execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', ...a], { cwd, encoding: 'utf8' }).trim();

test('CW1 linked worktree khong co .antigravity-pm.json: goc = worktree, cau hinh ke thua tu checkout chinh', () => {
  const main = tmpProject({ projectName: 'cw-main', testCommand: 'npm run cw-test' });
  try {
    g(main, 'init', '-q', '-b', 'main');
    writeFile(path.join(main, '.gitignore'), '.antigravity-pm/\n.antigravity-pm.json\n.claude/\n');
    writeFile(path.join(main, 'a.txt'), 'a\n');
    g(main, 'add', '-A'); g(main, 'commit', '-qm', 'init');
    const wt = path.join(main, '.claude', 'worktrees', 'x');
    g(main, 'worktree', 'add', '-q', '--detach', wt, 'HEAD');
    const cfg = loadConfig(wt);
    assert.equal(fs.realpathSync(cfg.projectRoot), fs.realpathSync(wt));
    assert.equal(cfg.testCommand, 'npm run cw-test', 'testCommand cua checkout chinh');
    assert.equal(cfg.projectName, 'cw-main');
  } finally {
    cleanup(main);
  }
});

test('CW2 worktree co .antigravity-pm.json rieng: dung file cua chinh no', () => {
  const main = tmpProject({ projectName: 'cw-main2', testCommand: 'npm run main' });
  try {
    g(main, 'init', '-q', '-b', 'main');
    writeFile(path.join(main, '.gitignore'), '.antigravity-pm/\n.antigravity-pm.json\n.claude/\n');
    writeFile(path.join(main, 'a.txt'), 'a\n');
    g(main, 'add', '-A'); g(main, 'commit', '-qm', 'init');
    const wt = path.join(main, '.claude', 'worktrees', 'y');
    g(main, 'worktree', 'add', '-q', '--detach', wt, 'HEAD');
    writeFile(path.join(wt, '.antigravity-pm.json'), JSON.stringify({ projectName: 'cw-wt', testCommand: 'npm run wt' }));
    const cfg = loadConfig(wt);
    assert.equal(cfg.testCommand, 'npm run wt');
    assert.equal(cfg.projectName, 'cw-wt');
  } finally {
    cleanup(main);
  }
});
