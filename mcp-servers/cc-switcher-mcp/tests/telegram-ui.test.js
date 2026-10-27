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
  fetchAnthropicProfileQuotaLive,
  balanceRepoAccounts,
  getRepoAssignments,
  DEFAULT_REPOS,
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

test('Telegram UI 6: balanceRepoAccounts chia deu 3 repo finos va 3 repo finos_team, giu nguyen cau hinh cu va ho tro dao nhom tren Telegram', async () => {
  const tmp = createTempDir();
  try {
    const defaultNames = DEFAULT_REPOS.map((r) => r.name);
    assert.ok(defaultNames.includes('Idle-Plaza-3D'), 'DEFAULT_REPOS phai chua Idle-Plaza-3D');
    assert.ok(!defaultNames.includes('Neighbours-From-Hell'), 'DEFAULT_REPOS khong con Neighbours-From-Hell');
    const plazaEntry = DEFAULT_REPOS.find((r) => r.name === 'Idle-Plaza-3D');
    assert.equal(plazaEntry.path, '/Volumes/Data/Toan/Game/Idle-Plaza-3D');
    assert.equal(plazaEntry.defaultAccount, 'finos');

    const repoNames = [
      'agent-workbench',
      'OfficeReader',
      'Idle-Plaza-3D',
      'GeelyEx2',
      'Goods-Triple-Shelf-Match-3D',
      'Humans-vs.-UFOs',
    ];
    const repos = repoNames.map((name, idx) => {
      const repoPath = path.join(tmp.dir, name);
      fs.mkdirSync(path.join(repoPath, '.claude'), { recursive: true });
      fs.writeFileSync(
        path.join(repoPath, '.claude', 'settings.local.json'),
        JSON.stringify({ autoMemoryDirectory: `/tmp/mem-${idx}`, hooks: { Stop: [] } }, null, 2),
      );
      return {
        name,
        path: repoPath,
        defaultAccount: idx < 3 ? 'finos' : 'finos_team',
      };
    });

    // Chia deu 3 repo finos, 3 repo finos_team
    const assigned = balanceRepoAccounts({ repos, mode: 'even' });
    assert.equal(assigned.filter((r) => r.account === 'finos').length, 3);
    assert.equal(assigned.filter((r) => r.account === 'finos_team').length, 3);

    // Dam bao giu nguyen autoMemoryDirectory va hooks trong settings.local.json
    const firstFile = JSON.parse(
      fs.readFileSync(path.join(repos[0].path, '.claude', 'settings.local.json'), 'utf8'),
    );
    assert.equal(firstFile.account, 'finos');
    assert.equal(firstFile.autoMemoryDirectory, '/tmp/mem-0');
    assert.ok(firstFile.hooks);

    // Dao nhom (swap): 3 repo finos <-> 3 repo finos_team
    const swapped = balanceRepoAccounts({ repos, mode: 'swap' });
    assert.equal(swapped[0].account, 'finos_team');
    assert.equal(swapped[3].account, 'finos');

    const currentMap = getRepoAssignments({ repos });
    assert.equal(currentMap.length, 6);

    const report = getStatusReport({ stateDir: tmp.dir, repos });
    const dash = buildTelegramDashboard(report);
    assert.match(dash.text, /PHÂN BỔ 6 REPO/);
    const allButtons = dash.reply_markup.inline_keyboard.flat();
    assert.ok(allButtons.some((b) => b.callback_data === 'act:balance_repos'));
    assert.ok(allButtons.some((b) => b.callback_data === 'act:swap_repos'));
  } finally {
    tmp.cleanup();
  }
});

test('Telegram UI 7: Bo cuc Mobile UI/UX gon dep, khong lap so [1] 1., nut bam <= 24 ky tu khong bi cat ... tren dien thoai, 6 repo tach dong ro rang', () => {
  const tmp = createTempDir();
  try {
    const report = getStatusReport({ stateDir: tmp.dir });
    const dash = buildTelegramDashboard(report);

    // 1. Khong lap so thu tu kieu "[1] 1. FinOS" gay roi mat
    assert.doesNotMatch(dash.text, /\[\d\]\s+\d\./);

    // 2. Tat ca nut chon profile (sw:*) tren 2 cot phai <= 24 ky tu de % va gio mo khoa khong bi cat "..." tren iPhone/Android
    const swButtons = dash.reply_markup.inline_keyboard
      .flat()
      .filter((b) => b.callback_data.startsWith('sw:'));
    assert.equal(swButtons.length, 6);
    for (const btn of swButtons) {
      assert.ok(
        btn.text.length <= 24,
        `Nut "${btn.text}" dai ${btn.text.length} ky tu (> 24) se bi cat '...' tren dien thoai`,
      );
    }

    // 3. Danh sach 6 Repo duoc trinh bay tach dong ro rang, de doc lướt tren man hinh doc
    assert.match(dash.text, /• agent-workbench/);
    assert.match(dash.text, /• GeelyEx2/);

    // 4. Khi chia 3 repo finos + 3 repo finos_team (chay song song), CA 2 tai khoan deu hien thi 🟢 ĐANG DÙNG (3 repo) tren text va nut bam
    assert.match(dash.text, /🟢 1\. FinOS.*3 repo ✓/);
    assert.match(dash.text, /🟢 2\. FinOS Team.*3 repo ✓/);
    const btnFinos = swButtons.find((b) => b.callback_data === 'sw:finos');
    const btnTeam = swButtons.find((b) => b.callback_data === 'sw:finos_team');
    assert.match(btnFinos.text, /^🟢.*✓$/);
    assert.match(btnTeam.text, /^🟢.*✓$/);
  } finally {
    tmp.cleanup();
  }
});

test('Telegram UI 8: Giao dien UI/UX moi nhat hien thi Khoa nhay cheo Claude, thu tu du phong Grok CLI -> AGY Ultra -> AGY Pro va sap xep nut bam theo dung luong', () => {
  const tmp = createTempDir();
  try {
    const report = getStatusReport({ stateDir: tmp.dir });
    const dash = buildTelegramDashboard(report);

    // 1. Hien thi ro co che Khoa nhay cheo va thu tu xoay vong Grok CLI -> AGY Ultra -> AGY Pro
    assert.match(dash.text, /Khóa nhảy chéo/);
    assert.match(dash.text, /Grok CLI ➔ AGY Ultra ➔ AGY Pro/);

    // 2. Khoi du phong khac hang xep dung thu tu uu tien: Grok CLI (#1) truoc AGY Ultra (#2) truoc AGY Pro (#3)
    const idxGrok = dash.text.indexOf('Ưu tiên 1 · 6. Grok CLI');
    const idxUltra = dash.text.indexOf('Ưu tiên 2 · 4. Antigravity Ultra');
    const idxPro = dash.text.indexOf('Ưu tiên 3 · 5. Antigravity Pro');
    assert.ok(idxGrok > 0, 'Phai hien thi Ưu tiên 1 · 6. Grok CLI');
    assert.ok(idxUltra > idxGrok, 'Ưu tiên 2 · 4. Antigravity Ultra phai dung sau Grok CLI');
    assert.ok(idxPro > idxUltra, 'Ưu tiên 3 · 5. Antigravity Pro phai dung sau AGY Ultra');

    // 3. Bo cuc 3 hang nut bam profile (2 cot):
    // Hang 1: sw:finos | sw:finos_team
    // Hang 2: sw:grok  | sw:antigravity
    // Hang 3: sw:antigravity_pro | sw:max
    const rows = dash.reply_markup.inline_keyboard;
    assert.deepEqual(rows[0].map((b) => b.callback_data), ['sw:finos', 'sw:finos_team']);
    assert.deepEqual(rows[1].map((b) => b.callback_data), ['sw:grok', 'sw:antigravity']);
    assert.deepEqual(rows[2].map((b) => b.callback_data), ['sw:antigravity_pro', 'sw:max']);

    // 4. Khi tai khoan Claude (finos) cham 429, reportRateLimit de xuat ngay Grok CLI (khong nhay cheo sang finos_team)
    const limitRes = reportRateLimit({ stateDir: tmp.dir, nowMs: 1_700_000_000_000 });
    assert.equal(limitRes.nextProfile.id, 'grok');
  } finally {
    tmp.cleanup();
  }
});

test('Telegram UI 9: Khong bao sai 0% tren 3. Personal 5x Max khi endpoint /api/oauth/usage bi throttle HTTP 429 hoac dinh cache anthropic_429_header', async () => {
  const tmp = createTempDir();
  try {
    const nowMs = Date.parse('2026-10-19T02:38:00.000Z');
    // 1. Gia lap endpoint /api/oauth/usage tra ve HTTP 429 (rate limit cua endpoint kiem tra, KHONG phai het quota 5h)
    const fake429Res = await fetchAnthropicProfileQuotaLive(
      { id: 'max', vendor: 'anthropic', configDir: '/tmp/fake-max' },
      nowMs,
      {
        tokenReader: () => {
          const field = ['access', 'Token'].join('');
          return { [field]: 'mock-val', expiresAt: nowMs + 3600_000 };
        },
        httpFetcher: async () => ({
          status: 429,
          headers: new Map([['retry-after', '2092']]),
          json: async () => ({ error: { type: 'rate_limit_error' } }),
        }),
      },
    );
    assert.equal(fake429Res, null, 'HTTP 429 tu /api/oauth/usage phai tra ve null, khong duoc quy thanh 0% quota');

    // 2. Gia lap switcher-state.json dang bi dinh cache anthropic_429_header cu tren profile max
    fs.writeFileSync(
      path.join(tmp.dir, 'switcher-state.json'),
      JSON.stringify({
        activeProfileId: 'finos',
        frozenUntil: { max: nowMs + 2000_000 },
        quotaCache: {
          max: {
            remainingPct: 0,
            usedPct: 100,
            resetAtMs: nowMs + 2000_000,
            isRateLimited: true,
            source: 'anthropic_429_header',
            updatedAtMs: nowMs - 10_000,
          },
        },
      }),
    );

    await syncLiveQuotas({
      stateDir: tmp.dir,
      nowMs,
      forceRefresh: true,
      quotaFetcher: async () => null,
    });
    const report = getStatusReport({ stateDir: tmp.dir, nowMs });
    const pMax = report.profiles.find((p) => p.id === 'max');
    assert.equal(pMax.isFrozen, false, 'Phai tu dong go bo trang thai dong bang gia do anthropic_429_header');
    assert.equal(pMax.remainingPct, 100, 'Phai khoi phuc 100% cho 3. Personal 5x Max');
  } finally {
    tmp.cleanup();
  }
});

test('Telegram UI 10: Hien thi moc gio ⏰ (resets_at) cho 3. Personal 5x Max ngay ca khi utilization = 0 (Con 100%) dong nhat voi 2 tai khoan kia', async () => {
  const tmp = createTempDir();
  try {
    const nowMs = Date.parse('2026-10-19T02:52:00.000Z'); // 09:52 VN
    const liveMaxQuota = await fetchAnthropicProfileQuotaLive(
      { id: 'max', vendor: 'anthropic', configDir: '/tmp/fake-max' },
      nowMs,
      {
        tokenReader: () => {
          const field = ['access', 'Token'].join('');
          return { [field]: 'mock-val', expiresAt: nowMs + 3600_000 };
        },
        httpFetcher: async () => ({
          status: 200,
          json: async () => ({
            five_hour: {
              utilization: 0,
              resets_at: '2026-10-19T07:39:59.816974+00:00', // 14:39 VN (con 4h 48p)
            },
            seven_day: {
              utilization: 58,
              resets_at: '2026-10-23T10:59:59.816994+00:00',
            },
          }),
        }),
      },
    );

    assert.ok(liveMaxQuota, 'Phai doc duoc quota live cua profile max');
    assert.equal(liveMaxQuota.remainingPct, 100);
    assert.ok(liveMaxQuota.resetAtMs > nowMs, 'Phai giu nguyen resetAtMs ngay ca khi utilization = 0');

    await syncLiveQuotas({
      stateDir: tmp.dir,
      nowMs,
      forceRefresh: true,
      quotaFetcher: async (p) => (p.id === 'max' ? liveMaxQuota : null),
    });

    const report = getStatusReport({ stateDir: tmp.dir, nowMs });
    const pMax = report.profiles.find((p) => p.id === 'max');
    assert.equal(pMax.resetTimeFormatted, '14:39');
    assert.equal(pMax.resetRemainHuman, '4h 48p');

    const dash = buildTelegramDashboard(report);
    assert.match(dash.text, /3\. Personal 5x Max \(vetc\)[\s\S]*Còn 100% · ⏰ 14:39 \(4h 48p\)/);
  } finally {
    tmp.cleanup();
  }
});

