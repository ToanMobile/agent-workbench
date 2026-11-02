// quet critical 31/10 — BUG-REV-agpm-config-null-object: khoa object da biet ghi null / gia tri don / mang trong
// .antigravity-pm.json (deepMerge chep nguyen) lam crash loadConfig ({"proof": null}) hoac mot tool ve sau ({"antigravity": 3}).
import test from 'node:test';
import assert from 'node:assert/strict';
import { loadConfig } from '../src/config.js';
import { tmpProject, cleanup } from './helpers.js';

test('loadConfig: proof / antigravity set to null or a primitive fall back to the defaults with a warning, no crash', () => {
  const dir = tmpProject({ proof: null, antigravity: 3, mustHave: [] });
  try {
    const cfg = loadConfig(dir);
    assert.equal(cfg.proof.require, 1);
    assert.equal(typeof cfg.antigravity, 'object');
    assert.ok(cfg.antigravity && !Array.isArray(cfg.antigravity));
    assert.ok(cfg.warnings.some((w) => w.startsWith('proof khong phai object')));
  } finally {
    cleanup(dir);
  }
});
