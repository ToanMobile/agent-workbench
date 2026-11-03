// finos_lua (tai khoan Claude thu 7): hai cho code cu gia dinh chi co 2-3 tai khoan Claude. Temp dirs only.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';
import { balanceRepoAccounts, switchProfile } from '../src/profiles.js';

function setup() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-lua-'));
  const stateDir = path.join(root, 'state');
  fs.mkdirSync(stateDir);
  fs.writeFileSync(path.join(stateDir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos_toan' }));
  fs.writeFileSync(path.join(stateDir, 'repos.json'), JSON.stringify({ custom: [], hidden: [], defaults: false }));
  const mkRepo = (name, account) => {
    const p = path.join(root, 'code', name);
    fs.mkdirSync(path.join(p, '.git'), { recursive: true });
    fs.mkdirSync(path.join(p, '.claude'), { recursive: true });
    fs.writeFileSync(path.join(p, '.claude', 'settings.local.json'), JSON.stringify(account ? { account } : {}));
    return p;
  };
  return { root, stateDir, mkRepo, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}
const account = (p) => JSON.parse(fs.readFileSync(path.join(p, '.claude', 'settings.local.json'), 'utf8')).account;

test('"Dao nhom" chi doi finos <-> finos_team, repo ghim finos_lua hoac max giu nguyen (truoc day bi chuyen ve finos)', () => {
  const t = setup();
  try {
    const repos = [
      { name: 'a', path: t.mkRepo('a', 'finos_toan') },
      { name: 'b', path: t.mkRepo('b', 'finos_linh') },
      { name: 'c', path: t.mkRepo('c', 'finos_lua') },
      { name: 'd', path: t.mkRepo('d', 'finos_toan_max') },
    ];
    balanceRepoAccounts({ stateDir: t.stateDir, repos, mode: 'swap' });
    assert.deepEqual(repos.map((r) => account(r.path)), ['finos_linh', 'finos_toan', 'finos_lua', 'finos_toan_max']);
  } finally { t.cleanup(); }
});

test('chuyen sang finos_lua khi cc-switch.db chua co provider nay: khong xoa co is_current cua provider dang dung', () => {
  const t = setup();
  try {
    const db = path.join(t.stateDir, 'cc-switch.db');
    execFileSync('sqlite3', [db, "CREATE TABLE providers (id TEXT, app_type TEXT, is_current INTEGER); INSERT INTO providers VALUES ('finos','claude',1),('finos_team','claude',0);"]); // DB cua app CC Switch van dung id cu
    switchProfile({ stateDir: t.stateDir, target: 'finos_lua', force: true });
    const rows = execFileSync('sqlite3', [db, "SELECT id || ':' || is_current FROM providers ORDER BY id;"], { encoding: 'utf8' }).trim().split('\n');
    assert.deepEqual(rows, ['finos:1', 'finos_team:0']);
    assert.equal(JSON.parse(fs.readFileSync(path.join(t.stateDir, 'settings.json'), 'utf8')).currentProviderClaude, 'finos_lua');
  } finally { t.cleanup(); }
});
