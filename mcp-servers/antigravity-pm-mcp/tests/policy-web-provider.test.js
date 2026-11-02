// quet critical 31/10 — BUG-REV-agpm-web-provider-types: proof-target.js mo qa-visual / playwright nhu provider web do PM chay,
// nhung task browser/script chung minh bang chung bi checkProofProvider tu choi (danh sach cu chi co browser / shell).
import test from 'node:test';
import assert from 'node:assert/strict';
import { checkProofProvider } from '../src/policy.js';

test('browser/script task: a qa-visual or playwright provider (PM-run) counts, an agent file does not', () => {
  const cfg = { proof: { providers: { qa: { type: 'qa-visual' }, pw: { type: 'playwright' } } } };
  assert.equal(checkProofProvider(cfg, [{ provider: 'qa' }], { proofKind: 'browser' }).ok, true);
  assert.equal(checkProofProvider(cfg, [{ provider: 'pw' }], { proofKind: 'script' }).ok, true);
  assert.equal(checkProofProvider(cfg, [{ provider: 'file' }], { proofKind: 'browser' }).ok, false);
});
