// Quota khong lay duoc: bao dung ly do (token het han / bi 429 / loi mang), khong luc nao cung bao "dang nhap lai".
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {
  fetchAnthropicProfileQuotaLive,
  getStatusReport,
  loadSwitcherState,
  saveSwitcherState,
  syncLiveQuotas,
} from '../src/profiles.js';
import { buildPanelState } from '../src/panel.js';
import { formatStatusText } from '../src/status-text.js';

const NOW = Date.parse('2026-11-09T08:00:00.000Z');
const noDaemon = () => ({ running: false, pids: [] });
const profile = { id: 'finos_toan', vendor: 'anthropic', configDir: '/tmp/x' };
const field = ['access', 'Token'].join('');

function tmpDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-issue-'));
  fs.writeFileSync(path.join(dir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos_linh' }));
  return { dir, cleanup: () => fs.rmSync(dir, { recursive: true, force: true }) };
}

test('fetch bao ly do token_expired / throttled / network qua onFailure', async () => {
  const reasons = [];
  const onFailure = (r) => reasons.push(r);
  const expired = await fetchAnthropicProfileQuotaLive(profile, NOW, {
    onFailure,
    tokenReader: () => ({ [field]: 'm', expiresAt: NOW - 1000 }),
    httpFetcher: async () => { throw new Error('khong duoc goi'); },
  });
  assert.equal(expired, null);
  const live = { tokenReader: () => ({ [field]: 'm', expiresAt: NOW + 3600_000 }), onFailure };
  await fetchAnthropicProfileQuotaLive(profile, NOW, { ...live, httpFetcher: async () => ({ status: 429 }) });
  await fetchAnthropicProfileQuotaLive(profile, NOW, { ...live, httpFetcher: async () => { throw new Error('ECONNRESET'); } });
  assert.deepEqual(reasons, ['token_expired', 'throttled', 'network']);
});

test('syncLiveQuotas luu ly do that bai vao state, thanh cong thi xoa', async () => {
  const t = tmpDir();
  try {
    const failing = async (p, _now, o) => { o?.onFailure?.('token_expired'); return null; };
    await syncLiveQuotas({ stateDir: t.dir, nowMs: NOW, forceRefresh: true, quotaFetcher: failing });
    assert.equal(loadSwitcherState(t.dir).quotaIssues.finos_toan.reason, 'token_expired');
    const ok = async (p) => (p.id === 'finos_toan'
      ? { remainingPct: 70, usedPct: 30, resetAtMs: NOW + 3600_000, weeklyRemainingPct: 50, weeklyResetAtMs: NOW + 86400_000, source: 'anthropic_oauth', updatedAtMs: NOW }
      : null);
    await syncLiveQuotas({ stateDir: t.dir, nowMs: NOW + 1000, forceRefresh: true, quotaFetcher: ok });
    assert.equal(loadSwitcherState(t.dir).quotaIssues.finos_toan, undefined);
  } finally { t.cleanup(); }
});

test('bao cao + panel mang quotaIssue cua profile cu', async () => {
  const t = tmpDir();
  try {
    saveSwitcherState(t.dir, {
      activeProfileId: 'finos_linh',
      quotaCache: { finos_toan: { remainingPct: 40, usedPct: 60, resetAtMs: NOW - 3600_000, source: 'anthropic_oauth', updatedAtMs: NOW - 30 * 3600_000 } },
      quotaIssues: { finos_toan: { reason: 'token_expired', atMs: NOW - 1000 } },
    });
    const p = getStatusReport({ stateDir: t.dir, nowMs: NOW }).profiles.find((x) => x.id === 'finos_toan');
    assert.equal(p.quotaStale, true);
    assert.equal(p.quotaIssue, 'token_expired');
    const v = (await buildPanelState({ stateDir: t.dir, nowMs: NOW, sync: false, daemonProbe: noDaemon })).profiles.find((x) => x.id === 'finos_toan');
    assert.equal(v.quotaIssue, 'token_expired');
  } finally { t.cleanup(); }
});

test('van ban trang thai: token het han chi cach mo claude, khong bao refresh token mat', () => {
  const t = tmpDir();
  try {
    saveSwitcherState(t.dir, {
      activeProfileId: 'finos_linh',
      quotaCache: { finos_toan: { remainingPct: 40, usedPct: 60, resetAtMs: NOW - 3600_000, source: 'anthropic_oauth', updatedAtMs: NOW - 30 * 3600_000 } },
      quotaIssues: { finos_toan: { reason: 'token_expired', atMs: NOW - 1000 } },
    });
    const text = formatStatusText(getStatusReport({ stateDir: t.dir, nowMs: NOW }));
    assert.match(text, /hết hạn/);
    assert.match(text, /claude/);
    assert.doesNotMatch(text, /\(đăng nhập lại\)/);
  } finally { t.cleanup(); }
});
