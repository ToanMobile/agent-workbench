// #742 finding 454bc984b7: syncLiveQuotas() giữ bản state đọc trước khi chờ mạng (tới 8 s mỗi profile) rồi ghi đè
// switcher-state.json. Một thao tác chạy xen (POST /api/cc-switcher/action, daemon xoay do 429) bị mất.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { loadSwitcherState, saveSwitcherState, syncLiveQuotas } from '../src/profiles.js';

test('syncLiveQuotas giữ thay đổi state ghi xen trong lúc chờ quota', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-sync-race-'));
  try {
    const nowMs = Date.parse('2026-11-01T02:20:00.000Z');
    fs.writeFileSync(path.join(dir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos' }));
    saveSwitcherState(dir, { ...loadSwitcherState(dir), activeProfileId: 'finos', frozenUntil: { finos_team: nowMs + 3_600_000 } });

    let raced = false;
    const quotaFetcher = async (p) => {
      if (!raced) {
        // một tiến trình khác chuyển tài khoản và đóng băng max đúng lúc sync còn đang chờ mạng
        raced = true;
        const other = loadSwitcherState(dir);
        other.activeProfileId = 'max';
        other.lastClaudeSwitchAtMs = nowMs - 1000;
        other.frozenUntil.finos = nowMs + 5 * 3_600_000;
        other.policy.claudeSwitchCooldownSec = 1200;
        saveSwitcherState(dir, other);
      }
      return p.id === 'finos_team'
        ? { remainingPct: 40, usedPct: 60, resetAtMs: nowMs + 600_000, isRateLimited: false, source: 'anthropic_oauth' }
        : null;
    };

    await syncLiveQuotas({ stateDir: dir, nowMs, forceRefresh: true, quotaFetcher });

    const st = loadSwitcherState(dir);
    assert.equal(st.activeProfileId, 'max', 'tài khoản vừa chuyển không được bị ghi đè bằng bản cũ');
    assert.equal(st.lastClaudeSwitchAtMs, nowMs - 1000, 'mốc Anti-Ban cooldown phải còn');
    assert.equal(st.policy.claudeSwitchCooldownSec, 1200, 'policy vừa đổi phải còn');
    assert.equal(st.frozenUntil.finos, nowMs + 5 * 3_600_000, 'đóng băng ghi xen phải còn');
    assert.equal(st.frozenUntil.finos_team, undefined, 'quota sống > 0 vẫn mở khoá finos_team');
    assert.equal(st.quotaCache.finos_team.remainingPct, 40, 'kết quả quota mới vẫn được lưu');
    assert.equal(st.quotaFetchedAtMs, nowMs);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
