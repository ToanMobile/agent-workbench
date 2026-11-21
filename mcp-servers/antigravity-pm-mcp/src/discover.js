// Tim "tay cam" RPC loopback cua chinh IDE Antigravity dang chay tren may nay.
//
// Antigravity tu bom 2 bien moi truong (dia chi language server + khoa phien CSRF cua
// loopback) vao moi terminal no mo ra. Khi MCP server nay chay NGOAI IDE thi phai lay
// lai dung cap do tu process table — chinh xac nhu terminal tich hop cua Antigravity lam.
//
// Quy tac bat buoc: khoa phien CHI nam trong bo nho, KHONG ghi ra file, KHONG tra ve cho model.
// Cache chi luu pid + cong.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { run, homeStateDir, readJsonIfExists, writeJsonAtomic, logStderr } from './util.js';

export const ENV_ADDRESS = 'ANTIGRAVITY_LS_ADDRESS';
export const ENV_TOKEN = 'ANTIGRAVITY_CSRF_TOKEN';

const LS_PROC_MATCH = 'language_server';
const CACHE_FILE = () => path.join(homeStateDir(), 'ls.json');
const NIL_UUID = '00000000-0000-0000-0000-000000000000';
const SAFE_DIR_RE = /^[A-Za-z0-9._-]+$/;
const TOKEN_RE = /^[A-Za-z0-9_-]{8,}$/;

export class AntigravityUnavailable extends Error {
  constructor(message, hint) {
    super(message);
    this.name = 'AntigravityUnavailable';
    this.hint = hint || 'Mo app Antigravity va mo dung project can lam viec, roi thu lai.';
  }
}

/** Duong dan binary agentapi. */
export function agentapiPath() {
  const home = process.env.HOME || os.homedir() || '';
  const exe = process.env.ANTIGRAVITY_AGENTAPI_EXE;
  // CLI `agy` tu dat ANTIGRAVITY_AGENTAPI_EXE=.../agy, nhung `agy` khong nhan lenh `get-conversation-metadata` cua agentapi.
  const usableExe = exe && path.basename(exe) !== 'agy' ? exe : null;
  const candidates = [
    process.env.ANTIGRAVITY_PM_AGENTAPI,
    usableExe,
    path.join(home, '.gemini/antigravity/bin/agentapi'),
    path.join(home, '.gemini/antigravity-ide/bin/agentapi'),
  ].filter(Boolean);
  for (const c of candidates) {
    try { fs.accessSync(c, fs.constants.X_OK); return c; } catch { /* thu cai ke tiep */ }
  }
  return null;
}

/** Chi chap nhan thu muc/file that thuoc user hien tai, khong symlink va khong cho group/other ghi. */
function safeLstat(target, expectDir) {
  let st;
  try { st = fs.lstatSync(target); } catch { return null; }
  if (st.isSymbolicLink()) return null;
  if (expectDir ? !st.isDirectory() : !st.isFile()) return null;
  if (typeof process.getuid === 'function' && st.uid !== process.getuid()) return null;
  if ((st.mode & 0o022) !== 0) return null;
  return st;
}

/** Lay ten thu muc app_data_dir an toan tu argv (chan path traversal / duong dan tuyet doi). */
function appDataDirsFromArgs(line) {
  const m = /--app_data_dir(?:=|\s+)([^\s]+)/.exec(line);
  if (!m) return ['antigravity', 'antigravity-ide'];
  const name = m[1].replace(/^['"]|['"]$/g, '');
  if (!SAFE_DIR_RE.test(name) || name === '.' || name === '..') return [];
  return [name];
}

/** Tim file daemon hub_<port>.json khop dung pid trong ~/.gemini/<app_data_dir>/daemon. */
function findDaemonEntry(pid, line) {
  const home = process.env.HOME || os.homedir() || '';
  if (!home) return null;
  const geminiDir = path.join(home, '.gemini');
  if (!safeLstat(geminiDir, true)) return null;

  const matches = [];
  for (const dirName of appDataDirsFromArgs(line)) {
    const appDir = path.join(geminiDir, dirName);
    if (!safeLstat(appDir, true)) continue;
    const daemonDir = path.join(appDir, 'daemon');
    if (!safeLstat(daemonDir, true)) continue;
    let entries;
    try { entries = fs.readdirSync(daemonDir); } catch { continue; }
    for (const name of entries) {
      if (!/^hub_\d+\.json$/.test(name)) continue;
      const filePath = path.join(daemonDir, name);
      const st = safeLstat(filePath, false);
      if (!st) continue;
      let data;
      try { data = JSON.parse(fs.readFileSync(filePath, 'utf8')); } catch { continue; }
      if (!data || typeof data !== 'object' || Array.isArray(data)) continue;
      if (Number(data.pid) !== pid) continue;
      if (typeof data.csrfToken !== 'string' || !TOKEN_RE.test(data.csrfToken)) continue;
      const hintPorts = Number.isInteger(data.httpPort) && data.httpPort >= 1 && data.httpPort <= 65535
        ? [data.httpPort]
        : [];
      matches.push({ pid, secret: data.csrfToken, hintPorts, mtimeMs: st.mtimeMs });
    }
  }
  if (matches.length === 0) return null;
  matches.sort((a, b) => b.mtimeMs - a.mtimeMs);
  return matches[0];
}

/** Doc process table, lay pid + khoa phien cua language_server dang chay. */
async function findLsProcess() {
  const psBin = process.env.ANTIGRAVITY_PM_PS || '/bin/ps';
  const ps = await run(psBin, ['ax', '-o', 'pid=,command='], { timeoutMs: 15000 });
  if (ps.code !== 0 && !ps.stdout) throw new AntigravityUnavailable('Khong doc duoc process table (ps that bai).');
  const lines = ps.stdout.split('\n').filter((l) => l.includes(LS_PROC_MATCH) && l.includes('--standalone'));
  for (const line of lines) {
    const pid = Number(line.trim().split(/\s+/)[0]);
    if (!Number.isInteger(pid) || pid <= 0) continue;
    const m = /--csrf_token[= ]([0-9a-fA-F-]{8,})/.exec(line);
    if (m) return { pid, secret: m[1], hintPorts: [] };
    const daemon = findDaemonEntry(pid, line);
    if (daemon) return { pid: daemon.pid, secret: daemon.secret, hintPorts: daemon.hintPorts };
  }
  throw new AntigravityUnavailable(
    'Khong thay tien trinh Antigravity language_server nao dang chay.',
    'Mo app Antigravity (va mo project can lam) roi thu lai — MCP nay dieu khien IDE dang mo, khong tu bat IDE len.',
  );
}

/** Liet ke cong LISTEN cua pid do. */
async function listenPorts(pid) {
  const r = await run('/usr/sbin/lsof', ['-nP', '-iTCP', '-sTCP:LISTEN', '-a', '-p', String(pid)], { timeoutMs: 20000 });
  const ports = [];
  for (const line of r.stdout.split('\n').slice(1)) {
    const m = /:(\d+)\s+\(LISTEN\)/.exec(line);
    if (m) ports.push(Number(m[1]));
  }
  return [...new Set(ports)];
}

/** Goi thu 1 cong: true neu day dung la dau gRPC ma agentapi noi duoc. */
async function probePort(address, secret, agentapi) {
  const r = await run(agentapi, ['get-conversation-metadata', NIL_UUID], {
    timeoutMs: 25000,
    env: { [ENV_ADDRESS]: address, [ENV_TOKEN]: secret },
  });
  const blob = `${r.stdout}${r.stderr}`;
  if (/Unauthenticated|missing CSRF/i.test(blob)) return false;
  if (/connection error|connection reset|Unavailable/i.test(blob)) return false;
  // Noi duoc = hoac tra ve metadata, hoac bao khong tim thay conversation.
  return /"response"|NotFound|not found|InvalidArgument/i.test(blob);
}

/** Thu tung cong, tra ve ket noi dau tien tra loi agentapi va luu cache pid + cong. */
async function tryPorts(ports, { pid, secret, agentapi }) {
  for (const p of ports) {
    const address = `127.0.0.1:${p}`;
    if (await probePort(address, secret, agentapi)) {
      writeJsonAtomic(CACHE_FILE(), { pid, address, at: new Date().toISOString() });
      logStderr(`da noi duoc language_server tai ${address} (pid ${pid})`);
      return { address, secret, pid, agentapi, source: 'probe' };
    }
  }
  return null;
}

/**
 * Tra ve { address, secret, pid, agentapi, source }.
 * force=true: bo cache, do lai tu dau (goi khi RPC bat dau loi).
 */
export async function discover({ force = false } = {}) {
  const agentapi = agentapiPath();
  if (!agentapi) {
    throw new AntigravityUnavailable(
      'Khong tim thay binary agentapi cua Antigravity.',
      'Mo Antigravity 1 lan de no sinh ~/.gemini/antigravity/bin/agentapi, hoac tro bien ANTIGRAVITY_PM_AGENTAPI vao dung file.',
    );
  }

  // Neu MCP nay duoc chay TU TRONG terminal cua Antigravity thi da co san env.
  if (process.env[ENV_ADDRESS] && process.env[ENV_TOKEN]) {
    return {
      address: process.env[ENV_ADDRESS],
      secret: process.env[ENV_TOKEN],
      pid: null,
      agentapi,
      source: 'env',
    };
  }

  const { pid, secret, hintPorts = [] } = await findLsProcess();

  if (!force) {
    const cached = readJsonIfExists(CACHE_FILE());
    if (cached && cached.pid === pid && cached.address) {
      if (await probePort(cached.address, secret, agentapi)) {
        return { address: cached.address, secret, pid, agentapi, source: 'cache' };
      }
    }
  }

  const hinted = await tryPorts(hintPorts, { pid, secret, agentapi });
  if (hinted) return hinted;

  const tried = new Set(hintPorts);
  const ports = (await listenPorts(pid)).filter((p) => !tried.has(p));
  if (ports.length === 0 && hintPorts.length === 0) {
    throw new AntigravityUnavailable(`language_server (pid ${pid}) khong mo cong LISTEN nao.`);
  }
  const found = await tryPorts(ports, { pid, secret, agentapi });
  if (found) return found;

  const allPorts = [...new Set([...hintPorts, ...ports])];
  throw new AntigravityUnavailable(
    `Thay language_server (pid ${pid}) nhung khong cong nao trong [${allPorts.join(', ')}] tra loi agentapi.`,
    'Antigravity co the dang khoi dong hoac vua doi phien ban. Thu lai sau vai giay, hoac khoi dong lai IDE.',
  );
}

export function forgetCache() {
  try { fs.rmSync(CACHE_FILE(), { force: true }); } catch { /* khong sao */ }
}
