// #757 F9: balanceRepoAccounts must never overwrite a repo's .claude/settings.local.json it cannot read as a JSON object
// (that write replaced hooks/permissions/autoMemoryDirectory with just {account}). Temp dirs only, no real repos or ~/.cc-switch.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { balanceRepoAccounts } from '../src/profiles.js';

function setup() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-balance-corrupt-'));
  const stateDir = path.join(root, 'state');
  fs.mkdirSync(stateDir);
  fs.writeFileSync(path.join(stateDir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos' }));
  fs.writeFileSync(path.join(stateDir, 'repos.json'), JSON.stringify({ custom: [], hidden: [], defaults: false }));
  const mkRepo = (name, rawSettings) => {
    const p = path.join(root, 'code', name);
    fs.mkdirSync(path.join(p, '.claude'), { recursive: true });
    fs.writeFileSync(path.join(p, '.claude', 'settings.local.json'), rawSettings);
    return p;
  };
  return { root, stateDir, mkRepo, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}

const settingsFile = (p) => path.join(p, '.claude', 'settings.local.json');

for (const mode of ['even', 'swap']) {
  test(`balanceRepoAccounts(${mode}): unparsable or non-object settings.local.json is left byte-for-byte, other repos still balanced`, () => {
    const t = setup();
    try {
      const truncated = '{"hooks": {';
      const arrayJson = '[1, 2]';
      const good = t.mkRepo('good', JSON.stringify({ hooks: { Stop: [] }, account: 'finos' }));
      const broken = t.mkRepo('broken', truncated);
      const notObject = t.mkRepo('not-object', arrayJson);
      const repos = [
        { name: 'good', path: good, defaultAccount: 'finos' },
        { name: 'broken', path: broken, defaultAccount: 'finos_team' },
        { name: 'not-object', path: notObject, defaultAccount: 'finos_team' },
      ];

      const res = balanceRepoAccounts({ repos, stateDir: t.stateDir, mode });

      assert.equal(fs.readFileSync(settingsFile(broken), 'utf8'), truncated);
      assert.equal(fs.readFileSync(settingsFile(notObject), 'utf8'), arrayJson);

      const goodSettings = JSON.parse(fs.readFileSync(settingsFile(good), 'utf8'));
      assert.deepEqual(goodSettings.hooks, { Stop: [] });
      assert.equal(goodSettings.account, mode === 'swap' ? 'finos_team' : 'finos');

      const byName = Object.fromEntries(res.map((r) => [r.name, r]));
      assert.equal(byName.good.account, goodSettings.account);
      assert.ok(!byName.good.skipped);
      for (const name of ['broken', 'not-object']) {
        assert.equal(byName[name]?.skipped, true, `${name} must be reported as skipped`);
        assert.ok(byName[name].error, `${name} must carry the read error`);
      }
    } finally {
      t.cleanup();
    }
  });
}
