// Profile dang nhap SAI tai khoan (vd thu muc finos_lua dang la tai khoan Toan): khong hien quota cua tai khoan khac.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { DEFAULT_PROFILES, getStatusReport, readLoggedInEmail, saveSwitcherState } from '../src/profiles.js';
import { buildPanelState } from '../src/panel.js';
import { formatStatusText } from '../src/status-text.js';

const NOW = Date.parse('2026-11-09T08:00:00.000Z');
const noDaemon = () => ({ running: false, pids: [] });
const fresh = { remainingPct: 55, usedPct: 45, resetAtMs: NOW + 3600_000, weeklyRemainingPct: 52, weeklyResetAtMs: NOW + 86400_000, source: 'anthropic_oauth', updatedAtMs: NOW - 1000 };

function tmp() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-identity-'));
  fs.writeFileSync(path.join(dir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos_toan' }));
  saveSwitcherState(dir, { activeProfileId: 'finos_toan', quotaCache: { finos_lua: fresh, finos_toan: fresh } });
  return { dir, cleanup: () => fs.rmSync(dir, { recursive: true, force: true }) };
}
const emails = (map) => (p) => map[p.id] ?? null;
const find = (rep, id) => rep.profiles.find((x) => x.id === id);

test('moi profile Claude khai bao email ky vong', () => {
  for (const p of DEFAULT_PROFILES.filter((x) => x.vendor === 'anthropic')) assert.match(p.expectedEmail, /^[^@\s]+@[^@\s]+$/, p.id);
  assert.equal(DEFAULT_PROFILES.find((x) => x.id === 'finos_lua').expectedEmail, 'ngoclua892@gmail.com');
});

test('readLoggedInEmail doc oauthAccount.emailAddress, loi/thieu file thi null', () => {
  const t = tmp();
  try {
    fs.writeFileSync(path.join(t.dir, '.claude.json'), JSON.stringify({ oauthAccount: { emailAddress: 'A@B.com' } }));
    assert.equal(readLoggedInEmail({ configDir: t.dir }), 'a@b.com');
    assert.equal(readLoggedInEmail({ configDir: path.join(t.dir, 'nope') }), null);
    fs.writeFileSync(path.join(t.dir, '.claude.json'), '{hong');
    assert.equal(readLoggedInEmail({ configDir: t.dir }), null);
  } finally { t.cleanup(); }
});

test('dang nhap sai tai khoan: an quota, bao wrong_account kem email ky vong/thuc te', async () => {
  const t = tmp();
  try {
    const accountReader = emails({ finos_lua: 'toan.huynh@finos.asia', finos_toan: 'toan.huynh@finos.asia' });
    const rep = getStatusReport({ stateDir: t.dir, nowMs: NOW, accountReader });
    const lua = find(rep, 'finos_lua');
    assert.equal(lua.quotaIssue, 'wrong_account');
    assert.equal(lua.remainingPct, null, 'khong hien quota cua tai khoan khac');
    assert.equal(lua.weeklyRemainingPct, null);
    assert.deepEqual(lua.accountMismatch, { expected: 'ngoclua892@gmail.com', actual: 'toan.huynh@finos.asia' });
    const toan = find(rep, 'finos_toan');
    assert.equal(toan.remainingPct, 55);
    assert.equal(toan.quotaIssue, '');
    assert.equal(toan.accountMismatch, null);
    const v = find(await buildPanelState({ stateDir: t.dir, nowMs: NOW, sync: false, daemonProbe: noDaemon, accountReader }), 'finos_lua');
    assert.equal(v.quotaIssue, 'wrong_account');
    assert.equal(v.accountMismatch.actual, 'toan.huynh@finos.asia');
    const text = formatStatusText(rep);
    assert.match(text, /sai tài khoản/i);
    assert.match(text, /ngoclua892@gmail\.com/);
  } finally { t.cleanup(); }
});

test('khong doc duoc email (chua dang nhap/file hong) thi KHONG bao sai tai khoan', () => {
  const t = tmp();
  try {
    const rep = getStatusReport({ stateDir: t.dir, nowMs: NOW, accountReader: () => null });
    assert.equal(find(rep, 'finos_lua').quotaIssue, '');
    assert.equal(find(rep, 'finos_lua').remainingPct, 55);
  } finally { t.cleanup(); }
});
