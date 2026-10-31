// Kiem thu hoi quy cho 5 loi phat hien qua dot Audit sau (Webhook 409 Conflict, Auto-bind Chat ID, Cooldown khong reset khi trung profile, Split-chunk log 429).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {
  fetchUpdatesSafely,
  loadTelegramConfig,
  saveTelegramConfig,
} from '../src/telegram.js';
import {
  processIncomingTelegramUpdates,
  createLogTailReader,
  detectRateLimitInLogChunk,
} from '../src/daemon.js';
import {
  loadSwitcherState,
  switchProfile,
} from '../src/profiles.js';

function createTempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-audit-'));
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

test('Audit Fix 1: fetchUpdatesSafely tu dong go deleteWebhook khi gap 409 Conflict va thu lai thanh cong', async () => {
  const calls = [];
  const fakeApiCaller = async (_token, method, body) => {
    calls.push({ method, body });
    if (method.startsWith('getUpdates') && calls.length === 1) {
      const err = new Error("Telegram API tra ve loi (409): Conflict: can't use getUpdates method while webhook is active");
      err.status = 409;
      throw err;
    }
    if (method === 'deleteWebhook') {
      return true;
    }
    return [{ update_id: 10, message: { chat: { id: 556677 }, text: '/status' } }];
  };

  const updates = await fetchUpdatesSafely('test-bot-key', 0, fakeApiCaller);
  assert.equal(updates.length, 1);
  assert.equal(calls.length, 3);
  assert.equal(calls[1].method, 'deleteWebhook');
  assert.deepEqual(calls[1].body, { drop_pending_updates: false });
});

test('Audit Fix 2: processIncomingTelegramUpdates tu dong luu chatId vao telegram.env khi nhan tin nhan dau tien', async () => {
  const tmp = createTempDir();
  try {
    const token = ['999888777', 'AAH_audit_test_secret_key_12345'].join(':');
    saveTelegramConfig(tmp.dir, { botToken: token, chatId: '' });
    assert.equal(loadTelegramConfig(tmp.dir).chatId, '');

    const sentMessages = [];
    const fakeApiCaller = async (_tok, method, body) => {
      if (method === 'sendMessage') sentMessages.push(body);
      return true;
    };

    const nextOffset = await processIncomingTelegramUpdates(
      [{ update_id: 42, message: { chat: { id: 88990011 }, text: '/status' } }],
      { stateDir: tmp.dir, currentOffset: 0, apiCaller: fakeApiCaller },
    );

    assert.equal(nextOffset, 43);
    assert.equal(loadTelegramConfig(tmp.dir).chatId, '88990011');
    assert.equal(sentMessages.length, 1);
    assert.equal(sentMessages[0].chat_id, '88990011');
    assert.match(sentMessages[0].text, /ai-factory\.localhost:4317\/cc-switcher/);
  } finally {
    tmp.cleanup();
  }
});

test('Audit Fix 3: switchProfile sang dung profile dang active khong reset moc lastClaudeSwitchAtMs', () => {
  const tmp = createTempDir();
  try {
    const t1 = 1_700_000_000_000;
    switchProfile({ stateDir: tmp.dir, target: 'finos_team', nowMs: t1, enforceCooldown: false });
    assert.equal(loadSwitcherState(tmp.dir).lastClaudeSwitchAtMs, t1);

    // Goi lai switchProfile vao chinh finos_team o t2 -> khong duoc ghi de lastClaudeSwitchAtMs thanh t2
    const t2 = t1 + 120_000;
    switchProfile({ stateDir: tmp.dir, target: 'finos_team', nowMs: t2, enforceCooldown: true });
    assert.equal(loadSwitcherState(tmp.dir).lastClaudeSwitchAtMs, t1);
  } finally {
    tmp.cleanup();
  }
});

test('Audit Fix 4: createLogTailReader ghep duoc dong log 429 bi cat doi giua 2 lan ghi file', () => {
  const tmp = createTempDir();
  try {
    const logFile = path.join(tmp.dir, 'cc-switch.log');
    fs.writeFileSync(logFile, 'Init log\n');
    const reader = createLogTailReader(logFile);

    // Lan ghi 1: chi moi ghi mot nua dong loi
    fs.appendFileSync(logFile, 'Error: HTTP 429 ');
    const chunk1 = reader.readNewChunk();
    assert.equal(detectRateLimitInLogChunk(chunk1), false);

    // Lan ghi 2: ghi not phan con lai "Too Many Requests\n"
    fs.appendFileSync(logFile, 'Too Many Requests\n');
    const chunk2 = reader.readNewChunk();
    assert.equal(detectRateLimitInLogChunk(chunk2), true);
  } finally {
    tmp.cleanup();
  }
});
