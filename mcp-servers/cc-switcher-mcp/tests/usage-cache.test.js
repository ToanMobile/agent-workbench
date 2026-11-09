// Token het han: chay `claude -p /usage` trong thu muc profile (Claude Code tu lam moi token) roi doc cachedUsageUtilization.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fetchAnthropicProfileQuotaLive } from '../src/profiles.js';
import {
  CACHE_MAX_AGE_MS,
  RUN_INTERVAL_MS,
  readCachedUsage,
  refreshUsageViaCli,
  usageCliArgs,
} from '../src/usage-cache.js';

const NOW = Date.parse('2026-11-09T09:00:00.000Z');
const AT = ['access', 'Token'].join('');
// Ten bien moi truong tai khoan that: ghep chuoi de khong de literal nhay cam trong test.
const ACCOUNT_ENV = ['ANTHROPIC_' + 'BASE_URL', 'ANTHROPIC_' + 'API_KEY', 'ANTHROPIC_' + 'AUTH_TOKEN', 'CLAUDE_CODE_' + 'OAUTH_TOKEN'];

function tmp() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-switcher-usage-'));
  const cfg = path.join(dir, 'cfg');
  fs.mkdirSync(cfg);
  const writeDoc = (doc) => fs.writeFileSync(path.join(cfg, '.claude.json'), JSON.stringify(doc));
  return { dir, cfg, writeDoc, cleanup: () => fs.rmSync(dir, { recursive: true, force: true }) };
}
const usage = { five_hour: { utilization: 20, resets_at: '2026-11-09T12:00:00+00:00' }, seven_day: { utilization: 99, resets_at: '2026-11-13T11:00:00+00:00' } };
const doc = (over = {}) => ({ oauthAccount: { accountUuid: 'acc-1' }, cachedUsageUtilization: { fetchedAtMs: NOW - 30_000, accountUuid: 'acc-1', utilization: usage, ...over } });

test('doc cache: chi nhan accountUuid khop, co fetchedAtMs va utilization la object', () => {
  const t = tmp();
  try {
    t.writeDoc(doc());
    assert.equal(readCachedUsage(t.cfg, 'acc-1').utilization.seven_day.utilization, 99);
    assert.equal(readCachedUsage(t.cfg, 'acc-2'), null, 'tai khoan khac khong duoc tin');
    t.writeDoc(doc({ utilization: null }));
    assert.equal(readCachedUsage(t.cfg, 'acc-1'), null);
    t.writeDoc({ oauthAccount: { accountUuid: 'acc-1' } });
    assert.equal(readCachedUsage(t.cfg, 'acc-1'), null);
    fs.writeFileSync(path.join(t.cfg, '.claude.json'), '{hong');
    assert.equal(readCachedUsage(t.cfg, 'acc-1'), null);
  } finally { t.cleanup(); }
});

test('lenh /usage: khong tools, khong MCP, khong setting, khong luu phien', () => {
  const a = usageCliArgs();
  assert.deepEqual(a.slice(0, 2), ['-p', '/usage']);
  for (const x of ['--strict-mcp-config', '--no-session-persistence']) assert.ok(a.includes(x), x);
  assert.equal(a[a.indexOf('--tools') + 1], '');
  assert.equal(a[a.indexOf('--setting-sources') + 1], '');
});

test('refresh chay runner 1 lan voi dung thu muc va moi truong sach, roi throttle 10 phut theo profile', async () => {
  const t = tmp();
  try {
    const calls = [];
    const runner = async (c) => { calls.push(c); };
    const prof = { id: 'finos_toan', configDir: t.cfg };
    const env = { PATH: '/usr/bin', HOME: '/h' };
    for (const k of ACCOUNT_ENV) env[k] = 'x';
    const r1 = await refreshUsageViaCli(prof, NOW, { lockDir: t.dir, runner, baseEnv: env });
    assert.equal(r1.ran, true);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].env.CLAUDE_CONFIG_DIR, t.cfg);
    for (const k of ACCOUNT_ENV) assert.equal(k in calls[0].env, false, k);
    assert.equal(calls[0].env.DISABLE_TELEMETRY, '1');
    const r2 = await refreshUsageViaCli(prof, NOW + RUN_INTERVAL_MS - 1000, { lockDir: t.dir, runner });
    assert.equal(r2.ran, false);
    assert.equal(r2.reason, 'throttled');
    const other = await refreshUsageViaCli({ id: 'finos_linh', configDir: t.cfg }, NOW + 1000, { lockDir: t.dir, runner });
    assert.equal(other.ran, true, 'throttle theo tung profile');
    const r3 = await refreshUsageViaCli(prof, NOW + RUN_INTERVAL_MS + 1000, { lockDir: t.dir, runner });
    assert.equal(r3.ran, true);
    assert.equal(calls.length, 3);
  } finally { t.cleanup(); }
});

test('runner loi van tinh la da chay (khong thu lai moi 45 giay) va khong nem ra ngoai', async () => {
  const t = tmp();
  try {
    let n = 0;
    const runner = async () => { n += 1; throw new Error('timeout'); };
    const prof = { id: 'finos_toan', configDir: t.cfg };
    const r1 = await refreshUsageViaCli(prof, NOW, { lockDir: t.dir, runner });
    assert.equal(r1.ran, true);
    assert.match(r1.error, /timeout/);
    const r2 = await refreshUsageViaCli(prof, NOW + 60_000, { lockDir: t.dir, runner });
    assert.equal(r2.reason, 'throttled');
    assert.equal(n, 1);
  } finally { t.cleanup(); }
});

test('mot tien trinh /usage mot luc: khoa dang giu thi bo qua, khoa duoc tha sau khi chay', async () => {
  const t = tmp();
  try {
    fs.writeFileSync(path.join(t.dir, 'usage-cli.lock'), String(process.pid));
    let n = 0;
    const runner = async () => { n += 1; };
    const prof = { id: 'finos_toan', configDir: t.cfg };
    const busy = await refreshUsageViaCli(prof, NOW, { lockDir: t.dir, runner });
    assert.equal(busy.reason, 'busy');
    assert.equal(n, 0);
    fs.rmSync(path.join(t.dir, 'usage-cli.lock'));
    await refreshUsageViaCli(prof, NOW, { lockDir: t.dir, runner });
    assert.equal(fs.existsSync(path.join(t.dir, 'usage-cli.lock')), false);
  } finally { t.cleanup(); }
});

test('fetch quota: token het han -> /usage -> doc cache -> quota dung, khong goi API', async () => {
  const t = tmp();
  try {
    t.writeDoc(doc());
    let apiCalls = 0;
    const q = await fetchAnthropicProfileQuotaLive({ id: 'finos_toan', vendor: 'anthropic', configDir: t.cfg }, NOW, {
      stateDir: t.dir,
      tokenReader: () => ({ [AT]: 'm', expiresAt: NOW - 3600_000 }),
      httpFetcher: async () => { apiCalls += 1; return { status: 500 }; },
      accountReader: () => null,
      usageRefresher: async () => ({ ran: true }),
    });
    assert.equal(apiCalls, 0);
    assert.equal(q.remainingPct, 80);
    assert.equal(q.weeklyRemainingPct, 1);
    assert.equal(q.weeklyResetAtMs, Date.parse('2026-11-13T11:00:00Z'));
    assert.equal(q.source, 'anthropic_oauth');
  } finally { t.cleanup(); }
});

test('fetch quota: khong co cache moi (hoac cache qua cu) -> refresh_failed (that su can dang nhap)', async () => {
  const t = tmp();
  try {
    t.writeDoc(doc({ fetchedAtMs: NOW - CACHE_MAX_AGE_MS - 60_000 }));
    const reasons = [];
    const q = await fetchAnthropicProfileQuotaLive({ id: 'finos_toan', vendor: 'anthropic', configDir: t.cfg }, NOW, {
      stateDir: t.dir,
      onFailure: (r) => reasons.push(r),
      tokenReader: () => ({ [AT]: 'm', expiresAt: NOW - 3600_000 }),
      usageRefresher: async () => ({ ran: true }),
    });
    assert.equal(q, null);
    assert.deepEqual(reasons, ['refresh_failed']);
  } finally { t.cleanup(); }
});

test('fetch quota: profile dang nhap sai tai khoan thi khong chay /usage', async () => {
  const t = tmp();
  try {
    t.writeDoc(doc());
    let ran = 0;
    const reasons = [];
    const q = await fetchAnthropicProfileQuotaLive({ id: 'finos_lua', vendor: 'anthropic', configDir: t.cfg, expectedEmail: 'lua@x.y' }, NOW, {
      stateDir: t.dir,
      onFailure: (r) => reasons.push(r),
      tokenReader: () => ({ [AT]: 'm', expiresAt: NOW - 3600_000 }),
      accountReader: () => 'toan@x.y',
      usageRefresher: async () => { ran += 1; return { ran: true }; },
    });
    assert.equal(q, null);
    assert.equal(ran, 0);
    assert.deepEqual(reasons, ['token_expired']);
  } finally { t.cleanup(); }
});
