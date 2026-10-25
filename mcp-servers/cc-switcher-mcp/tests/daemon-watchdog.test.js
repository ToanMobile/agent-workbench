import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { startSwitcherDaemon } from '../src/daemon.js';

// 25/10: daemon chạy từ 22/10 im lặng từ 08:11 (sau loạt lỗi mạng Telegram) và bỏ qua cú bấm Approve tới khi khởi động lại.
// Vòng setInterval giữ cờ inFlight: một await không bao giờ trả về giữ nó true mãi, mọi lượt sau return ngay, không một dòng log.
// Lượt kẹt quá tickTimeoutMs: ghi lỗi và thoát khác 0 để launchd (KeepAlive) khởi động lại daemon sạch.
function stateDirWithToken() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ccsw-watchdog-'));
  fs.writeFileSync(path.join(dir, 'telegram.env'), 'TELEGRAM_BOT_TOKEN=test-token\nTELEGRAM_CHAT_ID=1\n');
  return dir;
}

function waitFor(pred, ms) {
  return new Promise((resolve) => {
    const t0 = Date.now();
    const iv = setInterval(() => {
      if (pred() || Date.now() - t0 > ms) {
        clearInterval(iv);
        resolve(pred());
      }
    }, 10);
  });
}

test('lượt poll treo mãi: daemon ghi lỗi và thoát mã 1 (launchd khởi động lại), không kẹt im lặng', async () => {
  const stateDir = stateDirWithToken();
  const exits = [];
  const daemon = await startSwitcherDaemon({
    stateDir,
    logFile: path.join(stateDir, 'none.log'),
    pollIntervalMs: 20,
    tickTimeoutMs: 150,
    ensureMenu: () => {},
    fetchUpdates: () => new Promise(() => {}),
    exit: (code) => exits.push(code),
  });
  try {
    const fired = await waitFor(() => exits.length > 0, 2000);
    assert.equal(fired, true, 'daemon kẹt im lặng: không thoát sau khi lượt poll treo quá tickTimeoutMs');
    assert.deepEqual(exits, [1]);
  } finally {
    daemon.stop();
    fs.rmSync(stateDir, { recursive: true, force: true });
  }
});

test('đối chứng: poll trả về bình thường thì watchdog không bắn', async () => {
  const stateDir = stateDirWithToken();
  const exits = [];
  let polls = 0;
  const daemon = await startSwitcherDaemon({
    stateDir,
    logFile: path.join(stateDir, 'none.log'),
    pollIntervalMs: 20,
    tickTimeoutMs: 150,
    ensureMenu: () => {},
    fetchUpdates: async () => { polls += 1; return []; },
    exit: (code) => exits.push(code),
  });
  try {
    await waitFor(() => polls >= 15, 2000);
    assert.ok(polls >= 15, `poll chạy quá ít: ${polls}`);
    assert.deepEqual(exits, []);
  } finally {
    daemon.stop();
    fs.rmSync(stateDir, { recursive: true, force: true });
  }
});
