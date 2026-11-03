// Doi id 4 tai khoan: finos->finos_toan, finos_team->finos_linh, max->finos_toan_max, antigravity->antigravity_ultra.
// Id cu van duoc nhan (state, ghim account trong repo, CLI), thu muc ~/.claude-* khong bi doi: Keychain luu dang nhap theo
// sha256(duong dan configDir), doi ten thu muc la mat dang nhap. Temp dirs only, khong cham repo / HOME that.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { DEFAULT_PROFILES, LEGACY_ID_ALIASES, canonicalKeys, canonicalProfileId, resolveProfile, loadSwitcherState, saveSwitcherState, setRepoAccount, getRepoAssignments } from '../src/profiles.js';
import { migrateIds } from '../src/migrate-ids.js';

const RENAMES = { finos: 'finos_toan', finos_team: 'finos_linh', max: 'finos_toan_max', antigravity: 'antigravity_ultra' };

function setup() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-ids-'));
  const stateDir = path.join(root, 'state');
  fs.mkdirSync(stateDir);
  fs.writeFileSync(path.join(stateDir, 'repos.json'), JSON.stringify({ custom: [], hidden: [], defaults: false }));
  const mkRepo = (name, account) => {
    const p = path.join(root, 'code', name);
    fs.mkdirSync(path.join(p, '.git'), { recursive: true });
    fs.mkdirSync(path.join(p, '.claude'), { recursive: true });
    fs.writeFileSync(path.join(p, '.claude', 'settings.local.json'), JSON.stringify(account ? { account, keep: { me: 1 } } : { keep: { me: 1 } }));
    return p;
  };
  return { root, stateDir, mkRepo, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}
const pin = (p) => JSON.parse(fs.readFileSync(path.join(p, '.claude', 'settings.local.json'), 'utf8'));

test('id moi, id cu la bi danh, thu muc dang nhap giu nguyen', () => {
  assert.deepEqual(DEFAULT_PROFILES.map((p) => p.id), ['finos_toan', 'finos_linh', 'finos_toan_max', 'antigravity_ultra', 'antigravity_pro', 'grok', 'finos_lua']);
  assert.deepEqual(LEGACY_ID_ALIASES, RENAMES);
  for (const [old, neu] of Object.entries(RENAMES)) {
    assert.equal(canonicalProfileId(old), neu);
    assert.equal(canonicalProfileId(neu), neu);
    assert.equal(resolveProfile(old).id, neu);
    assert.equal(resolveProfile(neu).id, neu);
  }
  assert.equal(canonicalProfileId('grok'), 'grok');
  const dir = (id) => DEFAULT_PROFILES.find((p) => p.id === id).configDir;
  assert.ok(dir('finos_toan').endsWith(`${path.sep}.claude-finos`));
  assert.ok(dir('finos_linh').endsWith(`${path.sep}.claude-finos_team`));
  assert.ok(dir('finos_toan_max').endsWith(`${path.sep}.claude-max`));
  assert.ok(dir('finos_lua').endsWith(`${path.sep}.claude-finos_lua`));
});

test('state cu (id cu o activeProfileId, frozenUntil, quotaCache) duoc doc ra bang id moi', () => {
  const t = setup();
  try {
    saveSwitcherState(t.stateDir, { activeProfileId: 'finos_team', frozenUntil: { max: 123, grok: 456 }, quotaCache: { finos: { remainingPct: 40 } } });
    const st = loadSwitcherState(t.stateDir);
    assert.equal(st.activeProfileId, 'finos_linh');
    assert.deepEqual(st.frozenUntil, { finos_toan_max: 123, grok: 456 });
    assert.deepEqual(Object.keys(st.quotaCache), ['finos_toan']);
  } finally { t.cleanup(); }
});

test('state co ca khoa cu lan khoa moi (daemon cu chay song song): giu moc dong bang lon hon, khong de khoa sau ghi de', () => {
  const t = setup();
  try {
    saveSwitcherState(t.stateDir, { activeProfileId: 'finos_toan', frozenUntil: { finos_team: 9_000, finos_linh: 5_000, max: 1_000, finos_toan_max: 2_000 } });
    assert.deepEqual(loadSwitcherState(t.stateDir).frozenUntil, { finos_linh: 9_000, finos_toan_max: 2_000 });
  } finally { t.cleanup(); }
});

test('canonicalKeys: quotaCache trung khoa giu ban updatedAtMs moi hon (theo thu tu nao cung vay); null khong ghi de gia tri hop le', () => {
  const newer = { updatedAtMs: 9, remainingPct: 10 };
  const older = { updatedAtMs: 5, remainingPct: 90 };
  assert.deepEqual(canonicalKeys({ finos: newer, finos_toan: older }), { finos_toan: newer });
  assert.deepEqual(canonicalKeys({ finos_toan: newer, finos: older }), { finos_toan: newer });
  assert.deepEqual(canonicalKeys({ finos: 9000, finos_toan: null }), { finos_toan: 9000 });
  assert.deepEqual(canonicalKeys({ finos_toan: 9000, finos: null }), { finos_toan: 9000 });
});

test('ghim account cu trong repo duoc doc bang id moi; gan lai bang id cu ghi id moi', () => {
  const t = setup();
  try {
    const repos = [{ name: 'a', path: t.mkRepo('a', 'finos_team') }];
    assert.equal(getRepoAssignments({ stateDir: t.stateDir, repos })[0].account, 'finos_linh');
    setRepoAccount({ stateDir: t.stateDir, repos, repoPath: repos[0].path, account: 'max' });
    assert.equal(pin(repos[0].path).account, 'finos_toan_max');
  } finally { t.cleanup(); }
});

test('migrateIds: dry-run chi lap ke hoach; chay that doi ghim + state, giu khoa khac, khong cham thu muc, chay lai la no-op', () => {
  const t = setup();
  try {
    const repos = [
      { name: 'a', path: t.mkRepo('a', 'finos') },
      { name: 'b', path: t.mkRepo('b', 'finos_lua') },
      { name: 'c', path: t.mkRepo('c', 'antigravity') },
      { name: 'd', path: t.mkRepo('d') },
    ];
    saveSwitcherState(t.stateDir, { activeProfileId: 'max', frozenUntil: { finos_team: 9 } });
    const before = fs.readFileSync(path.join(repos[0].path, '.claude', 'settings.local.json'), 'utf8');

    const dry = migrateIds({ stateDir: t.stateDir, repos, dryRun: true });
    assert.equal(dry.dryRun, true);
    assert.deepEqual(dry.repoPins.map((x) => [x.name, x.from, x.to]), [['a', 'finos', 'finos_toan'], ['c', 'antigravity', 'antigravity_ultra']]);
    assert.equal(dry.state.changed, true);
    assert.equal(fs.readFileSync(path.join(repos[0].path, '.claude', 'settings.local.json'), 'utf8'), before, 'dry-run khong ghi gi');

    const done = migrateIds({ stateDir: t.stateDir, repos });
    assert.equal(done.dryRun, false);
    assert.deepEqual(pin(repos[0].path), { account: 'finos_toan', keep: { me: 1 } });
    assert.equal(pin(repos[1].path).account, 'finos_lua');
    assert.equal(pin(repos[2].path).account, 'antigravity_ultra');
    assert.equal(pin(repos[3].path).account, undefined);
    const st = JSON.parse(fs.readFileSync(path.join(t.stateDir, 'switcher-state.json'), 'utf8'));
    assert.equal(st.activeProfileId, 'finos_toan_max');
    assert.deepEqual(st.frozenUntil, { finos_linh: 9 });

    const again = migrateIds({ stateDir: t.stateDir, repos });
    assert.deepEqual(again.repoPins, []);
    assert.equal(again.state.changed, false);
  } finally { t.cleanup(); }
});

test('migrateIds: settings.local.json hong thi bo qua va bao, khong ghi de', () => {
  const t = setup();
  try {
    const p = t.mkRepo('broken');
    fs.writeFileSync(path.join(p, '.claude', 'settings.local.json'), '{"hooks": {');
    const res = migrateIds({ stateDir: t.stateDir, repos: [{ name: 'broken', path: p }] });
    assert.equal(res.skipped.length, 1);
    assert.equal(fs.readFileSync(path.join(p, '.claude', 'settings.local.json'), 'utf8'), '{"hooks": {');
  } finally { t.cleanup(); }
});
