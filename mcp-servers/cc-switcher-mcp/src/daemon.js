// Tien trinh chay nen (Daemon): theo doi log CC Switch phat hien Rate Limit 429, gui canh bao Telegram va xu ly nut duyet super-board.
// Bang dieu khien CC Switcher nam tren web (Agent Office /cc-switcher), khong con tren Telegram.
import fs from 'node:fs';
import path from 'node:path';
import { resolveStateDir, logStructured, maskSecret } from './errors.js';
import { rotateNextProfile } from './profiles.js';
import {
  loadTelegramConfig,
  saveTelegramConfig,
  callTelegramApi,
  fetchUpdatesSafely,
  sendTelegramNotification,
  handleTelegramCommand,
  handleTelegramCallback,
  refuseForeignTelegramChat,
  clearLegacyTelegramPanel,
  REMOVE_REPLY_KEYBOARD,
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
 * Bo doc duoi file log co nho dem goi dau (rolling tail overlap 256 byte) va cat an toan ranh gioi UTF-8.
 */
export function createLogTailReader(logFile) {
  let lastLogSize = fs.existsSync(logFile) ? fs.statSync(logFile).size : 0;
  let carryOver = '';

  return {
    readNewChunk() {
      if (!fs.existsSync(logFile)) return '';
      const stat = fs.statSync(logFile);
      if (stat.size < lastLogSize) {
        lastLogSize = 0;
        carryOver = '';
      }
      if (stat.size <= lastLogSize) return '';

      const delta = stat.size - lastLogSize;
      const readLen = Math.min(delta, 65536);
      const fd = fs.openSync(logFile, 'r');
      let buf = Buffer.alloc(readLen);
      try {
        fs.readSync(fd, buf, 0, readLen, stat.size - readLen);
      } finally {
        fs.closeSync(fd);
      }
      lastLogSize = stat.size;

      // Bo cac byte tiep noi UTF-8 (10xxxxxx) o dau neu phai cat bot do delta > 65536
      if (delta > 65536) {
        let i = 0;
        while (i < buf.length && i < 4 && (buf[i] & 0xc0) === 0x80) i += 1;
        buf = buf.subarray(i);
      }

      const freshText = buf.toString('utf8');
      const combined = `${carryOver}${freshText}`;
      carryOver = combined.slice(-256);
      return combined;
    },
  };
}

/**
 * Xu ly danh sach updates tu Telegram (tin nhan van ban, nut Reply Keyboard, va nut Inline Callback Query).
 * Tu dong bind va luu chatId khi nhan tuong tac dau tien.
 */
export async function processIncomingTelegramUpdates(updates, opts = {}) {
  const { stateDir, currentOffset = 0, apiCaller = callTelegramApi } = opts;
  let nextOffset = currentOffset;
  if (!Array.isArray(updates) || updates.length === 0) return nextOffset;

  let cfg = loadTelegramConfig(stateDir);
  for (const u of updates) {
    nextOffset = Math.max(nextOffset, (u.update_id || 0) + 1);
    // Ghi offset TRƯỚC khi xử lý (tối đa một lần): daemon thoát giữa chừng thì không phát lại update đã nhận (rotate, swap, `done`).
    if (opts.onOffset) opts.onOffset(nextOffset);

    // 1. Xu ly khi nguoi dung cham nut tren Inline Keyboard (callback_query)
    if (u.callback_query) {
      const cbq = u.callback_query;
      const fromChatId = String(cbq.message?.chat?.id || cbq.from?.id || '');
      if (!fromChatId) continue;

      const cbData = String(cbq.data || '');
      const boundChat = String(cfg.chatId || '');
      if ((boundChat && boundChat !== fromChatId) || (!boundChat && cbData.startsWith('sb:'))) {
        try {
          await refuseForeignTelegramChat(apiCaller, cfg.botToken, cbq);
        } catch (err) {
          logStructured('warn', 'telegram_answer_cbq_failed', { error: err?.message });
        }
        continue;
      }

      if (!boundChat) {
        saveTelegramConfig(stateDir, { chatId: fromChatId });
        cfg = loadTelegramConfig(stateDir);
        logStructured('info', 'telegram_chat_id_bound', { chatId: fromChatId });
      }

      const cbResult = await handleTelegramCallback(cbq, { stateDir, ...(opts.callbackOpts || {}) });
      try {
        await apiCaller(cfg.botToken, 'answerCallbackQuery', {
          callback_query_id: cbq.id,
          text: cbResult.toastText,
          show_alert: Boolean(cbResult.showAlert),
        });
      } catch (err) {
        logStructured('warn', 'telegram_answer_cbq_failed', { error: err?.message });
      }

      // Nut cua bang dieu khien cu: go hang nut khoi tin nhan (bang dieu khien da chuyen sang web)
      const msgId = cbq.message?.message_id;
      if (msgId && cbResult.clearButtons) {
        try {
          await apiCaller(cfg.botToken, 'editMessageReplyMarkup', {
            chat_id: fromChatId,
            message_id: msgId,
            reply_markup: { inline_keyboard: [] },
          });
        } catch (err) {
          if (!/not modified/i.test(String(err?.message || ''))) {
            logStructured('warn', 'telegram_clear_buttons_failed', { error: err?.message });
          }
        }
      }
      continue;
    }

    // 2. Xu ly khi nguoi dung gui tin nhan hoac cham nut tren Persistent Reply Keyboard
    const msg = u.message || u.edited_message;
    const text = msg?.text;
    const fromChatId = String(msg?.chat?.id || '');
    if (!text || !fromChatId) continue;

    const isFirstBind = !cfg.chatId;
    if (isFirstBind) {
      saveTelegramConfig(stateDir, { chatId: fromChatId });
      cfg = loadTelegramConfig(stateDir);
      logStructured('info', 'telegram_chat_id_bound', { chatId: fromChatId });
    } else if (String(cfg.chatId) !== fromChatId) {
      continue;
    }

    // Bang dieu khien da chuyen sang web: moi tin nhan nhan lai link va go ban phim ghim cu khoi day man hinh.
    const reply = await handleTelegramCommand(text, { stateDir });
    await apiCaller(cfg.botToken, 'sendMessage', {
      chat_id: fromChatId,
      text: reply,
      reply_markup: REMOVE_REPLY_KEYBOARD,
    });
  }
  return nextOffset;
}

// Offset getUpdates qua các lần khởi động: `<botId>:<offset>` trong <stateDir>/telegram.offset. botId = phần trước ':' của token (định
// danh công khai của bot, không phải bí mật): đổi bot thì offset của bot cũ không được dùng (review N2: update của bot mới bị bỏ qua).
// Thiếu / hỏng / bot khác = 0 như trước.
function botIdOf(token) {
  return String(token || '').split(':')[0];
}

function readTelegramOffset(file, botId) {
  try {
    const m = /^([^:\s]+):(\d{1,15})$/.exec(fs.readFileSync(file, 'utf8').trim());
    return m && m[1] === botId ? Number(m[2]) : 0;
  } catch (err) {
    if (err?.code !== 'ENOENT') logStructured('warn', 'telegram_offset_read_failed', { error: err?.message });
    return 0;
  }
}

function writeTelegramOffset(file, botId, offset) {
  const tmp = `${file}.${process.pid}.tmp`;
  try {
    fs.writeFileSync(tmp, `${botId}:${offset}\n`);
    fs.renameSync(tmp, file);   // nguyên tử: một lần thoát giữa chừng không để file offset dở
  } catch (err) {
    logStructured('warn', 'telegram_offset_write_failed', { error: err?.message });
    fs.rmSync(tmp, { force: true });
  }
}

/**
 * Khoi dong Daemon giam sat log + Long-Polling Telegram Bot.
 * Su dung co khoa inFlight chong chong cheo tick va giai phong toan bo timer khi nhan SIGTERM/SIGINT.
 */
export async function startSwitcherDaemon(opts = {}) {
  const stateDir = resolveStateDir(opts.stateDir);
  const logFile = opts.logFile || path.join(stateDir, 'logs', 'cc-switch.log');
  const pollIntervalMs = opts.pollIntervalMs || 4000;
  // 25/10: một await không bao giờ trả về giữ inFlight true mãi -> mọi lượt sau return ngay, daemon im lặng 5 giờ, bỏ qua nút Approve.
  // Lượt kẹt quá ngưỡng: ghi lỗi và thoát khác 0, launchd (KeepAlive) khởi động lại daemon sạch. 300 s: một lần approve tệ nhất ~70 s
  // (các lời gọi gh 15 s), một batch vài update vẫn dưới ngưỡng. Đo bằng đồng hồ đơn điệu: máy ngủ dậy không bắn nhầm.
  const tickTimeoutMs = opts.tickTimeoutMs || 300_000;
  const fetchUpdates = opts.fetchUpdates || fetchUpdatesSafely;
  const ensureMenu = opts.ensureMenu || clearLegacyTelegramPanel;
  const exit = opts.exit || ((code) => process.exit(code));
  const offsetFile = path.join(stateDir, 'telegram.offset');

  let stopped = false;
  let inFlight = false;
  let tickStartedAt = 0;
  let lastAutoRotateAtMs = 0;
  let telegramUpdateOffset = 0;
  let offsetBot = null;   // bot của telegramUpdateOffset: token đổi (switcher_telegram_setup) thì nạp offset của bot mới
  const logReader = createLogTailReader(logFile);

  logStructured('info', 'daemon_started', { stateDir, logFile, pollIntervalMs });

  const initCfg = loadTelegramConfig(stateDir);
  if (initCfg.botToken) {
    void ensureMenu(initCfg.botToken);
  }

  const checkLogStep = async () => {
    if (stopped) return;
    try {
      const chunk = logReader.readNewChunk();
      if (!chunk) return;
      const nowMs = Date.now();
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
    } catch (err) {
      logStructured('warn', 'daemon_log_check_error', { error: err?.message });
    }
  };

  const pollTelegramStep = async () => {
    if (stopped) return;
    const cfg = loadTelegramConfig(stateDir);
    if (!cfg.botToken) return;
    const botId = botIdOf(cfg.botToken);
    if (botId !== offsetBot) {
      telegramUpdateOffset = readTelegramOffset(offsetFile, botId);
      offsetBot = botId;
    }
    try {
      const updates = await fetchUpdates(cfg.botToken, telegramUpdateOffset);
      telegramUpdateOffset = await processIncomingTelegramUpdates(updates, {
        stateDir,
        currentOffset: telegramUpdateOffset,
        apiCaller: opts.apiCaller,
        onOffset: (offset) => writeTelegramOffset(offsetFile, botId, offset),
      });
    } catch (err) {
      logStructured('warn', 'daemon_telegram_poll_error', {
        error: maskSecret(err?.message, [cfg.botToken]),
      });
    }
  };

  const timer = setInterval(async () => {
    if (stopped) return;
    if (inFlight) {
      const stuckMs = performance.now() - tickStartedAt;
      if (stuckMs > tickTimeoutMs) {
        logStructured('error', 'daemon_tick_stuck', { stuckMs, tickTimeoutMs });
        stop();
        exit(1);
      }
      return;
    }
    inFlight = true;
    tickStartedAt = performance.now();
    try {
      await checkLogStep();
      await pollTelegramStep();
    } finally {
      inFlight = false;
    }
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
