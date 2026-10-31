// Bang dieu khien CC Switcher da go khoi Telegram (chuyen sang web). Telegram chi con canh bao va nut duyet super-board.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import * as telegram from '../src/telegram.js';
import { processIncomingTelegramUpdates, startSwitcherDaemon } from '../src/daemon.js';
import { getStatusReport } from '../src/profiles.js';

const SRC = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'src');

function createTempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-tg-'));
  fs.writeFileSync(path.join(dir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos' }, null, 2));
  return { dir, cleanup: () => fs.rmSync(dir, { recursive: true, force: true }) };
}

function fakeApi() {
  const calls = [];
  const api = async (_tok, method, body) => {
    calls.push({ method, body });
    return true;
  };
  return { calls, api };
}

test('khong con export nao dung bang dieu khien Telegram', () => {
  for (const name of ['buildTelegramDashboard', 'buildReplyKeyboardMarkup', 'formatStatusForTelegram', 'ensureTelegramBotMenu']) {
    assert.equal(name in telegram, false, `${name} van con`);
  }
  for (const f of fs.readdirSync(SRC)) {
    const text = fs.readFileSync(path.join(SRC, f), 'utf8');
    assert.doesNotMatch(text, /CC SWITCHER · BẢNG ĐIỀU KHIỂN/, `${f} van con tieu de bang dieu khien Telegram`);
    assert.doesNotMatch(text, /callback_data:\s*`?['"]?(sw|fsw|act|cd):/, `${f} van tao nut bang dieu khien`);
  }
});

test('tin nhan /status, /switch, nut ban phim cu: chi tra link web, go ban phim ghim, khong doi tai khoan', async () => {
  const tmp = createTempDir();
  try {
    telegram.saveTelegramConfig(tmp.dir, { botToken: ['111222333', 'AAH_removed_panel_token_xyz'].join(':'), chatId: '4242' });
    const { calls, api } = fakeApi();
    let id = 1;
    for (const text of ['/status', '/menu', '/start', '/switch 4', '/rotate', '/limit', '/cooldown 0', '🎛 Bảng điều khiển', '🔄 Xoay vòng an toàn', '4']) {
      await processIncomingTelegramUpdates([{ update_id: id++, message: { chat: { id: 4242 }, text } }], { stateDir: tmp.dir, apiCaller: api });
    }
    const sends = calls.filter((c) => c.method === 'sendMessage');
    assert.equal(sends.length, 10);
    for (const s of sends) {
      assert.match(s.body.text, /ai-factory\.localhost:4317\/cc-switcher/);
      assert.deepEqual(s.body.reply_markup, { remove_keyboard: true });
      assert.ok(!JSON.stringify(s.body).includes('inline_keyboard'));
    }
    const report = getStatusReport({ stateDir: tmp.dir });
    assert.equal(report.activeProfileId, 'finos', 'Telegram khong duoc doi tai khoan nua');
    assert.equal(report.policy.claudeSwitchCooldownSec, 900, '/cooldown khong con tac dung');
  } finally {
    tmp.cleanup();
  }
});

test('bam nut cu (sw:, fsw:, act:, cd:) tren tin nhan cu: toast chi duong + go hang nut, khong doi trang thai', async () => {
  const tmp = createTempDir();
  try {
    telegram.saveTelegramConfig(tmp.dir, { botToken: ['111222333', 'AAH_removed_panel_token_xyz'].join(':'), chatId: '4242' });
    const { calls, api } = fakeApi();
    const datas = ['sw:grok', 'fsw:finos_team', 'act:rotate', 'act:limit', 'act:unfreeze_all', 'act:balance_repos', 'cd:0'];
    let id = 1;
    for (const data of datas) {
      await processIncomingTelegramUpdates([{
        update_id: id++,
        callback_query: { id: `cb-${data}`, data, from: { id: 4242 }, message: { message_id: 900 + id, chat: { id: 4242 } } },
      }], { stateDir: tmp.dir, apiCaller: api });
    }
    const answers = calls.filter((c) => c.method === 'answerCallbackQuery');
    const clears = calls.filter((c) => c.method === 'editMessageReplyMarkup');
    assert.equal(answers.length, datas.length);
    assert.equal(clears.length, datas.length);
    for (const a of answers) assert.match(a.body.text, /ai-factory\.localhost:4317\/cc-switcher/);
    for (const c of clears) assert.deepEqual(c.body.reply_markup, { inline_keyboard: [] });
    assert.equal(calls.some((c) => c.method === 'editMessageText'), false);
    const report = getStatusReport({ stateDir: tmp.dir });
    assert.equal(report.activeProfileId, 'finos');
    assert.equal(report.policy.claudeSwitchCooldownSec, 900);
  } finally {
    tmp.cleanup();
  }
});

test('nut duyet super-board (sb:ap:) van di dung duong duyet, khong bi coi la nut bang dieu khien cu', async () => {
  const res = await telegram.handleTelegramCallback({ id: 'x', data: 'sb:ap:zz' }, {});
  assert.equal(res.toastText, 'Nút duyệt không hợp lệ.');
  assert.equal(res.clearButtons, undefined);
});

test('daemon khoi dong: don menu lenh cu (deleteMyCommands + nut Menu mac dinh), khong dang ky lai lenh bang dieu khien', async () => {
  const { calls, api } = fakeApi();
  assert.equal(await telegram.clearLegacyTelegramPanel('123:abc', api), true);
  assert.deepEqual(calls.map((c) => c.method), ['deleteMyCommands', 'setChatMenuButton']);
  assert.deepEqual(calls[1].body, { menu_button: { type: 'default' } });
  assert.equal(calls.some((c) => c.method === 'setMyCommands'), false);
  assert.equal(await telegram.clearLegacyTelegramPanel('', api), false);

  const tmp = createTempDir();
  try {
    telegram.saveTelegramConfig(tmp.dir, { botToken: ['111222333', 'AAH_removed_panel_token_xyz'].join(':'), chatId: '4242' });
    let menuToken = null;
    const d = await startSwitcherDaemon({ stateDir: tmp.dir, pollIntervalMs: 60_000, ensureMenu: (tok) => { menuToken = tok; }, fetchUpdates: async () => [] });
    d.stop();
    assert.ok(menuToken, 'daemon phai goi buoc don menu khi co token');
  } finally {
    tmp.cleanup();
  }
});

test('canh bao Telegram chi con van ban + link web, khong kem ban phim bang dieu khien', async () => {
  const tmp = createTempDir();
  const realFetch = globalThis.fetch;
  try {
    telegram.saveTelegramConfig(tmp.dir, { botToken: ['111222333', 'AAH_removed_panel_token_xyz'].join(':'), chatId: '4242' });
    let sent = null;
    globalThis.fetch = async (_url, init) => {
      sent = JSON.parse(init.body);
      return { ok: true, status: 200, json: async () => ({ ok: true, result: {} }) };
    };
    const r = await telegram.sendTelegramNotification('🚨 test 429', { stateDir: tmp.dir });
    assert.equal(r.sent, true);
    assert.match(sent.text, /^🚨 test 429/);
    assert.match(sent.text, /ai-factory\.localhost:4317\/cc-switcher/);
    assert.equal('reply_markup' in sent, false);
  } finally {
    globalThis.fetch = realFetch;
    tmp.cleanup();
  }
});
