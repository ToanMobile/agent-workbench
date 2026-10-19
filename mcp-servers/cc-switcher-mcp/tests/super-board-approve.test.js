// Approve button comments `done` on the approval-request source. A foreign chat is refused.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { saveTelegramConfig, loadTelegramConfig } from '../src/telegram.js';
import { processIncomingTelegramUpdates } from '../src/daemon.js';

const HEAD = 'ab'.repeat(20);

function temp() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sb-approve-'));
  fs.writeFileSync(path.join(dir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos' }));
  return dir;
}

test('matching chat comments done on the approval-request source and does not merge', async () => {
  const dir = temp();
  const approvals = path.join(dir, 'approvals');
  fs.mkdirSync(approvals);
  const pointerId = '0123456789abcdef';
  fs.writeFileSync(path.join(approvals, `${pointerId}.json`), JSON.stringify({
    repo: 'owner/repo', pr: 12, head: HEAD, source: 12,
  }));
  saveTelegramConfig(dir, { botToken: 'tok', chatId: '111' });
  const ghCalls = [];
  const apiCalls = [];
  await processIncomingTelegramUpdates([{
    update_id: 1,
    callback_query: {
      id: 'cb-match',
      data: `sb:ap:${pointerId}`,
      message: { chat: { id: 111 }, message_id: 4 },
      from: { id: 111 },
    },
  }], {
    stateDir: dir,
    apiCaller: async (bot, method, body) => { apiCalls.push({ method, body }); },
    callbackOpts: {
      approvalsDir: approvals,
      readComments: async () => [{
        source: 34,
        body: `approval-request: {"head":"${HEAD}","pr":12,"repo":"owner/repo"}`,
      }],
      gh: async (args) => { ghCalls.push(args); },
    },
  });
  assert.equal(ghCalls.length, 1);
  const flat = ghCalls[0].join(' ');
  assert.match(flat, /repos\/owner\/repo\/issues\/34\/comments/);
  assert.match(flat, /body=done/);
  assert.equal(flat.includes('merge'), false);
  assert.equal(apiCalls.some((c) => c.method === 'answerCallbackQuery'), true);
  fs.rmSync(dir, { recursive: true, force: true });
});

test('foreign chat is refused and does not comment or bind', async () => {
  const dir = temp();
  saveTelegramConfig(dir, { botToken: 'tok', chatId: '111' });
  const apiCalls = [];
  const ghCalls = [];
  await processIncomingTelegramUpdates([{
    update_id: 2,
    callback_query: {
      id: 'cb-foreign',
      data: 'sb:ap:0123456789abcdef',
      message: { chat: { id: 222 }, message_id: 5 },
      from: { id: 222 },
    },
  }], {
    stateDir: dir,
    apiCaller: async (bot, method, body) => { apiCalls.push({ method, body }); },
    callbackOpts: { gh: async (args) => { ghCalls.push(args); } },
  });
  assert.equal(apiCalls.length, 1);
  assert.equal(apiCalls[0].method, 'answerCallbackQuery');
  assert.match(apiCalls[0].body.text, /không được phép/);
  assert.equal(ghCalls.length, 0);
  assert.equal(loadTelegramConfig(dir).chatId, '111');
  fs.rmSync(dir, { recursive: true, force: true });
});

test('an sb callback from an unbound chat does not bind that chat', async () => {
  const dir = temp();
  saveTelegramConfig(dir, { botToken: 'tok', chatId: '' });
  const apiCalls = [];
  await processIncomingTelegramUpdates([{
    update_id: 3,
    callback_query: {
      id: 'cb-new',
      data: 'sb:ap:0123456789abcdef',
      message: { chat: { id: 555 }, message_id: 6 },
      from: { id: 555 },
    },
  }], {
    stateDir: dir,
    apiCaller: async (bot, method, body) => { apiCalls.push({ method, body }); },
  });
  assert.equal(loadTelegramConfig(dir).chatId, '');
  assert.equal(apiCalls[0].method, 'answerCallbackQuery');
  assert.match(apiCalls[0].body.text, /không được phép/);
  fs.rmSync(dir, { recursive: true, force: true });
});
