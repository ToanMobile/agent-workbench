// Profile khong dung gan day ma token het han la binh thuong: noi nhe, khong bao dong nhu loi.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { getStatusReport, saveSwitcherState } from '../src/profiles.js';
import { formatStatusText, quotaIssueText } from '../src/status-text.js';

const NOW = Date.parse('2026-11-09T08:00:00.000Z');
const old = { remainingPct: 40, usedPct: 60, resetAtMs: NOW - 3600_000, source: 'anthropic_oauth', updatedAtMs: NOW - 30 * 3600_000 };

test('token het han + profile khong dung: cau nhe "Chua dung gan day"', () => {
  const idle = quotaIssueText('token_expired', null, true);
  assert.match(idle, /Chưa dùng gần đây/);
  assert.match(idle, /bình thường/);
  assert.match(idle, /Đăng nhập lại/);
  assert.doesNotMatch(idle, /không làm mới được/);
});

test('token het han + profile dang dung: van la canh bao ro', () => {
  const active = quotaIssueText('token_expired', null, false);
  assert.doesNotMatch(active, /Chưa dùng gần đây/);
  assert.match(active, /hết hạn/);
});

test('ly do khac (sai tai khoan) khong bi lam nhe du profile khong dung', () => {
  assert.match(quotaIssueText('wrong_account', { actual: 'a@b.c', expected: 'd@e.f' }, true), /Sai tài khoản/);
});

test('bao cao: profile khong active hien cau nhe, profile active hien canh bao', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-idle-'));
  try {
    fs.writeFileSync(path.join(dir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos_toan' }));
    saveSwitcherState(dir, {
      activeProfileId: 'finos_toan',
      quotaCache: { finos_toan: old, finos_linh: old },
      quotaIssues: { finos_toan: { reason: 'token_expired', atMs: NOW }, finos_linh: { reason: 'token_expired', atMs: NOW } },
    });
    const text = formatStatusText(getStatusReport({ stateDir: dir, nowMs: NOW, repos: [{ name: 'khong-repo', path: path.join(dir, 'khong-repo') }] }));
    const lines = text.split('\n');
    const at = (name) => lines[lines.findIndex((l) => l.includes(name)) + 1];
    assert.doesNotMatch(at('FinOS Linh'), /không làm mới được/);
    assert.match(at('FinOS Linh'), /Chưa dùng gần đây/);
    assert.doesNotMatch(at('FinOS Toan —'), /Chưa dùng gần đây/);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
