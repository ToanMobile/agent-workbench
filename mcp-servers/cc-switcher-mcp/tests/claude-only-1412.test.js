// #1412 (lenh chu repo 21/11): cc-switch chi dung tai khoan Claude. Truoc do rotateNextProfile xoay tiep sang Antigravity
// (va uu tien Antigravity khi preferCrossVendorOnCooldown bat), reportRateLimit goi y AGY Ultra, va trang bao repo
// "tam chay" profile khac hang khi tai khoan ghim dong bang. Antigravity van hien tren trang va van chon tay duoc.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import * as profiles from '../src/profiles.js';
import { effectiveRepoAccount, runPanelAction } from '../src/panel.js';

const { DEFAULT_PROFILES, rotateNextProfile, reportRateLimit, switchProfile, loadSwitcherState } = profiles;
const vendorOf = (id) => DEFAULT_PROFILES.find((p) => p.id === id)?.vendor;
const CLAUDE = DEFAULT_PROFILES.filter((p) => p.vendor === 'anthropic').map((p) => p.id);
const T0 = 1_700_000_000_000;

function tempState(extra = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-1412-'));
  fs.writeFileSync(path.join(dir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos_toan' }));
  if (Object.keys(extra).length) fs.writeFileSync(path.join(dir, 'switcher-state.json'), JSON.stringify(extra));
  return { dir, cleanup: () => fs.rmSync(dir, { recursive: true, force: true }) };
}

test('rotateNextProfile chi di qua profile Claude, ke ca khi moi tai khoan Claude deu dong bang', () => {
  const tmp = tempState();
  try {
    const seen = [];
    for (let i = 1; i <= 8; i += 1) {
      const r = rotateNextProfile({ stateDir: tmp.dir, nowMs: T0 + i * 20 * 60_000, markCurrentLimited: true });
      seen.push(r.activeProfile.id);
      assert.equal(vendorOf(r.activeProfile.id), 'anthropic', `buoc ${i} xoay sang ${r.activeProfile.id}`);
    }
    assert.deepEqual(seen.slice(0, 3), ['finos_linh', 'finos_toan_max', 'finos_lua']);
    assert.deepEqual(Object.keys(loadSwitcherState(tmp.dir).frozenUntil).filter((id) => !CLAUDE.includes(id)), []);
  } finally { tmp.cleanup(); }
});

test('policy cu con preferCrossVendorOnCooldown=true trong state: van khong xoay sang Antigravity', async () => {
  const stale = { activeProfileId: 'finos_toan', policy: { preferCrossVendorOnCooldown: true } };
  const tmp = tempState(stale);
  const viaPanel = tempState(stale);
  try {
    const r = rotateNextProfile({ stateDir: tmp.dir, nowMs: T0, markCurrentLimited: true });
    assert.equal(r.activeProfile.id, 'finos_linh');
    const res = await runPanelAction('limit', {}, { stateDir: viaPanel.dir, nowMs: T0 });
    assert.equal(vendorOf(res.to), 'anthropic');
  } finally { tmp.cleanup(); viaPanel.cleanup(); }
});

test('dang chon tay Antigravity: nut Xoay vong quay ve tai khoan Claude, khong sang AGY Pro', () => {
  const tmp = tempState();
  try {
    switchProfile({ stateDir: tmp.dir, target: 'antigravity_ultra', nowMs: T0, enforceCooldown: false });
    const r = rotateNextProfile({ stateDir: tmp.dir, nowMs: T0 + 60_000 });
    assert.equal(vendorOf(r.activeProfile.id), 'anthropic');
  } finally { tmp.cleanup(); }
});

test('reportRateLimit chi goi y tai khoan Claude; het tai khoan Claude thi khong goi y gi', () => {
  const tmp = tempState();
  try {
    const first = reportRateLimit({ stateDir: tmp.dir, nowMs: T0 });
    assert.equal(first.limitedProfile.id, 'finos_toan');
    assert.equal(vendorOf(first.nextProfile.id), 'anthropic');
    let last = first;
    for (const id of CLAUDE.slice(1)) last = reportRateLimit({ stateDir: tmp.dir, profileId: id, nowMs: T0 + 1000 });
    assert.equal(last.nextProfile, null);
  } finally { tmp.cleanup(); }
});

test('khong con hang CROSS_VENDOR_ORDER va khoa policy preferCrossVendorOnCooldown', () => {
  assert.equal('CROSS_VENDOR_ORDER' in profiles, false);
  const tmp = tempState();
  try {
    assert.equal('preferCrossVendorOnCooldown' in profiles.updateAntiBanPolicy(tmp.dir, { preferCrossVendorOnCooldown: true }), false);
  } finally { tmp.cleanup(); }
});

test('trang: tai khoan ghim dong bang thi repo tam dung toi gio reset, khong "tam chay" profile khac hang', () => {
  const byId = {
    finos_linh: { id: 'finos_linh', isFrozen: true, shortLabel: '2. FinOS Linh', resetTimeFormatted: '17:20' },
    antigravity_ultra: { id: 'antigravity_ultra', isFrozen: false }, antigravity_pro: { id: 'antigravity_pro', isFrozen: false },
  };
  const e = effectiveRepoAccount({ pathExists: true, pinnedInFile: true, account: 'finos_linh' }, byId);
  assert.equal(e.kind, 'blocked');
  assert.equal(e.account, '');
  assert.match(e.note, /17:20/);
  assert.doesNotMatch(e.note, /Antigravity|AGY|khác hãng/i);
});
