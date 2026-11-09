// Quota cua profile khi token OAuth da het han: chay `claude -p /usage` trong thu muc profile, de CHINH Claude Code lam moi
// token (theo khoa cua no) va ghi ket qua vao <thu muc>/.claude.json (cachedUsageUtilization). Ta chi DOC cache do.
// Cach lam cua farion1231/cc-switch (services/claude_account/usage.rs). Khong doc/ghi token trong ma nay.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawn } from 'node:child_process';
import { logStructured } from './errors.js';

export const RUN_INTERVAL_MS = 10 * 60_000; // moi profile toi da 10 phut mot lan (ke ca lan loi)
export const RUN_TIMEOUT_MS = 45_000;
// Cache chi tin khi vua duoc `/usage` ghi: cu hon thi lan chay do that bai (dang nhap het han...), khong duoc che bang so cu.
export const CACHE_MAX_AGE_MS = RUN_INTERVAL_MS + RUN_TIMEOUT_MS;
const LOCK_STALE_MS = 2 * 60_000;
// Bien moi truong chon tai khoan/duong ra khac: bo di de /usage dung dung dang nhap cua thu muc profile.
const ACCOUNT_ENV = ['ANTHROPIC_' + 'BASE_URL', 'ANTHROPIC_' + 'API_KEY', 'ANTHROPIC_' + 'AUTH_TOKEN', 'CLAUDE_CODE_' + 'OAUTH_TOKEN', 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'];

export function usageCliArgs() {
  return ['-p', '/usage', '--output-format', 'json', '--tools', '', '--strict-mcp-config', '--setting-sources', '', '--no-session-persistence'];
}

function readClaudeJson(configDir) {
  try {
    return JSON.parse(fs.readFileSync(path.join(configDir, '.claude.json'), 'utf8'));
  } catch (err) {
    if (err?.code !== 'ENOENT') logStructured('warn', 'claude_json_read_failed', { error: err?.message });
    return null;
  }
}

export function readAccountUuid(configDir) {
  const uuid = readClaudeJson(configDir)?.oauthAccount?.accountUuid;
  return typeof uuid === 'string' && uuid ? uuid : null;
}

/** Cache quota Claude Code ghi; chi nhan khi accountUuid khop tai khoan trong thu muc. */
export function readCachedUsage(configDir, accountUuid) {
  const cached = readClaudeJson(configDir)?.cachedUsageUtilization;
  if (!cached || cached.accountUuid !== accountUuid) return null;
  const fetchedAtMs = Number(cached.fetchedAtMs);
  if (!Number.isFinite(fetchedAtMs) || !cached.utilization || typeof cached.utilization !== 'object') return null;
  return { fetchedAtMs, utilization: cached.utilization };
}

function claudeBinary() {
  const local = path.join(os.homedir(), '.local', 'bin', 'claude');
  return fs.existsSync(local) ? local : 'claude';
}

function cleanEnv(baseEnv, configDir) {
  const env = { ...baseEnv };
  for (const k of ACCOUNT_ENV) delete env[k];
  return {
    ...env,
    CLAUDE_CONFIG_DIR: configDir,
    CLAUDE_CODE_DISABLE_AUTO_MEMORY: '1',
    DISABLE_TELEMETRY: '1',
    DISABLE_ERROR_REPORTING: '1',
    DISABLE_AUTOUPDATER: '1',
  };
}

function defaultRunner({ command, args, env, cwd, timeoutMs }) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { env, cwd, stdio: 'ignore' });
    const timer = setTimeout(() => { child.kill('SIGKILL'); reject(new Error(`timeout ${timeoutMs}ms`)); }, timeoutMs);
    child.on('error', (err) => { clearTimeout(timer); reject(err); });
    child.on('exit', () => { clearTimeout(timer); resolve(); });
  });
}

function acquireLock(lockPath) {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      fs.writeFileSync(lockPath, String(process.pid), { flag: 'wx' });
      return true;
    } catch (err) {
      if (err?.code !== 'EEXIST') throw err;
      try {
        if (Date.now() - fs.statSync(lockPath).mtimeMs <= LOCK_STALE_MS) return false;
        fs.rmSync(lockPath, { force: true }); // khoa mo coi (tien trinh chet giua chung)
      } catch (statErr) {
        if (statErr?.code !== 'ENOENT') throw statErr;
      }
    }
  }
  return false;
}

/**
 * Chay `claude -p /usage` trong thu muc profile de Claude Code lam moi token + cache quota.
 * Moi profile toi da 1 lan / RUN_INTERVAL_MS (ke ca loi, ghi tren dia vi moi lan goi co the la mot tien trinh moi);
 * mot tien trinh /usage mot luc. Khong nem loi: tra { ran, reason?, error? }.
 */
export async function refreshUsageViaCli(profile, nowMs, opts = {}) {
  const { lockDir, runner = defaultRunner, baseEnv = process.env } = opts;
  if (!profile?.configDir || !/^[\w-]+$/.test(String(profile.id))) return { ran: false, reason: 'invalid' };
  const stamp = path.join(lockDir, `usage-cli-${profile.id}.stamp`);
  try {
    const last = Number(fs.readFileSync(stamp, 'utf8'));
    if (Number.isFinite(last) && nowMs - last < RUN_INTERVAL_MS && nowMs >= last) return { ran: false, reason: 'throttled' };
  } catch (err) {
    if (err?.code !== 'ENOENT') logStructured('warn', 'usage_stamp_read_failed', { profileId: profile.id, error: err?.message });
  }
  const lockPath = path.join(lockDir, 'usage-cli.lock');
  if (!acquireLock(lockPath)) return { ran: false, reason: 'busy' };
  try {
    fs.writeFileSync(stamp, String(nowMs), { mode: 0o600 });
    await runner({ command: claudeBinary(), args: usageCliArgs(), env: cleanEnv(baseEnv, profile.configDir), cwd: os.homedir(), timeoutMs: RUN_TIMEOUT_MS });
    return { ran: true };
  } catch (err) {
    logStructured('warn', 'usage_cli_failed', { profileId: profile.id, error: err?.message });
    return { ran: true, error: String(err?.message || err) };
  } finally {
    fs.rmSync(lockPath, { force: true });
  }
}
