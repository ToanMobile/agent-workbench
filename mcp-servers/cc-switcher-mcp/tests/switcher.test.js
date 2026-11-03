// Bo kiem thu Paired Executable Oracle (RED -> GREEN) cho cc-switcher-mcp.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {
  DEFAULT_PROFILES,
  resolveProfile,
  loadSwitcherState,
  getStatusReport,
  switchProfile,
  rotateNextProfile,
  reportRateLimit,
  updateAntiBanPolicy,
} from '../src/profiles.js';
import {
  maskSecret,
  saveTelegramConfig,
  loadTelegramConfig,
  handleTelegramCommand,
} from '../src/telegram.js';
import { detectRateLimitInLogChunk } from '../src/daemon.js';
import { TOOLS_BY_NAME } from '../src/tools.js';

function createTempEnv() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-test-'));
  const settingsFile = path.join(dir, 'settings.json');
  fs.writeFileSync(
    settingsFile,
    JSON.stringify({
      currentProviderClaude: 'finos_toan',
      currentProviderGemini: 'antigravity_ultra',
      currentProviderGrokbuild: 'grokbuild-official',
    }, null, 2),
  );
  return {
    dir,
    cleanup() {
      fs.rmSync(dir, { recursive: true, force: true });
    },
  };
}

test('7 profile mac dinh khop dung cau hinh CC Switch cua nguoi dung', () => {
  assert.equal(DEFAULT_PROFILES.length, 7);
  assert.deepEqual(
    DEFAULT_PROFILES.map((p) => p.id),
    ['finos_toan', 'finos_linh', 'finos_toan_max', 'antigravity_ultra', 'antigravity_pro', 'grok', 'finos_lua'],
  );
  const status = getStatusReport({ stateDir: createTempEnv().dir });
  assert.equal(status.profiles.length, 7);
  assert.equal(status.activeProfileId, 'finos_toan');
});

test('finos_lua: tai khoan Claude thu 7 dung ~/.claude-finos_lua, resolve duoc theo id va so 7', () => {
  const p = DEFAULT_PROFILES.find((x) => x.id === 'finos_lua');
  assert.ok(p, 'thieu profile finos_lua');
  assert.equal(p.index, 7);
  assert.equal(p.vendor, 'anthropic');
  assert.equal(p.appType, 'claude');
  assert.ok(p.configDir.endsWith('.claude-finos_lua'));
  assert.ok(p.name.includes('ngoclua892@gmail.com'));
  assert.equal(resolveProfile('finos_lua').id, 'finos_lua');
  assert.equal(resolveProfile(7).id, 'finos_lua');
  assert.equal(resolveProfile('7').id, 'finos_lua');
});

test('Anti-Ban Guard: chan chuyen tuc thi giua 2 tai khoan Claude khi chua du 15 phut cooldown va uu tien nhay sang provider khac', () => {
  const tmp = createTempEnv();
  try {
    // Danh dau profile 1 (finos - Claude) vua cham limit 429 tai t = 1000
    const nowMs = 1_700_000_000_000;
    const res = reportRateLimit({
      stateDir: tmp.dir,
      nowMs,
      reason: '429 Too Many Requests',
    });

    // Tai khoan 1 bi dong bang 5 tieng (18000s)
    const stateAfter = loadSwitcherState(tmp.dir);
    assert.ok(stateAfter.frozenUntil['finos_toan'] >= nowMs + 18000 * 1000);

    // Vi vua cham 429 tren Claude va dang trong vung cooldown 15 phut cua Claude,
    // neu bat che do an toan tuyet doi hoac xoay vong co kiem tra cooldown:
    // Neu chuyen sang Claude 2 ngay lap tuc (nowMs + 1000ms) ma khong co force -> bi chan hoac canh bao cooldown
    assert.throws(
      () => switchProfile({
        stateDir: tmp.dir,
        target: 'finos_linh',
        nowMs: nowMs + 2000,
        enforceCooldown: true,
      }),
      /COOLDOWN_ACTIVE/,
    );

    // Sau 15 phut (900s), chuyen sang finos_team (Account 2) thanh cong an toan
    const switchedAfter15m = switchProfile({
      stateDir: tmp.dir,
      target: 'finos_linh',
      nowMs: nowMs + 16 * 60 * 1000,
      enforceCooldown: true,
    });
    assert.equal(switchedAfter15m.activeProfile.id, 'finos_linh');
    assert.equal(switchedAfter15m.env.CLAUDE_DISABLE_TELEMETRY, '1');
    assert.ok(switchedAfter15m.env.CLAUDE_CONFIG_DIR.endsWith('.claude-finos_team'));
    assert.ok(res.nextProfile);
  } finally {
    tmp.cleanup();
  }
});

test('Xoay vong 6 profile tuan tu va bo qua tai khoan dang dong bang 5h', () => {
  const tmp = createTempEnv();
  try {
    const t0 = 1_700_000_000_000;
    //Tat enforceCooldown giua cac lan test xoay vong hoac tien thoi gian +16 phut moi buoc
    updateAntiBanPolicy(tmp.dir, { claudeSwitchCooldownSec: 600, rateLimitFreezeSec: 18000 });

    // Dang o 1 (finos) -> bao limit -> dong bang finos 5h, chuyen sang 2 (finos_team) sau 10 phut
    const r1 = rotateNextProfile({ stateDir: tmp.dir, nowMs: t0 + 11 * 60 * 1000, markCurrentLimited: true });
    assert.equal(r1.activeProfile.id, 'finos_linh');

    const r2 = rotateNextProfile({ stateDir: tmp.dir, nowMs: t0 + 25 * 60 * 1000, markCurrentLimited: true });
    assert.equal(r2.activeProfile.id, 'finos_toan_max');

    const r3 = rotateNextProfile({ stateDir: tmp.dir, nowMs: t0 + 40 * 60 * 1000, markCurrentLimited: true });
    assert.equal(r3.activeProfile.id, 'antigravity_ultra');

    const r4 = rotateNextProfile({ stateDir: tmp.dir, nowMs: t0 + 41 * 60 * 1000, markCurrentLimited: true });
    assert.equal(r4.activeProfile.id, 'antigravity_pro');

    const r5 = rotateNextProfile({ stateDir: tmp.dir, nowMs: t0 + 42 * 60 * 1000, markCurrentLimited: true });
    assert.equal(r5.activeProfile.id, 'grok');

    // Profile thu 7 (finos_lua) nam sau grok trong vong xoay
    const r6 = rotateNextProfile({ stateDir: tmp.dir, nowMs: t0 + 43 * 60 * 1000, markCurrentLimited: true });
    assert.equal(r6.activeProfile.id, 'finos_lua');

    // Sau 5 tieng + 1 phut, finos (Account 1) da het dong bang -> quay vong lai finos!
    const r7 = rotateNextProfile({ stateDir: tmp.dir, nowMs: t0 + (5 * 3600 + 3000) * 1000, markCurrentLimited: true });
    assert.equal(r7.activeProfile.id, 'finos_toan');
  } finally {
    tmp.cleanup();
  }
});

test('Telegram config luu an toan, mask secret; lenh /status, /switch, /cooldown chi tra link bang dieu khien web', async () => {
  const tmp = createTempEnv();
  try {
    const sampleKey = ['123456789', 'AAH_test_key_value_987654321'].join(':');
    saveTelegramConfig(tmp.dir, { botToken: sampleKey, chatId: '99887766' });
    const cfg = loadTelegramConfig(tmp.dir);
    assert.equal(cfg.botToken, sampleKey);
    assert.equal(cfg.chatId, '99887766');

    const masked = maskSecret(`Token la ${sampleKey} trong log`, [sampleKey]);
    assert.ok(!masked.includes('AAH_test_key_value_987654321'));
    assert.ok(masked.includes('***REDACTED***'));

    // Bang dieu khien da chuyen sang web: lenh Telegram chi tra link, khong doi tai khoan hay cooldown
    for (const cmd of ['/status', '/switch 4', '/cooldown 15']) {
      const reply = await handleTelegramCommand(cmd, { stateDir: tmp.dir });
      assert.match(reply, /ai-factory\.localhost:4317\/cc-switcher/);
    }
    assert.equal(getStatusReport({ stateDir: tmp.dir }).activeProfileId, 'finos_toan');
  } finally {
    tmp.cleanup();
  }
});

test('Daemon phat hien Rate Limit 429 trong log va MCP tools hoat dong day du', async () => {
  const tmp = createTempEnv();
  try {
    assert.equal(detectRateLimitInLogChunk('HTTP 429 Too Many Requests: rate_limit_error'), true);
    assert.equal(detectRateLimitInLogChunk('Usage limit reached. Resets at 11pm'), true);
    assert.equal(detectRateLimitInLogChunk(' Normal request 200 OK '), false);

    assert.ok(TOOLS_BY_NAME.has('switcher_status'));
    assert.ok(TOOLS_BY_NAME.has('switcher_switch'));
    assert.ok(TOOLS_BY_NAME.has('switcher_rotate'));
    assert.ok(TOOLS_BY_NAME.has('switcher_report_limit'));
    assert.ok(TOOLS_BY_NAME.has('switcher_configure_policy'));
    assert.ok(TOOLS_BY_NAME.has('switcher_telegram_setup'));

    const res = await TOOLS_BY_NAME.get('switcher_status').handler({ stateDir: tmp.dir });
    const text = typeof res === 'string' ? res : res.text;
    assert.match(text, /finos/);
  } finally {
    tmp.cleanup();
  }
});
