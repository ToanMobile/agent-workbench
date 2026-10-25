// Tien trinh chay nen (Daemon): theo doi log CC Switch phat hien Rate Limit 429 va lang nghe lenh Telegram tu dien thoai.
import fs from 'node:fs';
import path from 'node:path';
import { resolveStateDir, logStructured, maskSecret } from './errors.js';
import { rotateNextProfile, getStatusReport } from './profiles.js';
import {
  loadTelegramConfig,
  saveTelegramConfig,
  callTelegramApi,
  fetchUpdatesSafely,
  sendTelegramNotification,
  handleTelegramCommand,
  handleTelegramCallback,
  refuseForeignTelegramChat,
  buildTelegramDashboard,
  buildReplyKeyboardMarkup,
  ensureTelegramBotMenu,
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

      const msgId = cbq.message?.message_id;
      if (msgId && cbResult.dashboard) {
        try {
          await apiCaller(cfg.botToken, 'editMessageText', {
            chat_id: fromChatId,
            message_id: msgId,
            text: cbResult.dashboard.text,
            reply_markup: cbResult.dashboard.reply_markup,
          });
        } catch (err) {
          // Bo qua neu noi dung khong thay doi ("message is not modified")
          if (!/not modified/i.test(String(err?.message || ''))) {
            await apiCaller(cfg.botToken, 'sendMessage', {
              chat_id: fromChatId,
              text: cbResult.dashboard.text,
              reply_markup: cbResult.dashboard.reply_markup,
            });
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

    const trimmed = text.trim();
    // Neu la /start hoac /menu -> ghim thanh phim tat nhanh o day man hinh truoc khi hien Bang dieu khien Inline
    if (trimmed === '/start' || trimmed === '/menu') {
      try {
        await apiCaller(cfg.botToken, 'sendMessage', {
          chat_id: fromChatId,
          text: '⌨️ Đã ghim thanh phím tắt nhanh ở đáy màn hình. Bạn có thể chạm trực tiếp vào các nút bên dưới bất kỳ lúc nào:',
          reply_markup: buildReplyKeyboardMarkup(),
        });
      } catch (err) {
        logStructured('warn', 'telegram_reply_kb_failed', { error: err?.message });
      }
    }

    const reply = await handleTelegramCommand(text, { stateDir });
    const dash = buildTelegramDashboard(getStatusReport({ stateDir }));
    await apiCaller(cfg.botToken, 'sendMessage', {
      chat_id: fromChatId,
      text: reply,
      reply_markup: dash.reply_markup,
    });
  }
  return nextOffset;
}

// Offset getUpdates qua các lần khởi động (số nguyên >= 0 trong <stateDir>/telegram.offset); thiếu / hỏng = 0 như trước.
function readTelegramOffset(file) {
  try {
    const n = Number.parseInt(fs.readFileSync(file, 'utf8').trim(), 10);
    return Number.isSafeInteger(n) && n > 0 ? n : 0;
  } catch (err) {
    if (err?.code !== 'ENOENT') logStructured('warn', 'telegram_offset_read_failed', { error: err?.message });
    return 0;
  }
}

function writeTelegramOffset(file, offset) {
  const tmp = `${file}.${process.pid}.tmp`;
  try {
    fs.writeFileSync(tmp, `${offset}\n`);
    fs.renameSync(tmp, file);   // nguyên tử: một lần thoát giữa chừng không để file offset dở
  } catch (err) {
    logStructured('warn', 'telegram_offset_write_failed', { error: err?.message });
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
  const ensureMenu = opts.ensureMenu || ensureTelegramBotMenu;
  const exit = opts.exit || ((code) => process.exit(code));
  const offsetFile = path.join(stateDir, 'telegram.offset');

  let stopped = false;
  let inFlight = false;
  let tickStartedAt = 0;
  let lastAutoRotateAtMs = 0;
  let telegramUpdateOffset = readTelegramOffset(offsetFile);
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
    try {
      const updates = await fetchUpdates(cfg.botToken, telegramUpdateOffset);
      telegramUpdateOffset = await processIncomingTelegramUpdates(updates, {
        stateDir,
        currentOffset: telegramUpdateOffset,
        apiCaller: opts.apiCaller,
        onOffset: (offset) => writeTelegramOffset(offsetFile, offset),
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
