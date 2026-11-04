// Doi tai khoan Antigravity cho antigravity-pm-mcp (review/audit) ngay tu cc-switcher: ghi agyProfile vao ~/.antigravity-pm.json,
// giu nguyen cac khoa khac, chi nhan profile Antigravity (vendor google), khong dong vao tai khoan mac dinh (Claude).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { getPmAgyProfile, setPmAgyProfile } from '../src/profiles.js';

function cfgFile(t, initial) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pm-acct-'));
  const file = path.join(dir, '.antigravity-pm.json');
  if (initial !== undefined) fs.writeFileSync(file, typeof initial === 'string' ? initial : JSON.stringify(initial));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return file;
}

test('chua khai thi null; dat antigravity_pro ghi agyProfile va giu cac khoa khac', (t) => {
  const file = cfgFile(t, { defaultModel: 'gemini-4-argon-high', giaoDefault: false });
  assert.equal(getPmAgyProfile({ configPath: file }), null);
  const res = setPmAgyProfile({ configPath: file, profile: 'antigravity_pro' });
  assert.equal(res.profile, 'antigravity_pro');
  assert.equal(res.previous, null);
  const saved = JSON.parse(fs.readFileSync(file, 'utf8'));
  assert.equal(saved.agyProfile, 'antigravity_pro');
  assert.equal(saved.defaultModel, 'gemini-4-argon-high');
  assert.equal(getPmAgyProfile({ configPath: file }), 'antigravity_pro');
});

test('id cu antigravity duoc doi sang antigravity_ultra; null/rong bo khoa de ve tai khoan mac dinh', (t) => {
  const file = cfgFile(t, { agyProfile: 'antigravity_pro' });
  assert.equal(setPmAgyProfile({ configPath: file, profile: 'antigravity' }).profile, 'antigravity_ultra');
  assert.equal(setPmAgyProfile({ configPath: file, profile: null }).profile, null);
  assert.ok(!('agyProfile' in JSON.parse(fs.readFileSync(file, 'utf8'))));
});

test('profile Claude/Grok hoac id la bi tu choi, file khong doi', (t) => {
  const file = cfgFile(t, { agyProfile: 'antigravity_pro' });
  const before = fs.readFileSync(file, 'utf8');
  for (const bad of ['finos_toan', 'grok', '../x', 'nope']) {
    assert.throws(() => setPmAgyProfile({ configPath: file, profile: bad }), /Antigravity/);
  }
  assert.equal(fs.readFileSync(file, 'utf8'), before);
});

test('file cau hinh hong thi NEM LOI va khong bi ghi de', (t) => {
  const file = cfgFile(t, '{bad json');
  assert.throws(() => setPmAgyProfile({ configPath: file, profile: 'antigravity_pro' }), /không đọc được|khong doc duoc|JSON/i);
  assert.equal(fs.readFileSync(file, 'utf8'), '{bad json');
});

test('MCP tool switcher_set_pm_account doi tai khoan cho antigravity-pm qua ANTIGRAVITY_PM_GLOBAL_CONFIG', async (t) => {
  const file = cfgFile(t, {});
  const prev = process.env.ANTIGRAVITY_PM_GLOBAL_CONFIG;
  process.env.ANTIGRAVITY_PM_GLOBAL_CONFIG = file;
  t.after(() => { if (prev === undefined) delete process.env.ANTIGRAVITY_PM_GLOBAL_CONFIG; else process.env.ANTIGRAVITY_PM_GLOBAL_CONFIG = prev; });
  const { TOOLS_BY_NAME } = await import('../src/tools.js');
  const out = await TOOLS_BY_NAME.get('switcher_set_pm_account').handler({ profile: 'antigravity_pro' });
  assert.match(out.text, /antigravity_pro/);
  assert.equal(JSON.parse(fs.readFileSync(file, 'utf8')).agyProfile, 'antigravity_pro');
});
