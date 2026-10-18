// Tich hop Telegram Bot 2 chieu: gui canh bao khi het quota/chuyen profile va nhan lenh dieu khien tu dien thoai.
import fs from 'node:fs';
import path from 'node:path';
import {
  AppError,
  resolveStateDir,
  writeFileAtomic,
  maskSecret,
  logStructured,
} from './errors.js';
import {
  getStatusReport,
  switchProfile,
  rotateNextProfile,
  updateAntiBanPolicy,
} from './profiles.js';

export { maskSecret };

function telegramEnvPath(stateDir) {
  return path.join(resolveStateDir(stateDir), 'telegram.env');
}

/**
 * Nap cau hinh Telegram tu bien moi truong hoac file ~/.cc-switch/telegram.env (quyen 0600, ngoai Git).
 */
export function loadTelegramConfig(stateDir) {
  const file = telegramEnvPath(stateDir);
  const parsed = {};
  if (fs.existsSync(file)) {
    try {
      const lines = fs.readFileSync(file, 'utf8').split('\n');
      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) continue;
        const eqIdx = trimmed.indexOf('=');
        if (eqIdx > 0) {
          const k = trimmed.slice(0, eqIdx).trim();
          const v = trimmed.slice(eqIdx + 1).trim();
          parsed[k] = v;
        }
      }
    } catch (err) {
      logStructured('warn', 'read_telegram_env_failed', { error: err?.message });
    }
  }

  return {
    botToken: process.env.TELEGRAM_BOT_TOKEN || parsed.TELEGRAM_BOT_TOKEN || '',
    chatId: process.env.TELEGRAM_CHAT_ID || parsed.TELEGRAM_CHAT_ID || '',
    envFile: file,
  };
}

/**
 * Luu cau hinh Telegram an toan voi quyen 0600 (chi chu so huu may doc duoc).
 */
export function saveTelegramConfig(stateDir, { botToken, chatId }) {
  const current = loadTelegramConfig(stateDir);
  const nextToken = botToken !== undefined ? String(botToken).trim() : current.botToken;
  const nextChat = chatId !== undefined ? String(chatId).trim() : current.chatId;

  const content = [
    '# Cau hinh Telegram Bot cho CC Switcher (Quyen 0600 - Khong commit vao Git)',
    `TELEGRAM_BOT_TOKEN=${nextToken}`,
    `TELEGRAM_CHAT_ID=${nextChat}`,
    '',
  ].join('\n');

  writeFileAtomic(current.envFile, content, 0o600);
  return {
    botTokenMasked: maskSecret(nextToken, [nextToken]),
    chatId: nextChat,
    envFile: current.envFile,
  };
}

/**
 * Goi API Telegram voi timeout 10s (tuan thu Engineering Musts: connect <= 10s).
 */
export async function callTelegramApi(botToken, method, body = null) {
  if (!botToken) {
    throw new AppError('TELEGRAM_NOT_CONFIGURED', 'Chua cau hinh TELEGRAM_BOT_TOKEN.');
  }
  const url = `https://api.telegram.org/bot${botToken}/${method}`;
  const init = {
    method: body ? 'POST' : 'GET',
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(10000),
  };

  let res;
  try {
    res = await fetch(url, init);
  } catch (err) {
    throw new AppError(
      'TELEGRAM_NETWORK_ERROR',
      `Khong ket noi duoc Telegram API (${method}): ${maskSecret(err?.message, [botToken])}`,
    );
  }

  const data = await res.json().catch(() => ({ ok: false, description: `HTTP ${res.status}` }));
  if (!res.ok || !data.ok) {
    throw new AppError(
      'TELEGRAM_API_ERROR',
      `Telegram API tra ve loi (${res.status}): ${data.description || 'Unknown error'}`,
      { hint: 'Kiem tra lai Bot Token tu @BotFather va dam bao da nhan /start vao bot.' },
    );
  }
  return data.result;
}

/**
 * Tu dong tim chat_id tu tin nhan gan nhat nguoi dung gui cho Bot (/start).
 */
export async function discoverChatId(botToken) {
  const updates = await callTelegramApi(botToken, 'getUpdates');
  if (!Array.isArray(updates) || updates.length === 0) return '';
  for (let i = updates.length - 1; i >= 0; i -= 1) {
    const chatId = updates[i]?.message?.chat?.id || updates[i]?.edited_message?.chat?.id;
    if (chatId) return String(chatId);
  }
  return '';
}

/**
 * Gui tin nhan thong bao ve dien thoai qua Telegram (khong lam sap luong chinh neu loi mang).
 */
export async function sendTelegramNotification(text, opts = {}) {
  const cfg = loadTelegramConfig(opts.stateDir);
  if (!cfg.botToken || !cfg.chatId) {
    return { sent: false, reason: 'missing_token_or_chat_id' };
  }
  try {
    await callTelegramApi(cfg.botToken, 'sendMessage', {
      chat_id: cfg.chatId,
      text,
    });
    return { sent: true };
  } catch (err) {
    logStructured('warn', 'telegram_notify_failed', { error: maskSecret(err?.message, [cfg.botToken]) });
    return { sent: false, reason: maskSecret(err?.message, [cfg.botToken]) };
  }
}

/**
 * Dinh dang bao cao trang thai gon dep cho tin nhan Telegram tren dien thoai.
 */
export function formatStatusForTelegram(report) {
  const lines = [
    '📡 CC SWITCHER — TRẠNG THÁI 6 PROFILE',
    `▶️ Đang chạy: ${report.activeProfile.name}`,
    `⏱ Cooldown Claude còn lại: ${report.claudeCooldownRemainSec}s`,
    `🛡 Chính sách nghỉ: ${Math.round(report.policy.claudeSwitchCooldownSec / 60)} phút (Claude) | Đông băng 429: ${Math.round(report.policy.rateLimitFreezeSec / 3600)}h`,
    `💰 Tổng chi phí ghi nhận: $${report.usage.totalCostUsd} (${report.usage.totalRequests} requests)`,
    '',
    '📋 Danh sách tài khoản:',
  ];

  for (const p of report.profiles) {
    const icon = p.isActive ? '🟢' : (p.isFrozen ? '❄️' : '⚪️');
    lines.push(`${icon} [${p.index}] ${p.id}: ${p.status} — ${p.name}`);
  }

  lines.push('');
  lines.push('💡 Lệnh điều khiển từ điện thoại:');
  lines.push('/status — Xem trạng thái & token');
  lines.push('/switch <1..6> — Đổi sang profile chỉ định');
  lines.push('/rotate — Tự động chuyển sang profile an toàn kế tiếp');
  lines.push('/limit — Báo tài khoản hiện tại dính 429 (đóng băng 5h + xoay vòng)');
  lines.push('/cooldown <phút> — Đặt thời gian nghỉ chống ban (VD: /cooldown 15)');
  return lines.join('\n');
}

/**
 * Xu ly lenh van ban nhan tu Telegram (/status, /switch, /rotate, /limit, /cooldown, /help).
 */
export async function handleTelegramCommand(rawText, opts = {}) {
  const { stateDir, nowMs = Date.now() } = opts;
  const text = String(rawText || '').trim();
  const [cmdRaw, ...args] = text.split(/\s+/);
  const cmd = cmdRaw.toLowerCase().split('@')[0];

  if (cmd === '/start' || cmd === '/help' || cmd === '/status') {
    const report = getStatusReport({ stateDir, nowMs });
    return formatStatusForTelegram(report);
  }

  if (cmd === '/switch') {
    const target = args[0];
    if (!target) {
      return '⚠️ Vui lòng nhập số 1..6 hoặc ID. Ví dụ: /switch 2 hoặc /switch antigravity';
    }
    const force = args.includes('--force');
    try {
      const res = switchProfile({
        stateDir,
        target,
        nowMs,
        enforceCooldown: !force,
        reason: 'telegram_remote_switch',
      });
      return [
        '✅ ĐÃ CHUYỂN PROFILE THÀNH CÔNG',
        `• Từ: ${res.previousProfile.name}`,
        `• Sang: ${res.activeProfile.name}`,
        `• Chống ban: CLAUDE_DISABLE_TELEMETRY=${res.env.CLAUDE_DISABLE_TELEMETRY}`,
      ].join('\n');
    } catch (err) {
      return `⛔️ ${err.message}\n(Gõ "/switch ${target} --force" nếu muốn bỏ qua thời gian chờ)`;
    }
  }

  if (cmd === '/rotate' || cmd === '/next' || cmd === '/limit') {
    const markLimited = cmd === '/limit';
    const res = rotateNextProfile({
      stateDir,
      nowMs,
      markCurrentLimited: markLimited,
      reason: markLimited ? 'telegram_reported_429' : 'telegram_rotate',
    });
    const waitNote = res.requiredWaitSec > 0
      ? `\n⏳ Khuyến nghị chờ an toàn: ${res.requiredWaitSec}s trước khi gửi prompt tiếp theo.`
      : '';
    return [
      markLimited ? '🚨 ĐÃ ĐÓNG BĂNG TÀI KHOẢN 5 GIỜ & XOAY VÒNG' : '🔄 ĐÃ XOAY VÒNG PROFILE AN TOÀN',
      `• Tài khoản trước: ${res.previousProfile.name}`,
      `• Tài khoản mới: ${res.activeProfile.name}${waitNote}`,
    ].join('\n');
  }

  if (cmd === '/cooldown') {
    const minutes = Number(args[0]);
    if (!Number.isFinite(minutes) || minutes < 0 || minutes > 1440) {
      return '⚠️ Vui lòng nhập số phút hợp lệ (0 - 1440). Ví dụ: /cooldown 15';
    }
    const policy = updateAntiBanPolicy(stateDir, {
      claudeSwitchCooldownSec: Math.round(minutes * 60),
    });
    return `🛡 Đã cập nhật thời gian nghỉ chống ban giữa các tài khoản Claude: ${minutes} phút (${policy.claudeSwitchCooldownSec}s).`;
  }

  return '❓ Lệnh không hợp lệ. Gõ /status để xem danh sách lệnh điều khiển.';
}
