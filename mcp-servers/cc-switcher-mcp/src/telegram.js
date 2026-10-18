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
  resetLocks,
  resolveProfile,
  syncLiveQuotas,
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
 * Lay danh sach tin nhan & callback_query moi tu Telegram; neu gap loi 409 Conflict do Webhook cu dang bat,
 * tu dong go deleteWebhook (giu nguyen pending updates) roi thu lai.
 */
export async function fetchUpdatesSafely(botToken, offset = 0, apiCaller = callTelegramApi) {
  const method = `getUpdates?offset=${offset}&timeout=1`;
  try {
    return await apiCaller(botToken, method);
  } catch (err) {
    if (/409|webhook/i.test(String(err?.message || ''))) {
      logStructured('info', 'telegram_auto_delete_webhook', { reason: 'conflict_409_detected' });
      await apiCaller(botToken, 'deleteWebhook', { drop_pending_updates: false });
      return await apiCaller(botToken, method);
    }
    throw err;
  }
}

/**
 * Tu dong tim chat_id tu tin nhan hoac nut bam gan nhat nguoi dung gui cho Bot.
 */
export async function discoverChatId(botToken, apiCaller = callTelegramApi) {
  const updates = await fetchUpdatesSafely(botToken, 0, apiCaller);
  if (!Array.isArray(updates) || updates.length === 0) return '';
  for (let i = updates.length - 1; i >= 0; i -= 1) {
    const chatId =
      updates[i]?.message?.chat?.id ||
      updates[i]?.edited_message?.chat?.id ||
      updates[i]?.callback_query?.message?.chat?.id ||
      updates[i]?.callback_query?.from?.id;
    if (chatId) return String(chatId);
  }
  return '';
}

/**
 * Tao ban phim co dinh duoi day man hinh Telegram (Persistent Reply Keyboard)
 * giup nguoi dung mo bang dieu khien hoac xoay vong 1 cham ma khong can go lenh.
 */
export function buildReplyKeyboardMarkup() {
  return {
    resize_keyboard: true,
    is_persistent: true,
    keyboard: [
      [{ text: '🎛 Bảng điều khiển' }, { text: '🔄 Xoay vòng an toàn' }],
      [{ text: '🚨 Báo kịch 429 (Đổi ngay)' }, { text: '🔓 Mở khóa 429 / Cooldown' }],
    ],
  };
}

/**
 * Dang ky nut Menu xanh (☰ Menu) va danh sach phim tat tren giao dien Telegram.
 */
export async function ensureTelegramBotMenu(botToken, apiCaller = callTelegramApi) {
  if (!botToken) return false;
  try {
    await apiCaller(botToken, 'setMyCommands', {
      commands: [
        { command: 'status', description: '🎛 Mở bảng điều khiển nút bấm (6 tài khoản)' },
        { command: 'menu', description: '⌨️ Ghim thanh phím tắt nhanh ở đáy màn hình' },
        { command: 'rotate', description: '🔄 Xoay vòng sang tài khoản an toàn kế tiếp' },
        { command: 'limit', description: '🚨 Báo kịch 429 (Đóng băng 5h & đổi ngay)' },
        { command: 'unfreeze', description: '🔓 Mở khóa toàn bộ 429 & xóa Cooldown' },
      ],
    });
    await apiCaller(botToken, 'setChatMenuButton', {
      menu_button: { type: 'commands' },
    });
    return true;
  } catch (err) {
    logStructured('warn', 'telegram_menu_setup_failed', { error: maskSecret(err?.message, [botToken]) });
    return false;
  }
}

function formatDurationHuman(totalSec) {
  if (!totalSec || totalSec <= 0) return '0s (Sẵn sàng)';
  const m = Math.floor(totalSec / 60);
  const s = totalSec % 60;
  return m > 0 ? `${m}p ${s}s` : `${s}s`;
}

function renderProgressBar(remainingPct) {
  const pct = Math.max(0, Math.min(100, Number(remainingPct) || 0));
  const filled = Math.round(pct / 10);
  return `[${'█'.repeat(filled)}${'░'.repeat(10 - filled)}]`;
}

/**
 * Dinh dang bao cao trang thai gon dep, hien dai kem % Quota con lai va gio mo khoa cho Telegram.
 */
export function formatStatusForTelegram(report, opts = {}) {
  const { bannerNote = '' } = opts;
  const cooldownBadge =
    report.claudeCooldownRemainSec > 0
      ? `⏳ Đang nghỉ chống ban: còn ${formatDurationHuman(report.claudeCooldownRemainSec)}`
      : '🟢 Sẵn sàng chuyển ngay (0s)';

  const lines = [];
  if (bannerNote) {
    lines.push(bannerNote);
    lines.push('━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  const activePct = report.activeProfile.remainingPct ?? 100;
  const activeReset = report.activeProfile.resetTimeFormatted
    ? ` · Reset ${report.activeProfile.resetTimeFormatted}`
    : '';

  lines.push('🎛 CC SWITCHER — BẢNG ĐIỀU KHIỂN & QUOTA THỰC TẾ');
  lines.push(`▶️ Đang dùng: ${report.activeProfile.name} (Còn ${activePct}%${activeReset})`);
  lines.push(`🛡 Anti-Ban Guard: ${cooldownBadge}`);
  lines.push(
    `⚙️ Cấu hình: Nghỉ ${Math.round(report.policy.claudeSwitchCooldownSec / 60)}p giữa Claude · Đóng băng 429: ${Math.round(report.policy.rateLimitFreezeSec / 3600)}h`,
  );
  lines.push(`💰 Chi phí ghi nhận: $${report.usage.totalCostUsd} (${report.usage.totalRequests} requests)`);
  lines.push('━━━━━━━━━━━━━━━━━━━━━━━━');
  lines.push('📊 CHI TIẾT QUOTA & GIỜ MỞ KHÓA 6 TÀI KHOẢN:');

  for (const p of report.profiles) {
    const pct = p.remainingPct ?? (p.isFrozen ? 0 : 100);
    const used = p.usedPct ?? (100 - pct);
    const bar = renderProgressBar(pct);

    if (p.isFrozen || pct <= 0) {
      const unlockStr = p.resetTimeFormatted
        ? `Mở lại lúc ${p.resetTimeFormatted} (còn ${p.resetRemainHuman || `${p.freezeRemainMin}p`})`
        : `Mở lại sau ${p.freezeRemainMin}p`;
      lines.push(`🔴 [${p.index}] ${p.name}${p.isActive ? ' — ĐANG DÙNG ⚠️' : ''}`);
      lines.push(`   └ ⛔️ HẾT QUOTA (Còn 0%) ${bar} · ⏰ ${unlockStr}`);
    } else {
      const icon = p.isActive ? '🟢' : '⚪️';
      const activeTag = p.isActive ? ' — ĐANG DÙNG ✓' : '';
      const resetNote = p.resetTimeFormatted
        ? ` · ⏰ Reset 5h: ${p.resetTimeFormatted} (còn ${p.resetRemainHuman})`
        : '';
      const weekNote = typeof p.weeklyRemainingPct === 'number'
        ? ` · Tuần: ${p.weeklyRemainingPct}%`
        : '';
      lines.push(`${icon} [${p.index}] ${p.name}${activeTag}`);
      lines.push(`   └ 🔋 Còn ${pct}% ${bar} (Đã dùng ${used}%)${resetNote}${weekNote}`);
    }
  }

  lines.push('');
  lines.push('👇 Chạm trực tiếp vào nút bên dưới để đổi tài khoản ngay:');
  return lines.join('\n');
}

/**
 * Xay dung Bang dieu khien tuong tac (Text + Inline Keyboard 6 profile hien % va gio mo + Cac nut thao tac nhanh).
 */
export function buildTelegramDashboard(report, opts = {}) {
  const { bannerNote = '', forcePromptTargetId = '' } = opts;
  const text = formatStatusForTelegram(report, { bannerNote });

  const inlineKeyboard = [];

  // Neu nguoi dung vua cham vao 1 profile Claude dang vuong Cooldown 15p -> hien nut Ep chuyen 1 cham o hang dau
  if (forcePromptTargetId) {
    const targetProf = report.profiles.find((p) => p.id === forcePromptTargetId);
    const shortName = targetProf?.shortLabel || forcePromptTargetId;
    inlineKeyboard.push([
      {
        text: `⚡ ÉP CHUYỂN NGAY sang ${shortName} (Bỏ qua chờ)`,
        callback_data: `fsw:${forcePromptTargetId}`,
      },
    ]);
  }

  // 3 hang x 2 cot cho 6 profile (hien ro % con lai hoac gio mo khoa ngay tren nhan nut!)
  for (let i = 0; i < report.profiles.length; i += 2) {
    const row = report.profiles.slice(i, i + 2).map((p) => {
      const labelBase = p.shortLabel || `${p.index}. ${p.id}`;
      const pct = p.remainingPct ?? (p.isFrozen ? 0 : 100);
      let btnText = `⚪️ ${labelBase} · ${pct}%`;

      if (p.isFrozen || pct <= 0) {
        const unlockClock = p.resetTimeFormatted || `${p.freezeRemainMin}p`;
        btnText = `🔴 ${labelBase} · 0% (Mở ${unlockClock})`;
      } else if (p.isActive) {
        btnText = `🟢 ${labelBase} · ${pct}% ✓`;
      }

      return {
        text: btnText,
        callback_data: `sw:${p.id}`,
      };
    });
    inlineKeyboard.push(row);
  }

  // Hang thao tac thong minh: Xoay vong ke tiep & Bao kich 429
  inlineKeyboard.push([
    { text: '🔄 Xoay vòng kế tiếp', callback_data: 'act:rotate' },
    { text: '🚨 Báo kịch 429 (Đổi ngay)', callback_data: 'act:limit' },
  ]);

  // Hang mo khoa dong bang & lam moi % Quota
  inlineKeyboard.push([
    { text: '🔓 Mở khóa 429 & Cooldown', callback_data: 'act:unfreeze_all' },
    { text: '🔃 Làm mới % Quota', callback_data: 'act:refresh' },
  ]);

  // Hang chon nhanh muc Cooldown chong ban (15p / 5p / 0p)
  const currentCdMin = Math.round((report.policy?.claudeSwitchCooldownSec ?? 900) / 60);
  inlineKeyboard.push([
    { text: `${currentCdMin === 15 ? '✅' : '🛡'} Nghỉ 15p`, callback_data: 'cd:15' },
    { text: `${currentCdMin === 5 ? '✅' : '🛡'} Nghỉ 5p`, callback_data: 'cd:5' },
    { text: `${currentCdMin === 0 ? '✅' : '🛡'} Tắt chờ (0p)`, callback_data: 'cd:0' },
  ]);

  return {
    text,
    reply_markup: {
      inline_keyboard: inlineKeyboard,
    },
  };
}

async function maybeSyncLiveQuotas(stateDir, nowMs, forceRefresh = false) {
  if (resolveStateDir(stateDir) === resolveStateDir()) {
    await syncLiveQuotas({ stateDir, nowMs, forceRefresh });
  }
}

/**
 * Xu ly su kien khi nguoi dung cham vao nut tren Inline Keyboard (callback_query).
 */
export async function handleTelegramCallback(callbackQuery, opts = {}) {
  const { stateDir, nowMs = Date.now() } = opts;
  const data = String(callbackQuery?.data || '').trim();

  await maybeSyncLiveQuotas(stateDir, nowMs, data === 'act:refresh');

  if (data.startsWith('sw:') || data.startsWith('fsw:')) {
    const force = data.startsWith('fsw:');
    const targetId = data.slice(force ? 4 : 3);
    try {
      const res = switchProfile({
        stateDir,
        target: targetId,
        nowMs,
        enforceCooldown: !force,
        reason: force ? 'telegram_ui_force_switch' : 'telegram_ui_switch',
      });
      const report = getStatusReport({ stateDir, nowMs });
      const bannerNote = `✅ ĐÃ CHUYỂN SANG: ${res.activeProfile.name}`;
      return {
        toastText: `✅ Đã chuyển sang ${res.activeProfile.shortLabel || res.activeProfile.name}`,
        showAlert: false,
        dashboard: buildTelegramDashboard(report, { bannerNote }),
      };
    } catch (err) {
      const report = getStatusReport({ stateDir, nowMs });
      const targetProf = resolveProfile(targetId);
      const bannerNote = [
        `⛔️ CHƯA CHUYỂN: ${err.message}`,
        `👉 Nếu muốn bỏ qua thời gian chờ để đổi ngay sang "${targetProf.shortLabel || targetProf.name}", hãy bấm nút [⚡ ÉP CHUYỂN NGAY] bên dưới.`,
      ].join('\n');
      return {
        toastText: `⏳ Đang khóa/chờ chống ban! Bấm nút "⚡ ÉP CHUYỂN NGAY" nếu muốn đổi luôn.`,
        showAlert: true,
        dashboard: buildTelegramDashboard(report, {
          bannerNote,
          forcePromptTargetId: targetProf.id,
        }),
      };
    }
  }

  if (data === 'act:rotate' || data === 'act:limit') {
    const markLimited = data === 'act:limit';
    const res = rotateNextProfile({
      stateDir,
      nowMs,
      markCurrentLimited: markLimited,
      reason: markLimited ? 'telegram_ui_limit_429' : 'telegram_ui_rotate',
    });
    const report = getStatusReport({ stateDir, nowMs });
    const bannerNote = markLimited
      ? `🚨 Đã đóng băng 5h [${res.previousProfile.shortLabel || res.previousProfile.id}] & chuyển sang: ${res.activeProfile.name}`
      : `🔄 Đã xoay vòng sang: ${res.activeProfile.name}`;
    return {
      toastText: markLimited
        ? `🚨 Đã khóa 5h tài khoản cũ & đổi sang ${res.activeProfile.shortLabel || res.activeProfile.name}`
        : `🔄 Đã xoay sang ${res.activeProfile.shortLabel || res.activeProfile.name}`,
      showAlert: false,
      dashboard: buildTelegramDashboard(report, { bannerNote }),
    };
  }

  if (data === 'act:unfreeze_all') {
    resetLocks(stateDir);
    const report = getStatusReport({ stateDir, nowMs });
    return {
      toastText: '🔓 Đã xóa toàn bộ đóng băng 429 & đặt lại Cooldown về 0s!',
      showAlert: false,
      dashboard: buildTelegramDashboard(report, {
        bannerNote: '🔓 ĐÃ MỞ KHÓA TOÀN BỘ 6 TÀI KHOẢN & XÓA COOLDOWN',
      }),
    };
  }

  if (data.startsWith('cd:')) {
    const minutes = Number(data.slice(3));
    if (Number.isFinite(minutes) && minutes >= 0 && minutes <= 1440) {
      updateAntiBanPolicy(stateDir, { claudeSwitchCooldownSec: Math.round(minutes * 60) });
    }
    const report = getStatusReport({ stateDir, nowMs });
    return {
      toastText: `🛡 Đã đặt thời gian nghỉ chống ban: ${minutes} phút`,
      showAlert: false,
      dashboard: buildTelegramDashboard(report, {
        bannerNote: `🛡 ĐÃ CẬP NHẬT COOLDOWN CHỐNG BAN: ${minutes} PHÚT`,
      }),
    };
  }

  // Mac dinh: act:refresh hoac callback bat ky -> lam moi bang dieu khien va % quota
  const report = getStatusReport({ stateDir, nowMs });
  return {
    toastText: '🔃 Đã cập nhật % Quota & trạng thái mới nhất!',
    showAlert: false,
    dashboard: buildTelegramDashboard(report),
  };
}

/**
 * Gui tin nhan thong bao ve dien thoai qua Telegram kem bang nut bam tuong tac.
 */
export async function sendTelegramNotification(text, opts = {}) {
  const cfg = loadTelegramConfig(opts.stateDir);
  if (!cfg.botToken || !cfg.chatId) {
    return { sent: false, reason: 'missing_token_or_chat_id' };
  }
  try {
    const report = getStatusReport({ stateDir: opts.stateDir });
    const dash = buildTelegramDashboard(report);
    await callTelegramApi(cfg.botToken, 'sendMessage', {
      chat_id: cfg.chatId,
      text,
      reply_markup: opts.reply_markup || dash.reply_markup,
    });
    return { sent: true };
  } catch (err) {
    logStructured('warn', 'telegram_notify_failed', { error: maskSecret(err?.message, [cfg.botToken]) });
    return { sent: false, reason: maskSecret(err?.message, [cfg.botToken]) };
  }
}

/**
 * Xu ly lenh van ban hoac nut bam Reply Keyboard nhan tu Telegram.
 */
export async function handleTelegramCommand(rawText, opts = {}) {
  const { stateDir, nowMs = Date.now() } = opts;
  const text = String(rawText || '').trim();

  await maybeSyncLiveQuotas(stateDir, nowMs, text === '/status' || text === '🎛 Bảng điều khiển');

  // Anh xa cac nut tren Reply Keyboard hoac so 1..6 thanh lenh tuong ung
  if (text === '🎛 Bảng điều khiển' || text === '/menu') {
    const report = getStatusReport({ stateDir, nowMs });
    return formatStatusForTelegram(report);
  }
  if (text === '🔄 Xoay vòng an toàn') {
    return handleTelegramCommand('/rotate', { stateDir, nowMs });
  }
  if (text === '🚨 Báo kịch 429 (Đổi ngay)') {
    return handleTelegramCommand('/limit', { stateDir, nowMs });
  }
  if (text === '🔓 Mở khóa 429 / Cooldown' || text === '/unfreeze') {
    resetLocks(stateDir);
    const report = getStatusReport({ stateDir, nowMs });
    return formatStatusForTelegram(report, {
      bannerNote: '🔓 ĐÃ MỞ KHÓA TOÀN BỘ 6 TÀI KHOẢN & XÓA COOLDOWN',
    });
  }
  if (/^[1-6]$/.test(text)) {
    return handleTelegramCommand(`/switch ${text}`, { stateDir, nowMs });
  }

  const [cmdRaw, ...args] = text.split(/\s+/);
  const cmd = cmdRaw.toLowerCase().split('@')[0];

  if (cmd === '/start' || cmd === '/help' || cmd === '/status') {
    const report = getStatusReport({ stateDir, nowMs });
    return formatStatusForTelegram(report);
  }

  if (cmd === '/switch') {
    const target = args[0];
    if (!target) {
      return '⚠️ Vui lòng chạm trực tiếp vào nút tài khoản bên dưới hoặc nhập /switch <1..6>.';
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
      return `⛔️ ${err.message}\n(Chạm nút trên bảng điều khiển để chọn Ép chuyển hoặc gõ "/switch ${target} --force")`;
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
      return '⚠️ Vui lòng chọn nút Cooldown bên dưới hoặc nhập số phút hợp lệ (0 - 1440).';
    }
    const policy = updateAntiBanPolicy(stateDir, {
      claudeSwitchCooldownSec: Math.round(minutes * 60),
    });
    return `🛡 Đã cập nhật thời gian nghỉ chống ban giữa các tài khoản Claude: ${minutes} phút (${policy.claudeSwitchCooldownSec}s).`;
  }

  // Bat ky tin nhan nao khac cung tra ve bang dieu khien de nguoi dung bam nut chon luon
  const report = getStatusReport({ stateDir, nowMs });
  return formatStatusForTelegram(report, {
    bannerNote: '💡 Chạm trực tiếp vào các nút bên dưới để chuyển tài khoản:',
  });
}
