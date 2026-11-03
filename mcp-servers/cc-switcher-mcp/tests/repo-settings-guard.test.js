// #742 review c27d199d. Temp dirs only, never a real repo or ~/.cc-switch.
// 35f6ac7a5a: an unparsable .claude/settings.local.json gave a raw SyntaxError (exit 1 / HTTP 502) instead of
//   AppError INVALID_INPUT, and addRepo wrote repos.json before it read that file, so a failed add left the repo half-added
//   ("Repo này đã có trong danh sách." on the retry). removeRepo threw on it too after the registry was already saved.
// 0e1f66b8df: balanceRepoAccounts ("Chia đều" / "Đảo nhóm") also re-pinned repos the user added by hand (repo_add), which
//   have no defaultAccount: even mode overwrote their pin, swap moved a `max` pin to finos, and their count moved the split.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { addRepo, removeRepo, setRepoAccount, balanceRepoAccounts, listKnownRepos, loadRepoRegistry } from '../src/profiles.js';

function setup() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-repo-guard-'));
  const stateDir = path.join(root, 'state');
  fs.mkdirSync(stateDir);
  fs.writeFileSync(path.join(stateDir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos_toan' }));
  fs.writeFileSync(path.join(stateDir, 'repos.json'), JSON.stringify({ custom: [], hidden: [], defaults: false }));
  const mkRepo = (name, rawSettings) => {
    const p = path.join(root, 'code', name);
    fs.mkdirSync(path.join(p, '.git'), { recursive: true });
    if (rawSettings !== undefined) {
      fs.mkdirSync(path.join(p, '.claude'), { recursive: true });
      fs.writeFileSync(path.join(p, '.claude', 'settings.local.json'), rawSettings);
    }
    return p;
  };
  return { root, stateDir, mkRepo, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}
const settingsFile = (p) => path.join(p, '.claude', 'settings.local.json');
const account = (p) => JSON.parse(fs.readFileSync(settingsFile(p), 'utf8')).account;
const invalidInput = (err) => err && err.name === 'AppError' && err.code === 'INVALID_INPUT';
const TRUNCATED = '{"hooks": {';

test('35f6ac7a5a: setRepoAccount on an unparsable settings.local.json throws AppError INVALID_INPUT and keeps the bytes', () => {
  const t = setup();
  try {
    const p = t.mkRepo('alpha', TRUNCATED);
    const repos = [{ name: 'alpha', path: p, defaultAccount: 'finos_toan' }];
    assert.throws(() => setRepoAccount({ stateDir: t.stateDir, repos, repoPath: p, account: 'finos_linh' }), invalidInput);
    assert.equal(fs.readFileSync(settingsFile(p), 'utf8'), TRUNCATED);
  } finally { t.cleanup(); }
});

test('35f6ac7a5a: addRepo checks settings.local.json BEFORE it writes repos.json; the retry after a fix succeeds', () => {
  const t = setup();
  try {
    const repos = [{ name: 'base', path: t.mkRepo('base', '{}'), defaultAccount: 'finos_toan' }];
    const p = t.mkRepo('broken', TRUNCATED);
    const before = fs.readFileSync(path.join(t.stateDir, 'repos.json'), 'utf8');
    assert.throws(() => addRepo({ stateDir: t.stateDir, repos, repoPath: p, account: 'finos_toan_max' }), invalidInput);
    assert.equal(fs.readFileSync(path.join(t.stateDir, 'repos.json'), 'utf8'), before, 'repos.json must not change');
    assert.ok(!listKnownRepos({ stateDir: t.stateDir, repos }).some((r) => r.path === p), 'the repo must not be half-added');
    assert.equal(fs.readFileSync(settingsFile(p), 'utf8'), TRUNCATED);
    fs.writeFileSync(settingsFile(p), JSON.stringify({ hooks: {} }));
    const res = addRepo({ stateDir: t.stateDir, repos, repoPath: p, account: 'finos_toan_max' });
    assert.equal(res.added, true);
    assert.equal(account(p), 'finos_toan_max');
  } finally { t.cleanup(); }
});

test('35f6ac7a5a: removeRepo with an unparsable settings.local.json still removes the repo and leaves the file byte-for-byte', () => {
  const t = setup();
  try {
    const repos = [{ name: 'base', path: t.mkRepo('base', '{}'), defaultAccount: 'finos_toan' }];
    const p = t.mkRepo('later-broken', '{}');
    addRepo({ stateDir: t.stateDir, repos, repoPath: p, account: 'finos_toan_max' });
    fs.writeFileSync(settingsFile(p), TRUNCATED);
    const res = removeRepo({ stateDir: t.stateDir, repos, repoPath: p });
    assert.equal(res.removed, true);
    assert.equal(fs.readFileSync(settingsFile(p), 'utf8'), TRUNCATED);
    assert.ok(!loadRepoRegistry(t.stateDir).custom.some((c) => c.path === p));
  } finally { t.cleanup(); }
});

for (const mode of ['even', 'swap']) {
  test(`0e1f66b8df: balanceRepoAccounts(${mode}) keeps the hand-picked pin of repos added with repo_add`, () => {
    const t = setup();
    try {
      // 4 default repos with no defaultAccount: the split is idx < 2 -> finos, else finos_team
      const repos = ['d0', 'd1', 'd2', 'd3'].map((n) => ({ name: n, path: t.mkRepo(n, '{}') }));
      const pinnedMax = t.mkRepo('mine-max', '{}');
      const pinnedTeam = t.mkRepo('mine-team', '{}');
      addRepo({ stateDir: t.stateDir, repos, repoPath: pinnedMax, account: 'finos_toan_max' });
      addRepo({ stateDir: t.stateDir, repos, repoPath: pinnedTeam, account: 'finos_linh' });

      const res = balanceRepoAccounts({ stateDir: t.stateDir, repos, mode });

      assert.equal(account(pinnedMax), 'finos_toan_max', 'a custom repo pinned to max is not moved');
      assert.equal(account(pinnedTeam), 'finos_linh', 'a custom repo pinned by hand is not re-pinned');
      assert.ok(!res.some((r) => r.path === pinnedMax || r.path === pinnedTeam), 'custom repos are not in the balance result');
      // the default repos split over their own count (2 + 2), not over 6 with the custom repos (that gave 3 + 1)
      const want = mode === 'even' ? ['finos_toan', 'finos_toan', 'finos_linh', 'finos_linh'] : ['finos_linh', 'finos_linh', 'finos_toan', 'finos_toan'];
      assert.deepEqual(repos.map((r) => account(r.path)), want);
    } finally { t.cleanup(); }
  });
}
