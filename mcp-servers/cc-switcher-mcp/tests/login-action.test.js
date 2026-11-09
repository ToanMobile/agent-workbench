// Nut "Dang nhap lai": thao tac login mo Terminal chay `claude auth login` voi dung thu muc cau hinh cua profile.
import test from 'node:test';
import assert from 'node:assert/strict';
import { LOGIN_ACTION, PANEL_ACTIONS, runPanelAction } from '../src/panel.js';
import { DEFAULT_PROFILES } from '../src/profiles.js';
import { quotaIssueText } from '../src/status-text.js';

test('login la thao tac rieng, khong doi hop dong PANEL_ACTIONS', () => {
  assert.equal(LOGIN_ACTION, 'login');
  assert.equal(PANEL_ACTIONS.includes('login'), false);
});

test('login mo launcher voi thu muc va email cua profile, khong nhan duong dan tu ngoai', async () => {
  const calls = [];
  const lua = DEFAULT_PROFILES.find((p) => p.id === 'finos_lua');
  const res = await runPanelAction('login', { target: 'finos_lua', configDir: '/etc', email: 'x@y.z' }, { loginLauncher: (c) => { calls.push(c); } });
  assert.equal(res.ok, true);
  assert.equal(calls.length, 1);
  assert.match(calls[0].command, /auth login/);
  assert.ok(calls[0].command.includes(`CLAUDE_CONFIG_DIR='${lua.configDir}'`));
  assert.ok(calls[0].command.includes(`--email '${lua.expectedEmail}'`));
  assert.equal(calls[0].command.includes('/etc'), false);
  assert.equal(calls[0].command.includes('x@y.z'), false);
});

test('login chi cho profile Claude hop le', async () => {
  for (const target of ['grok', 'antigravity_pro', 'khong-co', '', undefined, "finos_lua'; rm -rf ~; '"]) {
    await assert.rejects(() => runPanelAction('login', { target }, { loginLauncher: () => { throw new Error('khong duoc goi'); } }), /hợp lệ/, String(target));
  }
});

test('launcher loi thi tra ok:false, khong nem', async () => {
  const res = await runPanelAction('login', { target: 'finos_linh' }, { loginLauncher: () => { throw new Error('osascript failed'); } });
  assert.equal(res.ok, false);
  assert.match(res.error, /Terminal/);
});

test('thong bao token het han chi ve nut Dang nhap lai, khong bat tu go lenh', () => {
  assert.match(quotaIssueText('token_expired'), /Đăng nhập lại/);
  assert.doesNotMatch(quotaIssueText('token_expired'), /chưa cần/);
});
