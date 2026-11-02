// C4 (#902) go bang dieu khien Telegram: 4 hanh vi CON TON TAI truoc day chi duoc kiem qua test Telegram cu
// (telegram-ui.test.js UI 2/3/7, switcher.test.js /switch 4). Kiem lai truc tiep o tang profiles/daemon.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {
  resolveProfile,
  switchProfile,
  reportRateLimit,
  resetLocks,
  loadSwitcherState,
  getStatusReport,
  DEFAULT_REPOS,
} from '../src/profiles.js';
import { saveTelegramConfig } from '../src/telegram.js';
import { processIncomingTelegramUpdates } from '../src/daemon.js';

function createTempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-c4cov-'));
  fs.writeFileSync(path.join(dir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos' }, null, 2));
  return { dir, cleanup: () => fs.rmSync(dir, { recursive: true, force: true }) };
}

test('resolveProfile nhan so 1..6 (MCP switcher_switch, CLI --switch): "4" va 4 la antigravity, switchProfile target "4" doi tai khoan', () => {
  assert.equal(resolveProfile('4').id, 'antigravity');
  assert.equal(resolveProfile(4).id, 'antigravity');
  assert.equal(resolveProfile('1').id, 'finos');
  assert.throws(() => resolveProfile('7'), (err) => err.code === 'PROFILE_NOT_FOUND');
  const tmp = createTempDir();
  try {
    switchProfile({ stateDir: tmp.dir, target: '4', nowMs: Date.now(), enforceCooldown: false });
    assert.equal(getStatusReport({ stateDir: tmp.dir }).activeProfileId, 'antigravity');
  } finally {
    tmp.cleanup();
  }
});

test('resetLocks (Mo khoa 429 & cooldown tren web) xoa dong bang, lastClaudeSwitchAtMs va lastClaudeRateLimitAtMs', () => {
  const tmp = createTempDir();
  try {
    const t0 = 1_700_000_000_000;
    reportRateLimit({ stateDir: tmp.dir, nowMs: t0 });
    const before = loadSwitcherState(tmp.dir);
    assert.ok(before.lastClaudeRateLimitAtMs > 0);
    assert.ok(Object.keys(before.frozenUntil).length > 0);
    resetLocks(tmp.dir);
    const after = loadSwitcherState(tmp.dir);
    assert.deepEqual(after.frozenUntil, {});
    assert.equal(after.lastClaudeSwitchAtMs, 0);
    assert.equal(after.lastClaudeRateLimitAtMs, 0);
  } finally {
    tmp.cleanup();
  }
});

test('chia 3 repo finos + 3 repo finos_team: ca 2 tai khoan Claude isParallelActive, assignedRepoCount = 3', () => {
  const tmp = createTempDir();
  try {
    const repos = DEFAULT_REPOS.map((r) => {
      const repoPath = path.join(tmp.dir, 'repos', r.name);
      fs.mkdirSync(path.join(repoPath, '.claude'), { recursive: true });
      fs.writeFileSync(path.join(repoPath, '.claude', 'settings.local.json'), JSON.stringify({ account: r.defaultAccount }, null, 2));
      return { ...r, path: repoPath };
    });
    const report = getStatusReport({ stateDir: tmp.dir, repos });
    const byId = Object.fromEntries(report.profiles.map((p) => [p.id, p]));
    assert.equal(byId.finos.assignedRepoCount, 3);
    assert.equal(byId.finos_team.assignedRepoCount, 3);
    assert.equal(byId.finos.isParallelActive, true);
    assert.equal(byId.finos_team.isParallelActive, true);
    assert.equal(byId.max.assignedRepoCount, 0);
    assert.equal(byId.max.isParallelActive, false);
  } finally {
    tmp.cleanup();
  }
});

test('nut cu tren tin nhan cu: answerCallbackQuery dung callback_query_id, editMessageReplyMarkup dung chat_id + message_id', async () => {
  const tmp = createTempDir();
  try {
    saveTelegramConfig(tmp.dir, { botToken: ['111222333', 'AAH_c4_coverage_token_xyz'].join(':'), chatId: '11223344' });
    const calls = [];
    const api = async (_tok, method, body) => {
      calls.push({ method, body });
      return true;
    };
    await processIncomingTelegramUpdates([{
      update_id: 7,
      callback_query: { id: 'cbq-99', data: 'sw:antigravity', from: { id: 11223344 }, message: { message_id: 555, chat: { id: 11223344 } } },
    }], { stateDir: tmp.dir, apiCaller: api });
    const answer = calls.find((c) => c.method === 'answerCallbackQuery');
    const edit = calls.find((c) => c.method === 'editMessageReplyMarkup');
    assert.equal(answer.body.callback_query_id, 'cbq-99');
    assert.equal(String(edit.body.chat_id), '11223344');
    assert.equal(edit.body.message_id, 555);
  } finally {
    tmp.cleanup();
  }
});
