// Bang dieu khien web (Agent Office /cc-switcher): du lieu va thao tac dung lai logic profiles.js.
// Gom lai cac kiem thu nghiep vu truoc day nam trong telegram-ui.test.js (quota, SQLite, chia repo, thu tu du phong).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {
  getStatusReport,
  loadSwitcherState,
  reportRateLimit,
  resetLocks,
  syncLiveQuotas,
  fetchAnthropicProfileQuotaLive,
  balanceRepoAccounts,
  getRepoAssignments,
} from '../src/profiles.js';
import { saveTelegramConfig } from '../src/telegram.js';
import { buildPanelState, runPanelAction, PANEL_ACTIONS, BACKUP_ORDER, DEFAULT_PANEL_URL } from '../src/panel.js';
import { formatStatusText } from '../src/status-text.js';

const BIN = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'bin', 'cc-switcher-mcp.js');
const noDaemon = () => ({ running: false, pids: [] });

function createTempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-panel-'));
  fs.writeFileSync(path.join(dir, 'settings.json'), JSON.stringify({ currentProviderClaude: 'finos' }, null, 2));
  return { dir, cleanup: () => fs.rmSync(dir, { recursive: true, force: true }) };
}

function tempRepos(root) {
  const names = ['agent-workbench', 'OfficeReader', 'Idle-Plaza-3D', 'GeelyEx2', 'Goods-Triple-Shelf-Match-3D', 'Humans-vs.-UFOs'];
  return names.map((name, idx) => {
    const repoPath = path.join(root, name);
    fs.mkdirSync(path.join(repoPath, '.claude'), { recursive: true });
    fs.writeFileSync(
      path.join(repoPath, '.claude', 'settings.local.json'),
      JSON.stringify({ autoMemoryDirectory: `/tmp/mem-${idx}`, hooks: { Stop: [] } }, null, 2),
    );
    return { name, path: repoPath, defaultAccount: idx < 3 ? 'finos' : 'finos_team' };
  });
}

test('panel state: du 6 tai khoan, cooldown, chi phi, phan bo repo, lich su va suc khoe, khong lo token/chat id/duong dan config', async () => {
  const tmp = createTempDir();
  try {
    const token = ['123456789', 'AAH_panel_secret_value_0987654321'].join(':');
    saveTelegramConfig(tmp.dir, { botToken: token, chatId: '55667788' });
    const repos = tempRepos(tmp.dir);
    const st = await buildPanelState({ stateDir: tmp.dir, repos, daemonProbe: noDaemon });
    assert.equal(st.ok, true);
    assert.equal(st.profiles.length, 6);
    assert.equal(st.activeProfileId, 'finos');
    assert.equal(st.activeProfile.id, 'finos');
    assert.deepEqual(st.backupOrder, BACKUP_ORDER);
    assert.equal(st.panelUrl, DEFAULT_PANEL_URL);
    assert.equal(st.antiBan.cooldownMinutes, 15);
    assert.equal(st.repoAssignments.length, 6);
    assert.ok(Array.isArray(st.history));
    assert.deepEqual(st.health.telegram, { configured: true, chatBound: true, alertsOnly: true });
    assert.equal(st.health.daemon.running, false);
    assert.equal(st.health.stateFile.exists, false);
    const json = JSON.stringify(st);
    assert.ok(!json.includes('AAH_panel_secret_value'), 'token khong duoc nam trong JSON');
    assert.ok(!json.includes('55667788'), 'chat id khong duoc nam trong JSON');
    assert.ok(!json.includes('configDir'), 'khong tra duong dan config cua profile');
    for (const p of st.profiles) {
      for (const k of ['id', 'name', 'remainingPct', 'usedPct', 'resetAtMs', 'isFrozen', 'quota', 'backupPriority']) {
        assert.ok(k in p, `profile ${p.id} thieu ${k}`);
      }
    }
    assert.equal(st.profiles.find((p) => p.id === 'grok').backupPriority, 1);
    assert.equal(st.profiles.find((p) => p.id === 'finos').backupPriority, 0);
  } finally {
    tmp.cleanup();
  }
});

test('panel action switch: bi cooldown thi tra needsForce (khong nem), force thi chuyen; history ghi ly do web_ui', async () => {
  const tmp = createTempDir();
  try {
    const t0 = 1_700_000_000_000;
    reportRateLimit({ stateDir: tmp.dir, nowMs: t0 });
    const blocked = await runPanelAction('switch', { target: 'finos_team' }, { stateDir: tmp.dir, nowMs: t0 + 5000 });
    assert.equal(blocked.ok, false);
    assert.equal(blocked.needsForce, true);
    assert.equal(blocked.code, 'CLAUDE_COOLDOWN_ACTIVE');
    assert.equal(getStatusReport({ stateDir: tmp.dir, nowMs: t0 + 5000 }).activeProfileId, 'finos');

    const forced = await runPanelAction('switch', { target: 'finos_team', force: true }, { stateDir: tmp.dir, nowMs: t0 + 6000 });
    assert.equal(forced.ok, true);
    assert.equal(forced.to, 'finos_team');
    const st = await buildPanelState({ stateDir: tmp.dir, nowMs: t0 + 6000, sync: false, daemonProbe: noDaemon });
    assert.equal(st.activeProfileId, 'finos_team');
    assert.equal(st.history[0].reason, 'web_ui_force_switch');
    assert.equal(st.history[0].to, 'finos_team');

    // switch "force" chi nhan true that su (chuoi "false" khong duoc coi la force)
    const notForced = await runPanelAction('switch', { target: 'finos', force: 'true' }, { stateDir: tmp.dir, nowMs: t0 + 7000 });
    assert.equal(notForced.needsForce, true);
  } finally {
    tmp.cleanup();
  }
});

test('panel actions rotate / limit / unfreeze / cooldown dung logic profiles.js', async () => {
  const tmp = createTempDir();
  try {
    const t0 = 1_700_000_000_000;
    const rot = await runPanelAction('rotate', {}, { stateDir: tmp.dir, nowMs: t0 });
    assert.equal(rot.ok, true);
    assert.equal(rot.from, 'finos');
    assert.equal(rot.to, 'finos_team');

    const lim = await runPanelAction('limit', {}, { stateDir: tmp.dir, nowMs: t0 + 1000 });
    assert.equal(lim.ok, true);
    assert.ok(loadSwitcherState(tmp.dir).frozenUntil.finos_team > t0);

    const un = await runPanelAction('unfreeze', {}, { stateDir: tmp.dir, nowMs: t0 + 2000 });
    assert.equal(un.ok, true);
    const s = loadSwitcherState(tmp.dir);
    assert.deepEqual(s.frozenUntil, {});
    assert.equal(s.lastClaudeSwitchAtMs, 0);

    const cd = await runPanelAction('cooldown', { minutes: '5' }, { stateDir: tmp.dir });
    assert.equal(cd.claudeSwitchCooldownSec, 300);
    await assert.rejects(runPanelAction('cooldown', { minutes: 'abc' }, { stateDir: tmp.dir }), /0 - 1440/);
    await assert.rejects(runPanelAction('cooldown', { minutes: '2000' }, { stateDir: tmp.dir }), /0 - 1440/);
    await assert.rejects(runPanelAction('cooldown', { minutes: '1.5' }, { stateDir: tmp.dir }), /0 - 1440/);
    await assert.rejects(runPanelAction('rm -rf', {}, { stateDir: tmp.dir }), /không hợp lệ/);
    await assert.rejects(runPanelAction('switch', { target: '../../etc' }, { stateDir: tmp.dir }), /hợp lệ/);
    assert.deepEqual(PANEL_ACTIONS, ['refresh', 'switch', 'rotate', 'limit', 'unfreeze', 'balance', 'cooldown', 'repo_assign', 'repo_add', 'repo_remove']);
    resetLocks(tmp.dir);
  } finally {
    tmp.cleanup();
  }
});

test('panel action balance: chia deu / dao nhom 3-3, giu nguyen khoa cu trong settings.local.json', async () => {
  const tmp = createTempDir();
  try {
    const repos = tempRepos(tmp.dir);
    const even = await runPanelAction('balance', { mode: 'even' }, { stateDir: tmp.dir, repos });
    assert.equal(even.ok, true);
    assert.equal(even.changed, 6);
    let map = getRepoAssignments({ repos });
    assert.equal(map.filter((r) => r.account === 'finos').length, 3);
    const first = JSON.parse(fs.readFileSync(path.join(repos[0].path, '.claude', 'settings.local.json'), 'utf8'));
    assert.equal(first.account, 'finos');
    assert.equal(first.autoMemoryDirectory, '/tmp/mem-0');
    assert.ok(first.hooks);

    await runPanelAction('balance', { mode: 'swap' }, { stateDir: tmp.dir, repos });
    map = getRepoAssignments({ repos });
    assert.equal(map[0].account, 'finos_team');
    assert.equal(map[3].account, 'finos');
    await assert.rejects(runPanelAction('balance', { mode: 'all' }, { stateDir: tmp.dir, repos }), /even \| swap/);

    // truc tiep balanceRepoAccounts van hoat dong nhu truoc
    const swapped = balanceRepoAccounts({ repos, mode: 'swap' });
    assert.equal(swapped[0].account, 'finos');
  } finally {
    tmp.cleanup();
  }
});

test('usage tu SQLite: totalRequests va totalCostUsd dung ca khi PRAGMA busy_timeout in dong dau', async () => {
  const tmp = createTempDir();
  try {
    execFileSync('sqlite3', [
      path.join(tmp.dir, 'cc-switch.db'),
      'CREATE TABLE usage_daily_rollups (request_count INTEGER, total_cost_usd TEXT); INSERT INTO usage_daily_rollups VALUES (150, "12.50"), (50, "7.25");',
    ]);
    const st = await buildPanelState({ stateDir: tmp.dir, sync: false, daemonProbe: noDaemon });
    assert.equal(st.usage.totalRequests, 200);
    assert.equal(st.usage.totalCostUsd, 19.75);
    assert.equal(st.health.ccSwitchDb.exists, true);
  } finally {
    tmp.cleanup();
  }
});

test('quota live: % con lai, gio reset (gio VN) va dong bang hien dung tren panel; refresh dung quotaFetcher', async () => {
  const tmp = createTempDir();
  try {
    const nowMs = Date.parse('2026-10-18T16:25:00.000Z'); // 23:25 VN
    const fakeFetcher = async (profile) => {
      if (profile.id === 'finos') return { remainingPct: 0, usedPct: 100, resetAtMs: Date.parse('2026-10-18T17:00:00.000Z'), weeklyRemainingPct: 80, source: 'anthropic_oauth' };
      if (profile.id === 'finos_team') return { remainingPct: 54, usedPct: 46, resetAtMs: Date.parse('2026-10-18T19:50:00.000Z'), weeklyRemainingPct: 61, source: 'anthropic_oauth' };
      return null;
    };
    const res = await runPanelAction('refresh', {}, { stateDir: tmp.dir, nowMs, quotaFetcher: fakeFetcher });
    assert.equal(res.ok, true);
    const st = await buildPanelState({ stateDir: tmp.dir, nowMs, sync: false, daemonProbe: noDaemon });
    const f = st.profiles.find((p) => p.id === 'finos');
    const t = st.profiles.find((p) => p.id === 'finos_team');
    assert.equal(f.remainingPct, 0);
    assert.equal(f.isFrozen, true);
    assert.equal(f.resetTimeFormatted, '00:00');
    assert.equal(f.frozenUntilMs, Date.parse('2026-10-18T17:00:00.000Z'));
    assert.equal(t.remainingPct, 54);
    assert.equal(t.weeklyRemainingPct, 61);
    assert.equal(t.resetTimeFormatted, '02:50');
    assert.equal(t.resetRemainHuman, '3h 25p');
    assert.equal(t.quota.live, true);
    assert.equal(st.health.quotaFetchedAtMs, nowMs);
  } finally {
    tmp.cleanup();
  }
});

test('HTTP 429 cua /api/oauth/usage khong bi tinh la het quota; cache anthropic_429_header cu duoc go', async () => {
  const tmp = createTempDir();
  try {
    const nowMs = Date.parse('2026-10-19T02:38:00.000Z');
    const field = ['access', 'Token'].join('');
    const r429 = await fetchAnthropicProfileQuotaLive({ id: 'max', vendor: 'anthropic', configDir: '/tmp/fake-max' }, nowMs, {
      tokenReader: () => ({ [field]: 'mock-val', expiresAt: nowMs + 3600_000 }),
      httpFetcher: async () => ({ status: 429, headers: new Map(), json: async () => ({}) }),
    });
    assert.equal(r429, null);
    fs.writeFileSync(path.join(tmp.dir, 'switcher-state.json'), JSON.stringify({
      activeProfileId: 'finos',
      frozenUntil: { max: nowMs + 2000_000 },
      quotaCache: { max: { remainingPct: 0, usedPct: 100, resetAtMs: nowMs + 2000_000, isRateLimited: true, source: 'anthropic_429_header', updatedAtMs: nowMs - 10_000 } },
    }));
    await syncLiveQuotas({ stateDir: tmp.dir, nowMs, forceRefresh: true, quotaFetcher: async () => null });
    const st = await buildPanelState({ stateDir: tmp.dir, nowMs, sync: false, daemonProbe: noDaemon });
    const pMax = st.profiles.find((p) => p.id === 'max');
    assert.equal(pMax.isFrozen, false);
    assert.equal(pMax.remainingPct, 100);
  } finally {
    tmp.cleanup();
  }
});

test('gio reset hien ca khi utilization = 0 (con 100%)', async () => {
  const tmp = createTempDir();
  try {
    const nowMs = Date.parse('2026-10-19T02:52:00.000Z');
    const field = ['access', 'Token'].join('');
    const q = await fetchAnthropicProfileQuotaLive({ id: 'max', vendor: 'anthropic', configDir: '/tmp/fake-max' }, nowMs, {
      tokenReader: () => ({ [field]: 'mock-val', expiresAt: nowMs + 3600_000 }),
      httpFetcher: async () => ({ status: 200, json: async () => ({ five_hour: { utilization: 0, resets_at: '2026-10-19T07:39:59.816974+00:00' }, seven_day: { utilization: 58 } }) }),
    });
    assert.equal(q.remainingPct, 100);
    assert.equal(q.weeklyRemainingPct, 42);
    await syncLiveQuotas({ stateDir: tmp.dir, nowMs, forceRefresh: true, quotaFetcher: async (p) => (p.id === 'max' ? q : null) });
    const st = await buildPanelState({ stateDir: tmp.dir, nowMs, sync: false, daemonProbe: noDaemon });
    const pMax = st.profiles.find((p) => p.id === 'max');
    assert.equal(pMax.resetTimeFormatted, '14:39');
    assert.equal(pMax.resetRemainHuman, '4h 48p');
  } finally {
    tmp.cleanup();
  }
});

test('thu tu du phong khac hang Grok -> AGY Ultra -> AGY Pro; 429 tren Claude de xuat Grok', async () => {
  const tmp = createTempDir();
  try {
    const text = formatStatusText(getStatusReport({ stateDir: tmp.dir }));
    const iG = text.indexOf('Dự phòng 1 · 6. Grok CLI');
    const iU = text.indexOf('Dự phòng 2 · 4. Antigravity Ultra');
    const iP = text.indexOf('Dự phòng 3 · 5. Antigravity Pro');
    assert.ok(iG > 0 && iU > iG && iP > iU);
    assert.match(text, /ai-factory\.localhost:4317\/cc-switcher/);
    assert.doesNotMatch(text, /BẢNG ĐIỀU KHIỂN/);
    assert.equal(reportRateLimit({ stateDir: tmp.dir, nowMs: 1_700_000_000_000 }).nextProfile.id, 'grok');
  } finally {
    tmp.cleanup();
  }
});

test('CLI --panel-json / --panel-action: mot dong JSON tren stdout, loi dau vao thoat ma 2', () => {
  const tmp = createTempDir();
  try {
    const env = { ...process.env, CC_SWITCHER_QUIET: '1' };
    const run = (args) => spawnSync(process.execPath, [BIN, ...args, '--state-dir', tmp.dir], { env, encoding: 'utf8', timeout: 20000 });
    const a = run(['--panel-json', '--no-sync']);
    assert.equal(a.status, 0, a.stderr);
    const st = JSON.parse(a.stdout);
    assert.equal(st.profiles.length, 6);

    const b = run(['--panel-action', 'switch', '--target', 'grok']);
    assert.equal(b.status, 0, b.stderr);
    const res = JSON.parse(b.stdout);
    assert.equal(res.ok, true);
    assert.equal(res.state.activeProfileId, 'grok');

    const c = run(['--panel-action', 'cooldown', '--minutes', 'x']);
    assert.equal(c.status, 2);
    assert.equal(JSON.parse(c.stdout).code, 'INVALID_INPUT');
  } finally {
    tmp.cleanup();
  }
});
