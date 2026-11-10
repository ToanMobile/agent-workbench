// #897 (residual review C2 #896 + C4 #902). Temp dirs only, never a real repo or ~/.cc-switch.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { addRepo, removeRepo, setRepoAccount } from '../src/profiles.js';
import { runPanelAction } from '../src/panel.js';
import { processIncomingTelegramUpdates } from '../src/daemon.js';

function setup() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-897-'));
  const stateDir = path.join(root, 'state');
  fs.mkdirSync(stateDir);
  fs.writeFileSync(path.join(stateDir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos_toan' }));
  const mkRepo = (name) => {
    const p = path.join(root, 'code', name);
    fs.mkdirSync(path.join(p, '.git'), { recursive: true });
    return p;
  };
  return { root, stateDir, mkRepo, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}

test('R1: repos.json hỏng ⇒ addRepo/removeRepo ném INVALID_INPUT, giữ nguyên byte', () => {
  const s = setup();
  try {
    const broken = '{"custom":[{"name":"a","path":"/x"}],"hidden":["/y"],"defaults":false,';
    const file = path.join(s.stateDir, 'repos.json');
    fs.writeFileSync(file, broken);
    const repo = s.mkRepo('r1');
    assert.throws(() => addRepo({ stateDir: s.stateDir, repoPath: repo, account: 'finos_toan' }), { code: 'INVALID_INPUT' });
    assert.throws(() => removeRepo({ stateDir: s.stateDir, repoPath: repo }), { code: 'INVALID_INPUT' });
    assert.equal(fs.readFileSync(file, 'utf8'), broken);
  } finally { s.cleanup(); }
});

test('R2: cooldown minutes rỗng / khoảng trắng / 0x0 / thiếu bị từ chối', async () => {
  const s = setup();
  try {
    for (const m of ['', ' ', '0x0', '1e1', undefined, null, '1.5']) {
      await assert.rejects(runPanelAction('cooldown', { minutes: m }, { stateDir: s.stateDir }), { code: 'INVALID_INPUT' }, `minutes=${JSON.stringify(m)}`);
    }
    const ok = await runPanelAction('cooldown', { minutes: '0' }, { stateDir: s.stateDir });
    assert.equal(ok.claudeSwitchCooldownSec, 0);
    const ok2 = await runPanelAction('cooldown', { minutes: 15 }, { stateDir: s.stateDir });
    assert.equal(ok2.claudeSwitchCooldownSec, 900);
  } finally { s.cleanup(); }
});

test('symlink: .claude ra ngoài repo và settings.local.json symlink không bị ghi xuyên', () => {
  const s = setup();
  try {
    fs.writeFileSync(path.join(s.stateDir, 'repos.json'), JSON.stringify({ custom: [], hidden: [], defaults: false }));
    const outside = path.join(s.root, 'outside');
    fs.mkdirSync(outside);
    const repo = s.mkRepo('sym');
    fs.symlinkSync(outside, path.join(repo, '.claude'));
    assert.throws(() => addRepo({ stateDir: s.stateDir, repoPath: repo, account: 'finos_toan' }), { code: 'INVALID_INPUT' });
    assert.deepEqual(fs.readdirSync(outside), []);

    const repo2 = s.mkRepo('sym2');
    fs.mkdirSync(path.join(repo2, '.claude'));
    const target = path.join(s.root, 'target.json');
    fs.writeFileSync(target, '{}');
    fs.symlinkSync(target, path.join(repo2, '.claude', 'settings.local.json'));
    assert.throws(() => addRepo({ stateDir: s.stateDir, repoPath: repo2, account: 'finos_toan' }), { code: 'INVALID_INPUT' });
    assert.equal(fs.readFileSync(target, 'utf8'), '{}');
    assert.ok(fs.lstatSync(path.join(repo2, '.claude', 'settings.local.json')).isSymbolicLink());
  } finally { s.cleanup(); }
});

test('findKnownRepo bỏ "/" cuối như addRepo', () => {
  const s = setup();
  try {
    fs.writeFileSync(path.join(s.stateDir, 'repos.json'), JSON.stringify({ custom: [], hidden: [], defaults: false }));
    const repo = s.mkRepo('slash');
    addRepo({ stateDir: s.stateDir, repoPath: repo, account: 'finos_toan' });
    const res = setRepoAccount({ stateDir: s.stateDir, repoPath: `${repo}/`, account: 'finos_linh' });
    assert.equal(res.account, 'finos_linh');
  } finally { s.cleanup(); }
});

test('sendMessage trả lời lệnh ném lỗi không làm mất update sb:ap: cùng batch', async () => {
  const s = setup();
  try {
    fs.writeFileSync(path.join(s.stateDir, 'telegram.env'), 'TELEGRAM_BOT_TOKEN=123:abc\nTELEGRAM_CHAT_ID=42\n');
    const calls = [];
    const apiCaller = async (_t, method, body) => {
      calls.push({ method, body });
      if (method === 'sendMessage') throw new Error('network down');
      return {};
    };
    const updates = [
      { update_id: 1, message: { text: '/status', chat: { id: 42 } } },
      { update_id: 2, callback_query: { id: 'cb', data: 'sb:zz', message: { chat: { id: 42 }, message_id: 7 } } },
    ];
    const next = await processIncomingTelegramUpdates(updates, { stateDir: s.stateDir, apiCaller });
    assert.equal(next, 3);
    assert.ok(calls.some((c) => c.method === 'answerCallbackQuery'), 'update thứ hai phải được xử lý');
  } finally { s.cleanup(); }
});
