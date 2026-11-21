// #1412: syncLiveQuotas chỉ nhìn quota 5 giờ khi ghi/xoá frozenUntil. Tài khoản hết giới hạn TUẦN nhưng cửa sổ 5 giờ còn
// trống bị gỡ đóng băng, nên trang /cc-switcher hiện ACTIVE trong lúc pool của runner báo PAUSE tới giờ reset tuần.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { loadSwitcherState, saveSwitcherState, syncLiveQuotas } from '../src/profiles.js';

function setup(nowMs, frozenUntil) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-sync-weekly-'));
  fs.writeFileSync(path.join(dir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos_toan' }));
  saveSwitcherState(dir, { ...loadSwitcherState(dir), activeProfileId: 'finos_toan', frozenUntil });
  return dir;
}

function fetcherFor(id, quota) {
  return async (p) => (p.id === id ? quota : null);
}

test('hết giới hạn tuần, 5 giờ còn trống: giữ đóng băng tới giờ reset tuần', async () => {
  const nowMs = Date.parse('2026-11-21T09:00:00.000Z');
  const weeklyReset = nowMs + 8 * 3_600_000;
  const dir = setup(nowMs, { finos_linh: weeklyReset });
  try {
    await syncLiveQuotas({
      stateDir: dir, nowMs, forceRefresh: true,
      quotaFetcher: fetcherFor('finos_linh', {
        remainingPct: 80, usedPct: 20, resetAtMs: nowMs + 600_000, isRateLimited: false, source: 'anthropic_oauth',
        weeklyRemainingPct: 0, weeklyResetAtMs: weeklyReset,
      }),
    });
    assert.equal(loadSwitcherState(dir).frozenUntil.finos_linh, weeklyReset, 'khoá tuần không được gỡ vì 5 giờ còn trống');
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('hết giới hạn tuần, chưa có khoá: đặt đóng băng tới giờ reset tuần', async () => {
  const nowMs = Date.parse('2026-11-21T09:00:00.000Z');
  const weeklyReset = nowMs + 8 * 3_600_000;
  const dir = setup(nowMs, {});
  try {
    await syncLiveQuotas({
      stateDir: dir, nowMs, forceRefresh: true,
      quotaFetcher: fetcherFor('finos_linh', {
        remainingPct: 80, usedPct: 20, resetAtMs: nowMs + 600_000, isRateLimited: false, source: 'anthropic_oauth',
        weeklyRemainingPct: 0, weeklyResetAtMs: weeklyReset,
      }),
    });
    assert.equal(loadSwitcherState(dir).frozenUntil.finos_linh, weeklyReset);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('cả hai cửa sổ còn hạn mức: vẫn gỡ đóng băng cũ', async () => {
  const nowMs = Date.parse('2026-11-21T09:00:00.000Z');
  const dir = setup(nowMs, { finos_linh: nowMs + 3_600_000 });
  try {
    await syncLiveQuotas({
      stateDir: dir, nowMs, forceRefresh: true,
      quotaFetcher: fetcherFor('finos_linh', {
        remainingPct: 35, usedPct: 65, resetAtMs: nowMs + 600_000, isRateLimited: false, source: 'anthropic_oauth',
        weeklyRemainingPct: 40, weeklyResetAtMs: nowMs + 8 * 3_600_000,
      }),
    });
    assert.equal(loadSwitcherState(dir).frozenUntil.finos_linh, undefined);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
