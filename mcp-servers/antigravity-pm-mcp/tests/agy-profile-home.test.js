// agy chi tach tai khoan qua HOME: PM (review/audit Antigravity) chay agy voi HOME=~/.agy-<profile> khi khai agyProfile
// (env ANTIGRAVITY_PM_AGY_PROFILE hoac ~/.antigravity-pm.json), con tai khoan mac dinh cua may va state cua PM khong doi.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { agyEnv } from '../src/agentapi.js';
import { tmpDir, cleanup } from './helpers.js';

const KEYS = ['HOME', 'AGY_REAL_HOME', 'ANTIGRAVITY_PM_AGY_PROFILE', 'ANTIGRAVITY_PM_GLOBAL_CONFIG'];

// Profile da dung dung cach (agy-profile): .gemini + Library that co Keychains/login.keychain-db rieng.
function mkProfile(real, name) {
  fs.mkdirSync(path.join(real, `.agy-${name}`, '.gemini'), { recursive: true });
  fs.mkdirSync(path.join(real, `.agy-${name}`, 'Library', 'Keychains'), { recursive: true });
  fs.writeFileSync(path.join(real, `.agy-${name}`, 'Library', 'Keychains', 'login.keychain-db'), '');
}

function withEnv(t, set) {
  const prev = Object.fromEntries(KEYS.map((k) => [k, process.env[k]]));
  for (const k of KEYS) delete process.env[k];
  Object.assign(process.env, set);
  t.after(() => { for (const k of KEYS) { if (prev[k] === undefined) delete process.env[k]; else process.env[k] = prev[k]; } });
}

test('khong khai agyProfile: HOME cua agy giu nguyen', (t) => {
  const real = tmpDir('agpm-prof-');
  t.after(() => cleanup(real));
  withEnv(t, { HOME: real, ANTIGRAVITY_PM_GLOBAL_CONFIG: path.join(real, 'none.json') });
  const env = agyEnv('x/1.jsonl');
  assert.equal(env.HOME, real);
  assert.equal(env.AGY_REAL_HOME, undefined);
});

test('agyProfile trong env: agy nhan HOME rieng cua profile, HOME that van o AGY_REAL_HOME, process.env cua PM khong doi', (t) => {
  const real = tmpDir('agpm-prof-');
  t.after(() => cleanup(real));
  mkProfile(real, 'antigravity_pro');
  withEnv(t, { HOME: real, ANTIGRAVITY_PM_AGY_PROFILE: 'antigravity_pro' });
  const env = agyEnv('x/1.jsonl');
  assert.equal(env.HOME, path.join(real, '.agy-antigravity_pro'));
  assert.equal(env.AGY_REAL_HOME, real);
  assert.equal(process.env.HOME, real, 'PM khong doi HOME cua chinh no');
});

test('agyProfile trong ~/.antigravity-pm.json cung duoc nhan', (t) => {
  const real = tmpDir('agpm-prof-');
  t.after(() => cleanup(real));
  mkProfile(real, 'antigravity_pro');
  const cfg = path.join(real, 'cfg.json');
  fs.writeFileSync(cfg, JSON.stringify({ agyProfile: 'antigravity_pro' }));
  withEnv(t, { HOME: real, ANTIGRAVITY_PM_GLOBAL_CONFIG: cfg });
  assert.equal(agyEnv('x/1.jsonl').HOME, path.join(real, '.agy-antigravity_pro'));
});

test('profile chua dung hoac ten xau: NEM LOI, khong am tham roi ve tai khoan mac dinh', (t) => {
  const real = tmpDir('agpm-prof-');
  t.after(() => cleanup(real));
  withEnv(t, { HOME: real, ANTIGRAVITY_PM_AGY_PROFILE: 'antigravity_pro' });
  assert.throws(() => agyEnv('x/1.jsonl'), (e) => e.name === 'AntigravityUnavailable' && /agy-profile antigravity_pro/.test(e.hint));
  process.env.ANTIGRAVITY_PM_AGY_PROFILE = '../etc';
  assert.throws(() => agyEnv('x/1.jsonl'), /khong hop le/);
});

test('profile cu (Library la symlink ve Keychain that) hoac thieu keychain rieng: NEM LOI, khong chay agy bang Keychain that', { skip: process.platform !== 'darwin' }, (t) => {
  const real = tmpDir('agpm-prof-');
  t.after(() => cleanup(real));
  fs.mkdirSync(path.join(real, 'Library'), { recursive: true });
  fs.mkdirSync(path.join(real, '.agy-antigravity_ultra', '.gemini'), { recursive: true });
  fs.symlinkSync(path.join(real, 'Library'), path.join(real, '.agy-antigravity_ultra', 'Library'));
  withEnv(t, { HOME: real, ANTIGRAVITY_PM_AGY_PROFILE: 'antigravity_ultra' });
  assert.throws(() => agyEnv('x/1.jsonl'), (e) => e.name === 'AntigravityUnavailable' && /agy-profile antigravity_ultra/.test(e.hint));
  fs.rmSync(path.join(real, '.agy-antigravity_ultra', 'Library'));
  fs.mkdirSync(path.join(real, '.agy-antigravity_ultra', 'Library', 'Keychains'), { recursive: true });
  assert.throws(() => agyEnv('x/1.jsonl'), (e) => e.name === 'AntigravityUnavailable', 'thieu login.keychain-db rieng cung phai nem loi');
});

test('~/.antigravity-pm.json hong: NEM LOI, khong am tham dung tai khoan mac dinh', (t) => {
  const real = tmpDir('agpm-prof-');
  t.after(() => cleanup(real));
  const cfg = path.join(real, 'cfg.json');
  fs.writeFileSync(cfg, '{bad json');
  withEnv(t, { HOME: real, ANTIGRAVITY_PM_GLOBAL_CONFIG: cfg });
  assert.throws(() => agyEnv('x/1.jsonl'), (e) => e.name === 'AntigravityUnavailable');
});
