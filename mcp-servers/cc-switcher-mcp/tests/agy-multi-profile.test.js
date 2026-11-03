// Antigravity nhieu profile: moi tai khoan AGY co HOME rieng (agy chi tach duoc tai khoan qua HOME), giong CLAUDE_CONFIG_DIR cua Claude.
import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import os from 'node:os';
import { DEFAULT_PROFILES } from '../src/profiles.js';

const agy = DEFAULT_PROFILES.filter((p) => p.vendor === 'google');

test('hai profile AGY co homeDir rieng, khac nhau, khong phai HOME that', () => {
  assert.equal(agy.length, 2);
  const homes = agy.map((p) => p.homeDir);
  assert.ok(homes.every((h) => typeof h === 'string' && h.length > 0), 'moi profile AGY can homeDir');
  assert.equal(new Set(homes).size, 2, 'homeDir phai khac nhau');
  assert.ok(!homes.includes(os.homedir()));
});

test('configDir cua AGY nam trong homeDir cua chinh no, khong chung ~/.gemini', () => {
  for (const p of agy) {
    assert.equal(p.homeDir, path.join(os.homedir(), `.agy-${p.id}`));
    assert.equal(p.configDir, path.join(p.homeDir, '.gemini'));
  }
});

test('buildSafeEnvForProfile: profile AGY nhan HOME rieng, Claude khong bi dat HOME', async () => {
  const { buildSafeEnvForProfile } = await import('../src/profiles.js');
  for (const p of agy) assert.equal(buildSafeEnvForProfile(p).HOME, p.homeDir);
  const claude = DEFAULT_PROFILES.find((p) => p.vendor === 'anthropic');
  assert.equal(buildSafeEnvForProfile(claude).HOME, undefined);
});
