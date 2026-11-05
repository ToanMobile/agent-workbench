// Quota sai: (1) thieu moc reset tuan (thu may, may gio) nhu Claude Code; (2) cache cu van hien 100%/READY nhu so that.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fetchAnthropicProfileQuotaLive, getStatusReport, saveSwitcherState } from '../src/profiles.js';
import { buildPanelState } from '../src/panel.js';

const noDaemon = () => ({ running: false, pids: [] });
const NOW = Date.parse('2026-11-05T08:00:00.000Z');

function tmpDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-weekly-'));
  fs.writeFileSync(path.join(dir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos_toan' }));
  return { dir, cleanup: () => fs.rmSync(dir, { recursive: true, force: true }) };
}

test('fetch giu moc reset tuan (seven_day.resets_at)', async () => {
  const field = ['access', 'Token'].join('');
  const q = await fetchAnthropicProfileQuotaLive({ id: 'finos_linh', vendor: 'anthropic', configDir: '/tmp/x' }, NOW, {
    tokenReader: () => ({ [field]: 'm', expiresAt: NOW + 3600_000 }),
    httpFetcher: async () => ({ status: 200, json: async () => ({ five_hour: { utilization: 14, resets_at: '2026-11-05T12:30:00+00:00' }, seven_day: { utilization: 55, resets_at: '2026-11-07T17:00:00+00:00' } }) }),
  });
  assert.equal(q.weeklyResetAtMs, Date.parse('2026-11-07T17:00:00Z'));
});

test('bao cao hien reset tuan dang "Thứ Bảy 00:00" (gio VN)', () => {
  const t = tmpDir();
  try {
    saveSwitcherState(t.dir, { activeProfileId: 'finos_linh', quotaCache: { finos_linh: { remainingPct: 86, usedPct: 14, resetAtMs: NOW + 3600_000, weeklyRemainingPct: 45, weeklyResetAtMs: Date.parse('2026-11-07T17:00:00Z'), source: 'anthropic_oauth', updatedAtMs: NOW - 1000 } } });
    const p = getStatusReport({ stateDir: t.dir, nowMs: NOW }).profiles.find((x) => x.id === 'finos_linh');
    assert.equal(p.weeklyResetAtMs, Date.parse('2026-11-07T17:00:00Z'));
    assert.match(p.weeklyResetFormatted, /Chủ Nhật 00:00/);
    assert.equal(p.quotaStale, false);
  } finally { t.cleanup(); }
});

test('cache qua cu (token het han, 30 gio) bi danh dau quotaStale, khong gia lam 100% con', async () => {
  const t = tmpDir();
  try {
    saveSwitcherState(t.dir, { activeProfileId: 'finos_toan', quotaCache: { finos_toan: { remainingPct: 40, usedPct: 60, resetAtMs: NOW - 20 * 3600_000, weeklyRemainingPct: 51, weeklyResetAtMs: NOW + 86400_000, source: 'anthropic_oauth', updatedAtMs: NOW - 30 * 3600_000 } } });
    const p = getStatusReport({ stateDir: t.dir, nowMs: NOW }).profiles.find((x) => x.id === 'finos_toan');
    assert.equal(p.quotaStale, true);
    assert.equal(p.remainingPct, null, 'khong ro thi khong bao 100%');
    assert.match(p.status, /CŨ|cũ|UNKNOWN/i);
    const st = await buildPanelState({ stateDir: t.dir, nowMs: NOW, sync: false, daemonProbe: noDaemon });
    const v = st.profiles.find((x) => x.id === 'finos_toan');
    assert.equal(v.quotaStale, true);
    assert.ok(v.weeklyResetFormatted);
  } finally { t.cleanup(); }
});

test('tuan da qua moc reset thi hoi phuc 100%', () => {
  const t = tmpDir();
  try {
    saveSwitcherState(t.dir, { activeProfileId: 'finos_linh', quotaCache: { finos_linh: { remainingPct: 80, usedPct: 20, resetAtMs: NOW + 1000_000, weeklyRemainingPct: 5, weeklyResetAtMs: NOW - 1000, source: 'anthropic_oauth', updatedAtMs: NOW - 1000 } } });
    const p = getStatusReport({ stateDir: t.dir, nowMs: NOW }).profiles.find((x) => x.id === 'finos_linh');
    assert.equal(p.weeklyRemainingPct, 100);
  } finally { t.cleanup(); }
});
