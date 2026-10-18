// Tien trinh chay nen (Daemon): theo doi log CC Switch phat hien Rate Limit 429 va lang nghe lenh Telegram tu dien thoai.
import fs from 'node:fs';
import path from 'node:path';
import { resolveStateDir, logStructured, maskSecret } from './errors.js';
import { rotateNextProfile } from './profiles.js';
import {
  loadTelegramConfig,
  callTelegramApi,
  sendTelegramNotification,
  handleTelegramCommand,
} from './telegram.js';

const RATE_LIMIT_PATTERNS = [
  /\b429\b.*(?:too many requests|rate[_\s-]?limit)/i,
  /rate_limit_error/i,
  /usage limit reached/i,
  /quota exceeded/i,
  /exceeded your current quota/i,
];

/**
 * Kiem tra xem doan log moi co chua dau hieu cham Rate Limit (429 / Quota Exhausted) hay khong.
 */
export function detectRateLimitInLogChunk(chunk) {
  const text = String(chunk || '');
  if (!text) return false;
  return RATE_LIMIT_PATTERNS.some((re) => re.test(text));
}

/**
 * Khoi dong Daemon giam sat log + Long-Polling Telegram Bot.
 * Dam bao giai phong toan bo timer/watcher khi nhan SIGTERM/SIGINT.
 */
export async function startSwitcherDaemon(opts = {}) {
  const stateDir = resolveStateDir(opts.stateDir);
  const logFile = opts.logFile || path.join(stateDir, 'logs', 'cc-switch.log');
  const pollIntervalMs = opts.pollIntervalMs || 4000;

  let stopped = false;
  let lastLogSize = fs.existsSync(logFile) ? fs.statSync(logFile).size : 0;
  let lastAutoRotateAtMs = 0;
  let telegramUpdateOffset = 0;

  logStructured('info', 'daemon_started', { stateDir, logFile, pollIntervalMs });

  const checkLogStep = async () => {
    if (stopped || !fs.existsSync(logFile)) return;
    try {
      const stat = fs.statSync(logFile);
      if (stat.size < lastLogSize) {
        lastLogSize = 0;
      }
      if (stat.size > lastLogSize) {
        const readLen = Math.min(stat.size - lastLogSize, 65536);
        const fd = fs.openSync(logFile, 'r');
        const buf = Buffer.alloc(readLen);
        try {
          fs.readSync(fd, buf, 0, readLen, stat.size - readLen);
        } finally {
          fs.closeSync(fd);
        }
        lastLogSize = stat.size;
        const chunk = buf.toString('utf8');
        const nowMs = Date.now();
        // Chong spam trigger lien tuc trong 30s
        if (detectRateLimitInLogChunk(chunk) && nowMs - lastAutoRotateAtMs > 30_000) {
          lastAutoRotateAtMs = nowMs;
          const rotated = rotateNextProfile({
            stateDir,
            nowMs,
            markCurrentLimited: true,
            reason: 'log_detected_429',
          });
          const msg = [
            '🚨 [AUTO-SWITCHER] PHÁT HIỆN CHẠM HẠN MỨC 429',
            `❄️ Đã đóng băng 5h: ${rotated.previousProfile.name}`,
            `▶️ Đã chuyển sang: ${rotated.activeProfile.name}`,
            rotated.requiredWaitSec > 0
              ? `⏳ Khuyến nghị nghỉ an toàn: ${Math.ceil(rotated.requiredWaitSec / 60)} phút`
              : '✅ Sẵn sàng tiếp tục code an toàn (0 nguy cơ ban).',
          ].join('\n');
          await sendTelegramNotification(msg, { stateDir });
        }
      }
    } catch (err) {
      logStructured('warn', 'daemon_log_check_error', { error: err?.message });
    }
  };

  const pollTelegramStep = async () => {
    if (stopped) return;
    const cfg = loadTelegramConfig(stateDir);
    if (!cfg.botToken) return;
    try {
      const updates = await callTelegramApi(
        cfg.botToken,
        `getUpdates?offset=${telegramUpdateOffset}&timeout=1`,
      );
      if (!Array.isArray(updates)) return;
      for (const u of updates) {
        telegramUpdateOffset = Math.max(telegramUpdateOffset, (u.update_id || 0) + 1);
        const msg = u.message || u.edited_message;
        const text = msg?.text;
        const fromChatId = String(msg?.chat?.id || '');
        if (!text || !fromChatId) continue;
        // Chi cho phep chatId da dang ky (hoac tu dong nhan neu chua dat chatId)
        if (cfg.chatId && String(cfg.chatId) !== fromChatId) continue;
        const reply = await handleTelegramCommand(text, { stateDir });
        await callTelegramApi(cfg.botToken, 'sendMessage', {
          chat_id: fromChatId,
          text: reply,
        });
      }
    } catch (err) {
      logStructured('warn', 'daemon_telegram_poll_error', {
        error: maskSecret(err?.message, [cfg.botToken]),
      });
    }
  };

  const timer = setInterval(async () => {
    await checkLogStep();
    await pollTelegramStep();
  }, pollIntervalMs);

  const stop = () => {
    if (stopped) return;
    stopped = true;
    clearInterval(timer);
    logStructured('info', 'daemon_stopped', { stateDir });
  };

  process.once('SIGTERM', stop);
  process.once('SIGINT', stop);

  return { stop };
}
