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

test('thoát giữa batch: khởi động lại không phát lại update đã nhận (offset lưu xuống đĩa TRƯỚC khi xử lý)', async () => {
  // Review 25/10: offset chỉ trong bộ nhớ, gán sau cả batch -> watchdog thoát giữa batch thì khởi động lại với offset 0, Telegram trả
  // lại đúng batch đó: act:rotate / act:swap_repos / `done` chạy lại lần nữa, và update gây treo làm daemon crash-loop.
  const stateDir = stateDirWithToken();
  const exits = [];
  let served = false;
  const d1 = await startSwitcherDaemon({
    stateDir,
    logFile: path.join(stateDir, 'none.log'),
    pollIntervalMs: 20,
    tickTimeoutMs: 150,
    ensureMenu: () => {},
    fetchUpdates: async () => {
      if (served) return [];
      served = true;
      return [{ update_id: 41, message: { chat: { id: 1 }, text: '/status' } }];
    },
    apiCaller: () => new Promise(() => {}),   // gửi trả lời treo: lượt kẹt ngay giữa batch
    exit: (code) => exits.push(code),
  });
  const offsets = [];
  try {
    await waitFor(() => exits.length > 0, 3000);
    d1.stop();
    assert.deepEqual(exits, [1], 'setup: watchdog không thoát khi xử lý update treo');
    const d2 = await startSwitcherDaemon({
      stateDir,
      logFile: path.join(stateDir, 'none.log'),
      pollIntervalMs: 20,
      tickTimeoutMs: 2000,
      ensureMenu: () => {},
      fetchUpdates: async (_token, offset) => { offsets.push(offset); return []; },
      exit: () => {},
    });
    await waitFor(() => offsets.length > 0, 2000);
    d2.stop();
    assert.equal(offsets[0], 42, `khởi động lại poll từ offset ${offsets[0]}: update 41 sẽ bị xử lý lại`);
  } finally {
    d1.stop();
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
