// Repo <-> tai khoan tren bang dieu khien web: hang repo, tai khoan thuc te (429 -> khac hang), lan dung cuoi,
// gan / them / go repo qua logic profiles.js. Chi dung thu muc tam, khong dong vao repo that.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {
  listKnownRepos,
  loadRepoRegistry,
  setRepoAccount,
  addRepo,
  removeRepo,
  getRepoAssignments,
  reportRateLimit,
  DEFAULT_REPOS,
} from '../src/profiles.js';
import { buildPanelState, runPanelAction, claudeProjectKey, effectiveRepoAccount, PANEL_ACTIONS } from '../src/panel.js';

const BIN = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'bin', 'cc-switcher-mcp.js');
const noDaemon = () => ({ running: false, pids: [] });

function setup() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-repos-'));
  const stateDir = path.join(root, 'state');
  fs.mkdirSync(stateDir);
  fs.writeFileSync(path.join(stateDir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos' }));
  // defaults:false -> khong co 6 repo that trong danh sach
  fs.writeFileSync(path.join(stateDir, 'repos.json'), JSON.stringify({ custom: [], hidden: [], defaults: false }));
  const mkRepo = (name, settings) => {
    const p = path.join(root, 'code', name);
    fs.mkdirSync(path.join(p, '.git'), { recursive: true });
    if (settings) {
      fs.mkdirSync(path.join(p, '.claude'), { recursive: true });
      fs.writeFileSync(path.join(p, '.claude', 'settings.local.json'), JSON.stringify(settings));
    }
    return p;
  };
  const homes = { finos: path.join(root, 'h-finos'), finos_team: path.join(root, 'h-team'), max: path.join(root, 'h-max') };
  return { root, stateDir, mkRepo, homes, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}
const readSettings = (p) => JSON.parse(fs.readFileSync(path.join(p, '.claude', 'settings.local.json'), 'utf8'));

test('claudeProjectKey giong ten thu muc projects cua Claude Code', () => {
  assert.equal(claudeProjectKey('/Volumes/Data/Toan/Game/Humans-vs.-UFOs'), '-Volumes-Data-Toan-Game-Humans-vs--UFOs');
  assert.equal(claudeProjectKey('/Volumes/Data/Toan/OfficeReader/OfficeReader'), '-Volumes-Data-Toan-OfficeReader-OfficeReader');
});

test('PANEL_ACTIONS co repo_assign / repo_add / repo_remove', () => {
  for (const a of ['repo_assign', 'repo_add', 'repo_remove']) assert.ok(PANEL_ACTIONS.includes(a));
});

test('listKnownRepos: truyen repos ma khong truyen stateDir thi khong tron danh sach that; mac dinh la 6 repo', () => {
  const repos = [{ name: 'x', path: '/tmp/x-not-real' }];
  assert.deepEqual(listKnownRepos({ repos }).map((r) => r.path), ['/tmp/x-not-real']);
  const t = setup();
  try {
    fs.writeFileSync(path.join(t.stateDir, 'repos.json'), JSON.stringify({ hidden: [DEFAULT_REPOS[0].path] }));
    const list = listKnownRepos({ stateDir: t.stateDir });
    assert.equal(list.length, DEFAULT_REPOS.length - 1);
    assert.ok(!list.some((r) => r.path === DEFAULT_REPOS[0].path));
  } finally { t.cleanup(); }
});

test('panel state: hang repo co nhom, duong dan, tai khoan gan, tai khoan thuc te, worktree, lan dung cuoi', async () => {
  const t = setup();
  try {
    const a = t.mkRepo('alpha', { account: 'finos', hooks: {} });
    const b = t.mkRepo('beta', { hooks: {} });
    const c = t.mkRepo('gamma', { account: 'max' });
    for (const p of [a, b, c]) addRepoRaw(t.stateDir, p);
    // worktree git cua alpha
    const wt = path.join(t.root, 'code', 'alpha-wt');
    fs.mkdirSync(path.join(a, '.git', 'worktrees', 'alpha-wt'), { recursive: true });
    fs.writeFileSync(path.join(a, '.git', 'worktrees', 'alpha-wt', 'gitdir'), `${wt}/.git\n`);
    // phien Claude: alpha dung qua finos_team (worktree .claude) moi hon finos
    const old = path.join(t.homes.finos, 'projects', claudeProjectKey(a));
    const newer = path.join(t.homes.finos_team, 'projects', `${claudeProjectKey(a)}--claude-worktrees-issue-1`);
    const other = path.join(t.homes.max, 'projects', `${claudeProjectKey(a)}-other`); // repo khac ten gan giong: bo qua
    for (const d of [old, newer, other]) fs.mkdirSync(d, { recursive: true });
    fs.writeFileSync(path.join(old, 's1.jsonl'), '{}');
    fs.writeFileSync(path.join(newer, 's2.jsonl'), '{}');
    fs.writeFileSync(path.join(other, 's3.jsonl'), '{}');
    const tOld = new Date('2026-10-30T01:00:00Z'), tNew = new Date('2026-10-31T02:00:00Z'), tOther = new Date('2026-10-31T03:00:00Z');
    fs.utimesSync(path.join(old, 's1.jsonl'), tOld, tOld);
    fs.utimesSync(path.join(newer, 's2.jsonl'), tNew, tNew);
    fs.utimesSync(path.join(other, 's3.jsonl'), tOther, tOther);
    // max cham 429 -> gamma tam chay khac hang (Grok)
    const nowMs = Date.parse('2026-10-31T04:00:00Z');
    reportRateLimit({ stateDir: t.stateDir, profileId: 'max', nowMs });

    const st = await buildPanelState({ stateDir: t.stateDir, nowMs, sync: false, daemonProbe: noDaemon, claudeHomes: t.homes });
    assert.deepEqual(st.claudeAccounts, ['finos', 'finos_team', 'max']);
    const row = (n) => st.repoAssignments.find((r) => r.name === n);
    assert.equal(st.repoAssignments.length, 3);

    const ra = row('alpha');
    assert.equal(ra.path, a);
    assert.equal(ra.account, 'finos');
    assert.equal(ra.pinnedInFile, true);
    assert.equal(ra.group, 'Tự thêm');
    assert.equal(ra.effective.kind, 'assigned');
    assert.equal(ra.effective.account, 'finos');
    assert.equal(ra.differs, false);
    assert.deepEqual(ra.worktrees, [wt]);
    assert.equal(ra.lastUsedAtMs, tNew.getTime());
    assert.equal(ra.lastUsedAccount, 'finos_team');

    const rb = row('beta');
    assert.equal(rb.pinnedInFile, false);
    assert.equal(rb.effective.kind, 'unpinned');
    assert.equal(rb.differs, true);
    assert.equal(rb.lastUsedAtMs, 0);

    const rc = row('gamma');
    assert.equal(rc.effective.kind, 'fallback');
    assert.equal(rc.effective.account, 'grok');
    assert.match(rc.effective.note, /không nhảy chéo Claude/);
    assert.equal(rc.differs, true);

    const raw = JSON.stringify(st);
    assert.ok(!raw.includes('configDir'));
  } finally { t.cleanup(); }
});

function addRepoRaw(stateDir, p) {
  const f = path.join(stateDir, 'repos.json');
  const reg = JSON.parse(fs.readFileSync(f, 'utf8'));
  reg.custom.push({ name: path.basename(p), path: p });
  fs.writeFileSync(f, JSON.stringify(reg));
}

test('effectiveRepoAccount: thieu thu muc, account la, tat ca du phong khoa', () => {
  const byId = {
    finos: { id: 'finos', isFrozen: true, shortLabel: 'FinOS', resetTimeFormatted: '15:00' },
    grok: { id: 'grok', isFrozen: true }, antigravity: { id: 'antigravity', isFrozen: true }, antigravity_pro: { id: 'antigravity_pro', isFrozen: true },
  };
  assert.equal(effectiveRepoAccount({ pathExists: false }, byId).kind, 'missing');
  assert.equal(effectiveRepoAccount({ pathExists: true, pinnedInFile: true, account: 'zzz' }, byId).kind, 'unknown');
  const e = effectiveRepoAccount({ pathExists: true, pinnedInFile: true, account: 'finos' }, byId);
  assert.equal(e.kind, 'blocked');
  assert.match(e.note, /15:00/);
});

test('repo_assign: ghi account, giu khoa khac; chi tai khoan Claude; repo la bi tu choi', async () => {
  const t = setup();
  try {
    const a = t.mkRepo('alpha', { account: 'finos', hooks: { Stop: [] }, autoMemoryDirectory: '/tmp/m' });
    addRepoRaw(t.stateDir, a);
    const res = await runPanelAction('repo_assign', { repo: a, account: 'max' }, { stateDir: t.stateDir });
    assert.equal(res.ok, true);
    assert.equal(res.repo.previous, 'finos');
    assert.match(res.message, /alpha/);
    const s = readSettings(a);
    assert.equal(s.account, 'max');
    assert.deepEqual(s.hooks, { Stop: [] });
    assert.equal(s.autoMemoryDirectory, '/tmp/m');
    assert.equal(getRepoAssignments({ stateDir: t.stateDir })[0].account, 'max');

    await assert.rejects(runPanelAction('repo_assign', { repo: a, account: 'grok' }, { stateDir: t.stateDir }), (e) => e.code === 'INVALID_INPUT');
    await assert.rejects(runPanelAction('repo_assign', { repo: '/etc', account: 'finos' }, { stateDir: t.stateDir }), /không nằm trong danh sách/);
    await assert.rejects(runPanelAction('repo_assign', { account: 'finos' }, { stateDir: t.stateDir }), /Thiếu đường dẫn/);
    assert.equal(readSettings(a).account, 'max');
    // repo chua co .claude: tao file moi
    const b = t.mkRepo('beta', null);
    addRepoRaw(t.stateDir, b);
    setRepoAccount({ stateDir: t.stateDir, repoPath: b, account: 'finos_team' });
    assert.deepEqual(readSettings(b), { account: 'finos_team' });
  } finally { t.cleanup(); }
});

test('repo_add / repo_remove: chi them thu muc git that, khong trung; go thi xoa account va giu khoa khac', async () => {
  const t = setup();
  try {
    const a = t.mkRepo('alpha', { hooks: { Stop: [] } });
    const notGit = path.join(t.root, 'plain');
    fs.mkdirSync(notGit);
    const opts = { stateDir: t.stateDir };
    await assert.rejects(runPanelAction('repo_add', { repo: 'relative/x', account: 'finos' }, opts), /tuyệt đối/);
    await assert.rejects(runPanelAction('repo_add', { repo: notGit, account: 'finos' }, opts), /không phải Git repo/);
    await assert.rejects(runPanelAction('repo_add', { repo: path.join(t.root, 'nope'), account: 'finos' }, opts), /Không thấy thư mục/);
    await assert.rejects(runPanelAction('repo_add', { repo: a, account: 'antigravity' }, opts), /tài khoản Claude/);
    await assert.rejects(runPanelAction('repo_add', { repo: a, account: 'finos', name: '<script>' }, opts), /Tên repo/);
    await assert.rejects(runPanelAction('repo_add', { repo: '/', account: 'finos' }, opts), /không phải \/ hay thư mục home/);

    const added = await runPanelAction('repo_add', { repo: `${a}/`, account: 'finos_team', name: 'Alpha App' }, opts);
    assert.equal(added.ok, true);
    assert.equal(readSettings(a).account, 'finos_team');
    let reg = loadRepoRegistry(t.stateDir);
    assert.deepEqual(reg.custom.map((r) => [r.name, r.path]), [['Alpha App', a]]);
    assert.equal(reg.defaults, false);
    await assert.rejects(runPanelAction('repo_add', { repo: a, account: 'finos' }, opts), /đã có trong danh sách/);

    const removed = await runPanelAction('repo_remove', { repo: a }, opts);
    assert.equal(removed.ok, true);
    assert.match(removed.message, /bỏ ghim/);
    assert.deepEqual(readSettings(a), { hooks: { Stop: [] } });
    reg = loadRepoRegistry(t.stateDir);
    assert.equal(reg.custom.length, 0);
    assert.equal(reg.defaults, false); // khong lam mat co defaults:false
    await assert.rejects(runPanelAction('repo_remove', { repo: a }, opts), /không nằm trong danh sách/);
  } finally { t.cleanup(); }
});

test('go repo mac dinh -> an (hidden), them lai -> hien lai; dung repos truyen vao thay vi repo that', () => {
  const t = setup();
  try {
    fs.writeFileSync(path.join(t.stateDir, 'repos.json'), JSON.stringify({ custom: [], hidden: [] }));
    const a = t.mkRepo('alpha', { account: 'finos', keep: 1 });
    const repos = [{ name: 'alpha', path: a, defaultAccount: 'finos' }];
    removeRepo({ stateDir: t.stateDir, repos, repoPath: a });
    assert.deepEqual(loadRepoRegistry(t.stateDir).hidden, [a]);
    assert.equal(listKnownRepos({ stateDir: t.stateDir, repos }).length, 0);
    assert.deepEqual(readSettings(a), { keep: 1 });
    addRepo({ stateDir: t.stateDir, repos, repoPath: a, account: 'max' });
    const reg = loadRepoRegistry(t.stateDir);
    assert.deepEqual(reg.hidden, []);
    assert.equal(reg.custom.length, 0);
    assert.equal(listKnownRepos({ stateDir: t.stateDir, repos })[0].source, 'default');
    assert.equal(readSettings(a).account, 'max');
  } finally { t.cleanup(); }
});

test('CLI --panel-action repo_add / repo_assign / repo_remove voi --state-dir tam', () => {
  const t = setup();
  try {
    const a = t.mkRepo('alpha', { hooks: {} });
    const env = { ...process.env, CC_SWITCHER_QUIET: '1' };
    const run = (args) => spawnSync(process.execPath, [BIN, ...args, '--state-dir', t.stateDir], { env, encoding: 'utf8', timeout: 20000 });
    let r = run(['--panel-action', 'repo_add', '--repo', a, '--account', 'finos', '--name', 'Alpha']);
    assert.equal(r.status, 0, r.stderr);
    let out = JSON.parse(r.stdout.trim());
    assert.equal(out.ok, true);
    assert.equal(out.state.repoAssignments.length, 1);
    assert.equal(out.state.repoAssignments[0].name, 'Alpha');
    r = run(['--panel-action', 'repo_assign', '--repo', a, '--account', 'finos_team']);
    out = JSON.parse(r.stdout.trim());
    assert.equal(out.state.repoAssignments[0].account, 'finos_team');
    r = run(['--panel-action', 'repo_assign', '--repo', a, '--account', 'grok']);
    assert.equal(r.status, 2);
    r = run(['--panel-action', 'repo_remove', '--repo', a]);
    out = JSON.parse(r.stdout.trim());
    assert.equal(out.state.repoAssignments.length, 0);
    assert.deepEqual(readSettings(a), { hooks: {} });
  } finally { t.cleanup(); }
});
