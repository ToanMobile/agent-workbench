// Lop loi trung tam va cac tien ich ghi file nguyen khoi, log co cau truc, che giau secret.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

/**
 * Lop loi chuan cho toan bo ung dung (tuan thu Node.js production rules).
 */
export class AppError extends Error {
  constructor(code, message, opts = {}) {
    super(message);
    this.name = 'AppError';
    this.code = code || 'INTERNAL_ERROR';
    this.isOperational = opts.isOperational ?? true;
    this.hint = opts.hint || '';
    this.detail = opts.detail || '';
  }
}

/**
 * Dam bao thu muc ton tai.
 */
export function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
  return dirPath;
}

/**
 * Ghi file nguyen khoi (atomic write) qua file tam roi rename de tranh hong du lieu khi mat dien/ngat tien trinh.
 */
export function writeFileAtomic(filePath, content, mode = 0o600) {
  ensureDir(path.dirname(filePath));
  const tmpFile = `${filePath}.tmp-${process.pid}-${Date.now()}`;
  fs.writeFileSync(tmpFile, content, { mode });
  fs.renameSync(tmpFile, filePath);
  return filePath;
}

/**
 * Ghi JSON nguyen khoi.
 */
export function writeJsonAtomic(filePath, data, mode = 0o600) {
  return writeFileAtomic(filePath, `${JSON.stringify(data, null, 2)}\n`, mode);
}

/**
 * Doc JSON an toan, tra ve fallback neu file chua ton tai hoac loi dinh dang.
 */
export function readJsonSafe(filePath, fallback = null) {
  try {
    if (!fs.existsSync(filePath)) return fallback;
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (err) {
    logStructured('warn', 'read_json_failed', { filePath, error: err?.message });
    return fallback;
  }
}

/**
 * Che giau token Telegram va cac chuoi nhay cam truoc khi dua ra log hoac tra ve client.
 */
export function maskSecret(input, extraSecrets = []) {
  let text = String(input ?? '');
  for (const sec of extraSecrets) {
    if (sec && String(sec).length >= 6) {
      text = text.split(String(sec)).join('***REDACTED***');
    }
  }
  // Che bot token dang <digits>:<alphanumeric>
  text = text.replace(/\b\d{7,12}:[A-Za-z0-9_-]{20,}\b/g, '***REDACTED***');
  return text;
}

/**
 * Ghi log co cau truc JSON ra stderr (khong anh huong kenh stdout cua giao thuc MCP stdio).
 */
export function logStructured(level, event, meta = {}) {
  if (process.env.CC_SWITCHER_QUIET === '1') return;
  const payload = {
    ts: new Date().toISOString(),
    level,
    service: 'cc-switcher-mcp',
    event,
    ...meta,
  };
  process.stderr.write(`${ maskSecret(JSON.stringify(payload)) }\n`);
}

/**
 * Thu muc trang thai mac dinh cua CC Switch (~/.cc-switch).
 */
export function resolveStateDir(customDir) {
  return ensureDir(customDir || process.env.CC_SWITCH_DIR || path.join(os.homedir(), '.cc-switch'));
}
