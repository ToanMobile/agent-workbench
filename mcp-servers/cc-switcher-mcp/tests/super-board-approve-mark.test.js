// Chủ repo 08/11: bấm Approve trên Telegram ghi `done` xong thì chính tin đó phải đổi sang "đã duyệt" và bỏ nút,
// không còn trông như đang chờ. Duyệt bị từ chối thì tin giữ nguyên (người bấm còn đọc toast và thử lại được).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { saveTelegramConfig } from '../src/telegram.js';
import { processIncomingTelegramUpdates } from '../src/daemon.js';

const HEAD = 'cd'.repeat(20);
const ID = 'fedcba9876543210';
const TEXT = '🙋 PR #12 cần duyệt · head cdcdcdc';

async function press({ request, message = { chat: { id: 111 }, message_id: 7, text: TEXT } }) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sb-approve-mark-'));
  fs.writeFileSync(path.join(dir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos_toan' }));
  const approvals = path.join(dir, 'approvals');
  fs.mkdirSync(approvals);
  fs.writeFileSync(path.join(approvals, `${ID}.json`), JSON.stringify({ repo: 'owner/repo', pr: 12, head: HEAD, source: 12 }));
  saveTelegramConfig(dir, { botToken: 'tok', chatId: '111' });
  const apiCalls = [];
  try {
    await processIncomingTelegramUpdates([{
      update_id: 1,
      callback_query: { id: 'cb', data: `sb:ap:${ID}`, from: { id: 111 }, message },
    }], {
      stateDir: dir,
      apiCaller: async (bot, method, body) => { apiCalls.push({ method, body }); },
      callbackOpts: {
        approvalsDir: approvals,
        ghRead: async (args) => (args.join(' ').includes('/permission')
          ? JSON.stringify({ permission: 'admin' })
          : JSON.stringify({ headRefOid: HEAD, state: 'OPEN', body: '', closingIssuesReferences: [] })),
        readComments: async () => [{
          source: 12, id: 1, user: { login: 'owner', type: 'User' },
          created_at: '2026-11-08T10:00:00Z', updated_at: '2026-11-08T10:00:00Z',
          body: `approval-request: {"head":"${request}","pr":12,"repo":"owner/repo","scope":"${'0'.repeat(64)}"}`,
        }],
        gh: async () => {},
      },
    });
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  return apiCalls;
}

test('duyệt thành công: tin đổi sang "đã duyệt", giữ nội dung cũ, bỏ nút', async () => {
  const calls = await press({ request: HEAD });
  const edit = calls.find((c) => c.method === 'editMessageText');
  assert.ok(edit, `không thấy editMessageText: ${JSON.stringify(calls.map((c) => c.method))}`);
  assert.equal(edit.body.chat_id, '111');
  assert.equal(edit.body.message_id, 7);
  assert.ok(edit.body.text.startsWith(TEXT), edit.body.text);
  assert.match(edit.body.text, /✅ Đã duyệt/);
  assert.deepEqual(edit.body.reply_markup, { inline_keyboard: [] });
});

// Review PR #1059 (P3): tin không còn truy cập được (MaybeInaccessibleMessage) hay tin caption không có `text`: chỉ bỏ nút,
// không ghi đè nội dung gốc bằng mỗi dòng "đã duyệt".
test('duyệt thành công trên tin không có text: chỉ bỏ nút, không editMessageText', async () => {
  const calls = await press({ request: HEAD, message: { chat: { id: 111 }, message_id: 7, date: 0 } });
  assert.equal(calls.some((c) => c.method === 'editMessageText'), false);
  const clear = calls.find((c) => c.method === 'editMessageReplyMarkup');
  assert.ok(clear, JSON.stringify(calls.map((c) => c.method)));
  assert.deepEqual(clear.body.reply_markup, { inline_keyboard: [] });
});

test('duyệt bị từ chối (request của head khác): tin giữ nguyên, không sửa', async () => {
  const calls = await press({ request: 'ef'.repeat(20) });
  assert.equal(calls.some((c) => c.method === 'editMessageText' || c.method === 'editMessageReplyMarkup'), false);
  assert.equal(calls.some((c) => c.method === 'answerCallbackQuery'), true);
});
