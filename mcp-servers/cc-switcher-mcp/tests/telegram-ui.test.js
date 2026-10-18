// Kiem thu Paired Executable Oracle (RED -> GREEN) cho Giao dien Tuong tac Telegram (Inline Keyboard + Callback Query + Persistent Menu).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {
  getStatusReport,
  loadSwitcherState,
  reportRateLimit,
  resetLocks,
  syncLiveQuotas,
} from '../src/profiles.js';
import {
  saveTelegramConfig,
  buildTelegramDashboard,
  buildReplyKeyboardMarkup,
  handleTelegramCallback,
  handleTelegramCommand,
} from '../src/telegram.js';
import { processIncomingTelegramUpdates } from '../src/daemon.js';

function createTempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-ui-'));
  fs.writeFileSync(
    path.join(dir, 'settings.json'),
    JSON.stringify({ currentProviderClaude: 'finos' }, null, 2),
  );
  return {
    dir,
    cleanup() {
      fs.rmSync(dir, { recursive: true, force: true });
    },
  };
}

test('Telegram UI 1: buildTelegramDashboard tao Inline Keyboard dep mat cho 6 profile va moi callback_data <= 64 byte', () => {
  const tmp = createTempDir();
  try {
    const report = getStatusReport({ stateDir: tmp.dir });
    const dash = buildTelegramDashboard(report);
    assert.ok(dash.text.includes('CC SWITCHER'));
    assert.ok(dash.reply_markup);
    assert.ok(Array.isArray(dash.reply_markup.inline_keyboard));

    const allButtons = dash.reply_markup.inline_keyboard.flat();
    const callbackDataList = allButtons.map((b) => b.callback_data);

    // Du 6 nut chon profile truc tiep
    for (const id of ['finos', 'finos_team', 'max', 'antigravity', 'antigravity_pro', 'grok']) {
      assert.ok(callbackDataList.includes(`sw:${id}`), `Thieu nut sw:${id}`);
    }

    // Du cac nut hanh dong nhanh
    for (const act of ['act:rotate', 'act:limit', 'act:unfreeze_all', 'act:refresh', 'cd:15', 'cd:5', 'cd:0']) {
      assert.ok(callbackDataList.includes(act), `Thieu nut ${act}`);
    }

    // Kiem tra gioi han 64 byte cua Telegram API cho callback_data
    for (const btn of allButtons) {
      assert.ok(btn.text.length > 0);
      assert.ok(Buffer.byteLength(btn.callback_data, 'utf8') <= 64);
    }

    // Kiem tra ReplyKeyboardMarkup co is_persistent va resize_keyboard
    const bottomKb = buildReplyKeyboardMarkup();
    assert.equal(bottomKb.resize_keyboard, true);
    assert.equal(bottomKb.is_persistent, true);
    assert.ok(Array.isArray(bottomKb.keyboard));
  } finally {
    tmp.cleanup();
  }
});

test('Telegram UI 2: handleTelegramCallback chuyen profile bang 1 cham, ho tro nut Ep chuyen (Force) khi dang Cooldown va Mo khoa 429', async () => {
  const tmp = createTempDir();
  try {
    const t0 = 1_700_000_000_000;
    // Dang o finos, bao dinh 429 -> finos bi dong bang 5h va kich hoat cooldown 15p cua Claude
    reportRateLimit({ stateDir: tmp.dir, nowMs: t0 });

    // Bam nut chon sang finos_team ngay lap tuc (t0 + 5s) -> bi chan Cooldown nhung hien nut Ep chuyen (fsw:finos_team)
    const blockedRes = await handleTelegramCallback(
      { id: 'cb-1', data: 'sw:finos_team' },
      { stateDir: tmp.dir, nowMs: t0 + 5000 },
    );
    assert.equal(blockedRes.showAlert, true);
    const blockedButtons = blockedRes.dashboard.reply_markup.inline_keyboard.flat();
    assert.ok(blockedButtons.some((b) => b.callback_data === 'fsw:finos_team'));

    // Nguoi dung bam nut "⚡ ÉP CHUYỂN NGAY" (fsw:finos_team) -> chuyen thanh cong luon!
    const forcedRes = await handleTelegramCallback(
      { id: 'cb-2', data: 'fsw:finos_team' },
      { stateDir: tmp.dir, nowMs: t0 + 6000 },
    );
    assert.equal(getStatusReport({ stateDir: tmp.dir, nowMs: t0 + 6000 }).activeProfileId, 'finos_team');
    assert.match(forcedRes.toastText, /FinOS Team/);

    // Bam nut "🔓 Mở khóa 429 & Cooldown" (act:unfreeze_all) -> xoa sach dong bang 5h va cooldown
    await handleTelegramCallback(
      { id: 'cb-3', data: 'act:unfreeze_all' },
      { stateDir: tmp.dir, nowMs: t0 + 7000 },
    );
    const unlockedState = loadSwitcherState(tmp.dir);
    assert.deepEqual(unlockedState.frozenUntil, {});
    assert.equal(unlockedState.lastClaudeSwitchAtMs, 0);
    assert.equal(unlockedState.lastClaudeRateLimitAtMs, 0);

    // Kiem tra ham resetLocks truc tiep
    reportRateLimit({ stateDir: tmp.dir, nowMs: t0 + 8000 });
    resetLocks(tmp.dir);
    assert.deepEqual(loadSwitcherState(tmp.dir).frozenUntil, {});
  } finally {
    tmp.cleanup();
  }
});

test('Telegram UI 3: processIncomingTelegramUpdates gui kem inline_keyboard va cap nhat tai cho (editMessageText) khi bam nut', async () => {
  const tmp = createTempDir();
  try {
    const token = ['888777666', 'AAH_ui_test_secret_token_999'].join(':');
    saveTelegramConfig(tmp.dir, { botToken: token, chatId: '11223344' });

    const apiCalls = [];
    const fakeApiCaller = async (_tok, method, body) => {
      apiCalls.push({ method, body });
      return true;
    };

    // 1. Nguoi dung bam nut tren Reply Keyboard "🎛 Bảng điều khiển" hoac go /status
    await processIncomingTelegramUpdates(
      [{ update_id: 100, message: { chat: { id: 11223344 }, text: '🎛 Bảng điều khiển' } }],
      { stateDir: tmp.dir, currentOffset: 0, apiCaller: fakeApiCaller },
    );

    const sendCall = apiCalls.find((c) => c.method === 'sendMessage');
    assert.ok(sendCall);
    assert.ok(sendCall.body.reply_markup?.inline_keyboard, 'Tin nhan phai dinh kem inline_keyboard');

    // 2. Nguoi dung cham nut inline "sw:antigravity" tren bang dieu khien (message_id: 555)
    apiCalls.length = 0;
    await processIncomingTelegramUpdates(
      [
        {
          update_id: 101,
          callback_query: {
            id: 'cbq-99',
            data: 'sw:antigravity',
            from: { id: 11223344 },
            message: { message_id: 555, chat: { id: 11223344 } },
          },
        },
      ],
      { stateDir: tmp.dir, currentOffset: 101, apiCaller: fakeApiCaller },
    );

    const answerCall = apiCalls.find((c) => c.method === 'answerCallbackQuery');
    const editCall = apiCalls.find((c) => c.method === 'editMessageText');
    assert.ok(answerCall, 'Phai goi answerCallbackQuery de hien toast');
    assert.equal(answerCall.body.callback_query_id, 'cbq-99');
    assert.ok(editCall, 'Phai goi editMessageText de cap nhat bang dieu khien tai cho');
    assert.equal(editCall.body.message_id, 555);
    assert.ok(editCall.body.reply_markup?.inline_keyboard);
    assert.equal(getStatusReport({ stateDir: tmp.dir }).activeProfileId, 'antigravity');

    // Kiem tra nut tren Reply Keyboard cung hoat dong qua handleTelegramCommand
    const rotateText = await handleTelegramCommand('🔄 Xoay vòng an toàn', { stateDir: tmp.dir });
    assert.match(rotateText, /XOAY VÒNG/);
  } finally {
    tmp.cleanup();
  }
});

test('Telegram UI 4: getStatusReport doc chinh xac totalRequests va totalCostUsd tu SQLite ngay ca khi PRAGMA busy_timeout in dong dau', async () => {
  const { execFileSync } = await import('node:child_process');
  const tmp = createTempDir();
  try {
    const dbFile = path.join(tmp.dir, 'cc-switch.db');
    execFileSync('sqlite3', [
      dbFile,
      'CREATE TABLE usage_daily_rollups (request_count INTEGER, total_cost_usd TEXT); INSERT INTO usage_daily_rollups VALUES (150, "12.50"), (50, "7.25");',
    ]);
    const report = getStatusReport({ stateDir: tmp.dir });
    assert.equal(report.usage.totalRequests, 200);
    assert.equal(report.usage.totalCostUsd, 19.75);
  } finally {
    tmp.cleanup();
  }
});

test('Telegram UI 5: syncLiveQuotas hien thi % quota con lai, thanh tien trinh va gio mo khoa chinh xac tren nut bam Telegram', async () => {
  const tmp = createTempDir();
  try {
    const nowMs = Date.parse('2026-10-18T16:25:00.000Z'); // 23:25 VN
    const fakeFetcher = async (profile) => {
      if (profile.id === 'finos') {
        return {
          remainingPct: 0,
          usedPct: 100,
          resetAtMs: Date.parse('2026-10-18T17:00:00.000Z'), // 00:00 VN (con 35p)
          weeklyRemainingPct: 100,
          source: 'anthropic_oauth',
        };
      }
      if (profile.id === 'finos_team') {
        return {
          remainingPct: 54,
          usedPct: 46,
          resetAtMs: Date.parse('2026-10-18T19:50:00.000Z'), // 02:50 VN (con 3h 25p)
          weeklyRemainingPct: 100,
          source: 'anthropic_oauth',
        };
      }
      if (profile.id === 'max') {
        return {
          remainingPct: 0,
          usedPct: 100,
          resetAtMs: Date.parse('2026-10-18T17:19:00.000Z'), // 00:19 VN (con 54p)
          isRateLimited: true,
          source: 'anthropic_429_header',
        };
      }
      return null;
    };

    await syncLiveQuotas({ stateDir: tmp.dir, nowMs, forceRefresh: true, quotaFetcher: fakeFetcher });
    const report = getStatusReport({ stateDir: tmp.dir, nowMs });

    const pFinos = report.profiles.find((p) => p.id === 'finos');
    const pTeam = report.profiles.find((p) => p.id === 'finos_team');
    const pMax = report.profiles.find((p) => p.id === 'max');

    assert.equal(pFinos.remainingPct, 0);
    assert.equal(pFinos.isFrozen, true);
    assert.equal(pFinos.resetTimeFormatted, '00:00');
    assert.equal(pTeam.remainingPct, 54);
    assert.equal(pTeam.isFrozen, false);
    assert.equal(pTeam.resetTimeFormatted, '02:50');
    assert.equal(pMax.remainingPct, 0);
    assert.equal(pMax.isFrozen, true);

    const dash = buildTelegramDashboard(report);
    // Kiem tra noi dung tin nhan hien ro % con lai, thanh tien trinh va gio mo khoa
    assert.match(dash.text, /Còn 54%/);
    assert.match(dash.text, /00:00/);
    assert.match(dash.text, /02:50/);
    assert.match(dash.text, /00:19/);

    // Kiem tra nut bam Inline Keyboard hien % va gio mo khoa ngay tren nhan nut
    const buttons = dash.reply_markup.inline_keyboard.flat();
    const btnFinos = buttons.find((b) => b.callback_data === 'sw:finos');
    const btnTeam = buttons.find((b) => b.callback_data === 'sw:finos_team');
    assert.match(btnFinos.text, /0%/);
    assert.match(btnFinos.text, /00:00/);
    assert.match(btnTeam.text, /54%/);
  } finally {
    tmp.cleanup();
  }
});
