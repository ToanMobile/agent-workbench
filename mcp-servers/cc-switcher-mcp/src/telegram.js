// Tich hop Telegram Bot 2 chieu: gui canh bao khi het quota/chuyen profile va nhan lenh dieu khien tu dien thoai.
import fs from 'node:fs';
import os from 'node:os';
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
  balanceRepoAccounts,
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

function formatCleanProfileHeader(p) {
  switch (p.id) {
    case 'finos':
      return '1. FinOS (toan.huynh@finos)';
    case 'finos_team':
      return '2. FinOS Team (linhnt@finos)';
    case 'max':
      return '3. Personal 5x Max (vetc)';
    case 'antigravity':
      return '4. Antigravity Ultra (Gemini 4)';
    case 'antigravity_pro':
      return '5. Antigravity Pro (Gemini 4)';
    case 'grok':
      return '6. Grok CLI (grok-4.7 xhigh)';
    default:
      return p.shortLabel || p.name;
  }
}

function compactButtonName(p) {
  switch (p.id) {
    case 'finos':
      return '1.FinOS';
    case 'finos_team':
      return '2.Team';
    case 'max':
      return '3.5xMax';
    case 'antigravity':
      return '4.AGY Ultra';
    case 'antigravity_pro':
      return '5.AGY Pro';
    case 'grok':
      return '6.Grok';
    default:
      return p.shortLabel || p.id;
  }
}

/**
 * Dinh dang bao cao trang thai gon dep, toi uu cho man hinh doc dien thoai (khong bi tran dong hay lap so).
 */
export function formatStatusForTelegram(report, opts = {}) {
  const { bannerNote = '' } = opts;
  const cdMin = Math.round((report.policy?.claudeSwitchCooldownSec ?? 900) / 60);
  const cooldownBadge =
    report.claudeCooldownRemainSec > 0
      ? `⏳ Chờ ${formatDurationHuman(report.claudeCooldownRemainSec)}`
      : `🟢 Đổi ngay (0s) · Nghỉ ${cdMin}p`;

  const lines = [];
  if (bannerNote) {
    lines.push(bannerNote);
    lines.push('────────────────────────');
  }

  const claudeProfiles = report.profiles.filter((p) => p.vendor === 'anthropic');
  const backupProfiles = report.profiles.filter((p) => p.vendor !== 'anthropic');
  const parallelClaude = claudeProfiles.filter((p) => p.isParallelActive && (p.assignedRepoCount || 0) > 0);

  let activeHeaderLine;
  if (parallelClaude.length >= 2 && report.activeProfile.vendor === 'anthropic') {
    const parts = parallelClaude.map((p) => `${p.shortLabel || p.id} (${p.assignedRepoCount} repo · ${p.remainingPct}%)`);
    activeHeaderLine = `▶️ Đang chạy song song: ${parts.join(' + ')}`;
  } else {
    const activePct = report.activeProfile.remainingPct ?? 100;
    const activeReset = report.activeProfile.resetTimeFormatted
      ? ` · ⏰ ${report.activeProfile.resetTimeFormatted}`
      : '';
    const activeTitle = report.activeProfile.shortLabel || report.activeProfile.name;
    activeHeaderLine = `▶️ Đang dùng: ${activeTitle} (Còn ${activePct}%${activeReset})`;
  }

  lines.push('🎛 CC SWITCHER · BẢNG ĐIỀU KHIỂN');
  lines.push(activeHeaderLine);
  lines.push(`🛡 Anti-Ban: Khóa nhảy chéo Claude · ${cooldownBadge}`);
  lines.push('🔄 Hết limit tự xoay: Grok CLI ➔ AGY Ultra ➔ AGY Pro');
  lines.push(`💰 Chi phí: $${report.usage.totalCostUsd} (${report.usage.totalRequests} req)`);
  lines.push('');
  lines.push('🔋 QUOTA 3 TÀI KHOẢN CLAUDE (5 GIỜ · CÁCH LY REPO)');

  for (const p of claudeProfiles) {
    const pct = p.remainingPct ?? (p.isFrozen ? 0 : 100);
    const used = p.usedPct ?? (100 - pct);
    const bar = renderProgressBar(pct);
    const title = formatCleanProfileHeader(p);
    const isRunning = Boolean(p.isParallelActive ?? p.isActive);

    if (p.isFrozen || pct <= 0) {
      const unlockStr = p.resetTimeFormatted
        ? `Mở ${p.resetTimeFormatted} (${p.resetRemainHuman || `${p.freezeRemainMin}p`})`
        : `Mở sau ${p.freezeRemainMin}p`;
      lines.push(`🔴 ${title}${p.isActive ? ' ⚠️' : ''}`);
      lines.push(`   ${bar} 0% · ⏰ ${unlockStr}`);
    } else {
      const icon = isRunning ? '🟢' : '⚪️';
      const repoBadge = p.assignedRepoCount > 0 ? ` · ${p.assignedRepoCount} repo ✓` : (isRunning ? ' ✓' : '');
      const resetNote = p.resetTimeFormatted
        ? ` · ⏰ ${p.resetTimeFormatted} (${p.resetRemainHuman})`
        : ` · Dùng ${used}%`;
      lines.push(`${icon} ${title}${repoBadge}`);
      lines.push(`   ${bar} Còn ${pct}%${resetNote}`);
    }
  }

  if (backupProfiles.length > 0) {
    const orderedBackups = ['grok', 'antigravity', 'antigravity_pro']
      .map((id) => backupProfiles.find((p) => p.id === id))
      .filter(Boolean);
    lines.push('');
    lines.push('🚀 DỰ PHÒNG KHÁC HÃNG (TỰ XOAY 0S · KHÔNG LO BAN)');
    orderedBackups.forEach((p, idx) => {
      const icon = p.isFrozen ? '🔴' : p.isActive ? '🟢' : '⚪️';
      const mark = p.isActive ? ' — ĐANG DÙNG ✓' : '';
      lines.push(`${icon} Ưu tiên ${idx + 1} · ${formatCleanProfileHeader(p)}${mark}`);
    });
  }

  if (Array.isArray(report.repoAssignments) && report.repoAssignments.length > 0) {
    const finosRepos = report.repoAssignments.filter((r) => r.account === 'finos').map((r) => r.name);
    const teamRepos = report.repoAssignments.filter((r) => r.account === 'finos_team').map((r) => r.name);
    lines.push('');
    lines.push(`📂 PHÂN BỔ 6 REPO (${finosRepos.length} FinOS · ${teamRepos.length} Team · Khóa nhảy chéo)`);
    lines.push('🔹 1. FinOS (Hết ➔ Grok ➔ AGY):');
    for (const name of finosRepos) {
      lines.push(`   • ${name}`);
    }
    lines.push('🔸 2. FinOS Team (Hết ➔ Grok ➔ AGY):');
    for (const name of teamRepos) {
      lines.push(`   • ${name}`);
    }
  }

  lines.push('');
  lines.push('👇 Chạm nút bên dưới để đổi tài khoản:');
  return lines.join('\n');
}

/**
 * Xay dung Bang dieu khien tuong tac voi nhan nut sieu gon (<= 24 ky tu) khong bi cat '...' tren dien thoai.
 */
export function buildTelegramDashboard(report, opts = {}) {
  const { bannerNote = '', forcePromptTargetId = '' } = opts;
  const text = formatStatusForTelegram(report, { bannerNote });

  const inlineKeyboard = [];

  if (forcePromptTargetId) {
    const targetProf = report.profiles.find((p) => p.id === forcePromptTargetId);
    const shortName = targetProf?.shortLabel || forcePromptTargetId;
    inlineKeyboard.push([
      {
        text: `⚡ ÉP CHUYỂN sang ${shortName}`,
        callback_data: `fsw:${forcePromptTargetId}`,
      },
    ]);
  }

  // Sap xep 3 hang x 2 cot theo dung luong thuc te:
  // Hang 1: 1.FinOS | 2.Team (Cap tai khoan chinh chay song song 3/3 repo)
  // Hang 2: 6.Grok  | 4.AGY Ultra (Du phong tu dong #1 va #2)
  // Hang 3: 5.AGY Pro | 3.5xMax (Du phong tu dong #3 va Claude Max thu cong)
  const buttonOrderIds = ['finos', 'finos_team', 'grok', 'antigravity', 'antigravity_pro', 'max'];
  const orderedProfiles = buttonOrderIds
    .map((id) => report.profiles.find((p) => p.id === id))
    .filter(Boolean);

  for (let i = 0; i < orderedProfiles.length; i += 2) {
    const row = orderedProfiles.slice(i, i + 2).map((p) => {
      const shortName = compactButtonName(p);
      const pct = p.remainingPct ?? (p.isFrozen ? 0 : 100);
      const isRunning = Boolean(p.isParallelActive ?? p.isActive);
      let btnText = `⚪️ ${shortName} · ${pct}%`;

      if (p.isFrozen || pct <= 0) {
        const unlockClock = p.resetTimeFormatted || `${p.freezeRemainMin}p`;
        btnText = `🔴 ${shortName} · 0% (${unlockClock})`;
      } else if (isRunning) {
        btnText = `🟢 ${shortName} · ${pct}% ✓`;
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
    { text: '🔄 Đổi kế tiếp', callback_data: 'act:rotate' },
    { text: '🚨 Báo kịch 429', callback_data: 'act:limit' },
  ]);

  // Hang can bang 6 Repo: Chia deu 3/3 hoac Dao nhom 3/3
  inlineKeyboard.push([
    { text: '⚖️ Chia đều 3/3', callback_data: 'act:balance_repos' },
    { text: '🔀 Đảo nhóm 3/3', callback_data: 'act:swap_repos' },
  ]);

  // Hang mo khoa dong bang & lam moi % Quota
  inlineKeyboard.push([
    { text: '🔓 Mở khóa 429', callback_data: 'act:unfreeze_all' },
    { text: '🔃 Làm mới Quota', callback_data: 'act:refresh' },
  ]);

  // Hang chon nhanh muc Cooldown chong ban (15p / 5p / 0p)
  const currentCdMin = Math.round((report.policy?.claudeSwitchCooldownSec ?? 900) / 60);
  inlineKeyboard.push([
    { text: `${currentCdMin === 15 ? '✅' : '🛡'} Nghỉ 15p`, callback_data: 'cd:15' },
    { text: `${currentCdMin === 5 ? '✅' : '🛡'} Nghỉ 5p`, callback_data: 'cd:5' },
    { text: `${currentCdMin === 0 ? '✅' : '🛡'} Tắt (0p)`, callback_data: 'cd:0' },
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
export function superBoardApprovalsDir(override) {
  if (override) return override;
  return path.join(os.homedir(), '.claude', 'super-board', 'approvals');
}

// Nút chỉ ghi `done` khi validate() của super-board-approval.py sẽ đọc đúng `done` đó cho đúng PR này, nên chọn nguồn theo
// cùng luật: block tin cậy MỚI NHẤT (`approval-request:` hoặc `Reason tag: …🙋`) trên mọi nguồn của PR, người đăng có quyền
// write/maintain/admin (collaborators/{login}/permission, không phải author_association), request chưa sửa, đủ trường như
// parse_request. Issue có thể chung nhiều PR và thân PR (`closes #N`) do tác giả sửa: chọn request khớp ĐẦU TIÊN thì `done`
// duyệt hộ block mới nhất của PR khác (probe validate(): #9 có request cho 164 rồi cho 20, `done` lên #9 ⇒ PR 20 duyệt).
const REQUEST_PREFIX = 'approval-request: ';
// `(?:^|\n)` thay cờ `m` để khớp đúng tập đầu dòng của BLOCK (re.M) trong super-board-approval.py. Đo 25/10: Python re.M
// khớp sau \n, trượt sau \r và U+2028; JS có `m` khớp cả ba; mẫu này khớp đầu body và sau \n, trượt sau \r và U+2028.
const APPROVAL_BLOCK = /Reason tag:[^\n]*🙋|(?:^|\n)approval-request:/u;
const WRITE_PERMISSIONS = new Set(['write', 'maintain', 'admin']);

// Như parse_request của approval.py: đúng một dòng request, JSON đủ repo/pr/head/scope hợp lệ; không thì null.
function parseApprovalRequest(body) {
  const lines = body.split(/\r\n|[\n\r\v\f\x1c-\x1e\x85\u2028\u2029]/).filter((line) => line.startsWith(REQUEST_PREFIX));
  if (lines.length !== 1) return null;
  let value;
  // parse_request đòi `type(pr) is int`: json.loads đọc `20.0`/`2e1` thành float và từ chối, JSON.parse thì ra 20. Giữ văn bản
  // gốc của `pr` (đối số thứ ba của reviver, Node >= 21) để từ chối như gate; Node 20 không có thì như trước (gate vẫn từ chối).
  const prSources = [];
  try {
    value = JSON.parse(lines[0].slice(REQUEST_PREFIX.length), function reviver(key, v, context) {
      if (key === 'pr') prSources.push([this, context?.source]);
      return v;
    });
  } catch {
    return null; // JSON hỏng: gate cũng coi là request không khớp
  }
  const prSource = prSources.find(([holder]) => holder === value)?.[1];
  const ok = value && typeof value === 'object' && !Array.isArray(value)
    && typeof value.repo === 'string' && /^[^/\s]+\/[^/\s]+$/.test(value.repo)
    && Number.isInteger(value.pr) && value.pr >= 1 && (prSource === undefined || /^\d+$/.test(prSource))
    && typeof value.head === 'string' && /^[0-9a-f]{40}$/.test(value.head)
    && typeof value.scope === 'string' && /^[0-9a-f]{64}$/.test(value.scope);
  return ok ? value : null;
}

// Thời điểm comment phải có múi giờ (như timestamp() của approval.py); sai thì ném, người gọi từ chối.
function commentTime(value) {
  const t = typeof value === 'string' && /(?:Z|[+-]\d\d:\d\d)$/.test(value) ? Date.parse(value) : NaN;
  if (Number.isNaN(t)) throw new Error('comment timestamp missing or lacks timezone');
  return t;
}

// { source } khi gate sẽ nhận `done` ghi lên source cho đúng phiếu; ngược lại { why } để báo người bấm.
async function approvalSource(comments, record, permission) {
  const head7 = record.head.slice(0, 7);
  const blocks = (comments || []).filter((c) => APPROVAL_BLOCK.test(String(c?.body || '')));
  if (blocks.some((c) => !c?.user?.login || !['User', 'Bot'].includes(c.user.type))) {
    return { why: 'Không xác minh được người đăng yêu cầu duyệt.' };
  }
  const perms = await Promise.all(blocks.map((c) => permission(c.user.login)));
  const trusted = blocks.filter((_, i) => WRITE_PERMISSIONS.has(perms[i]));
  if (!trusted.length) {
    return { why: `Chưa có approval-request cho head ${head7} của người có quyền ghi: đăng request trên issue liên kết hoặc PR rồi bấm lại.` };
  }
  const times = trusted.map((c) => commentTime(c.created_at));
  const latestTime = Math.max(...times);
  const latest = trusted.filter((_, i) => times[i] === latestTime);
  if (latest.length !== 1) return { why: 'Hai yêu cầu duyệt mới nhất trùng thời điểm: đăng request mới rồi bấm lại.' };
  const req = latest[0];
  const value = parseApprovalRequest(String(req.body || ''));
  if (!value || value.repo !== record.repo.toLowerCase() || value.pr !== Number(record.pr) || value.head !== record.head) {
    return { why: `Yêu cầu duyệt mới nhất không phải cho PR #${record.pr} head ${head7}: đăng request mới rồi bấm lại.` };
  }
  if (commentTime(req.updated_at) !== latestTime) return { why: 'Request đã bị sửa: đăng request mới rồi bấm lại.' };
  const source = Number(req.source);
  if (!Number.isInteger(source) || source < 1 || !req.id) return { why: 'Request thiếu nguồn hoặc id.' };
  return { source };
}

// Quyền hiện tại của login trên repo (một lời gọi gh mỗi login). Login lạ: null (không tin), như GitHub.permission().
function permissionLookup(repo, ghRead) {
  const cache = new Map();
  return (login) => {
    if (!/^[A-Za-z0-9_-]+(?:\[bot\])?$/.test(login)) return Promise.resolve(null);
    if (!cache.has(login)) {
      cache.set(login, ghRead(['api', `repos/${repo}/collaborators/${login}/permission`])
        .then((out) => JSON.parse(out || '{}').permission ?? null));
    }
    return cache.get(login);
  };
}

async function defaultGhRead(args) {
  const { execFile } = await import('node:child_process');
  const { promisify } = await import('node:util');
  const { stdout } = await promisify(execFile)('gh', args, { timeout: 15000 });
  return stdout;
}

// Như CLOSES/body_links của super-board-approval.py: `KEYWORD[:] #N` hoặc `KEYWORD[:] owner/repo#N` cùng repo (không phân biệt hoa/thường).
// Python re theo Unicode: ranh giới từ là chữ/số Unicode (`écloses #9`, `#9é` không liên kết), `\s` không gồm U+FEFF, `ſ` gập thành `s`.
// JS `\b`/`\s` thì khác, nên viết tường minh; JS chỉ được liên kết ít hơn Python (`\d` ASCII), không bao giờ nhiều hơn.
const SAME_REPO_CLOSES = /(?<![\p{L}\p{N}_])(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?[^\S\uFEFF]+([\w.-]+\/[\w.-]+)?#(\d+)(?![\p{L}\p{N}_])/giu;

// Head hien tai cua PR va cac issue no dong (request chinh tac nam tren issue, block-template.md).
async function readPrState(record, ghRead) {
  const out = await ghRead(['pr', 'view', String(record.pr), '--repo', record.repo, '--json', 'headRefOid,state,body,closingIssuesReferences']);
  const pr = JSON.parse(out || '{}');
  const repo = String(record.repo).toLowerCase();
  const issues = new Set();
  for (const ref of pr.closingIssuesReferences || []) {
    if (String(ref?.repository?.nameWithOwner || '').toLowerCase() === repo) issues.add(Number(ref.number));
  }
  for (const m of String(pr.body || '').matchAll(SAME_REPO_CLOSES)) {
    if (!m[1] || m[1].toLowerCase() === repo) issues.add(Number(m[2]));
  }
  return { head: String(pr.headRefOid || ''), state: String(pr.state || ''), issues: [...issues].filter((n) => n > 0) };
}

async function readApprovalComments(record, issues, ghRead) {
  // Đúng tập nguồn GitHub.check() của gate đọc (issue liên kết | {PR}); record.source không nằm trong đó thì `done` ở đó vô hiệu.
  const sources = [...new Set([record.pr, ...issues].filter((n) => Number(n) > 0))];
  // Đọc song song (mỗi lời gọi gh vẫn timeout 15 s): đọc tuần tự N nguồn cộng dồn N×15 s trước khi trả lời callback.
  // Promise.all giữ thứ tự nguồn, nên thứ tự chọn request không đổi.
  const outs = await Promise.all(sources.map((source) => ghRead(['api', '--paginate', '--slurp', `repos/${record.repo}/issues/${source}/comments?per_page=100`])));
  const all = [];
  sources.forEach((source, i) => {
    for (const page of JSON.parse(outs[i] || '[]')) {
      for (const comment of Array.isArray(page) ? page : []) all.push({ ...comment, source: Number(source) });
    }
  });
  return all;
}

async function defaultGh(args) {
  const { execFile } = await import('node:child_process');
  const { promisify } = await import('node:util');
  await promisify(execFile)('gh', args, { timeout: 15000 });
}

/**
 * Nut sb:ap:<16 hex> khong phai uy quyen. Chi comment dung `done` tren dung source
 * dang giu approval-request cua head do. Khong merge.
 */
export async function approveSuperBoardCallback(token, opts = {}) {
  const id = String(token || '').trim();
  if (!/^[0-9a-f]{16}$/.test(id)) {
    return { toastText: 'Nút duyệt không hợp lệ.', showAlert: true };
  }
  const file = path.join(superBoardApprovalsDir(opts.approvalsDir), `${id}.json`);
  let record;
  try {
    record = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return { toastText: 'Không thấy phiếu duyệt.', showAlert: true };
  }
  const head = String(record.head || '');
  const repo = String(record.repo || '');
  if (!/^[0-9a-f]{40}$/.test(head) || !/^[^/\s]+\/[^/\s]+$/.test(repo)) {
    return { toastText: 'Phiếu duyệt thiếu head hoặc repo.', showAlert: true };
  }
  const ghRead = opts.ghRead || defaultGhRead;
  const gh = opts.gh || defaultGh;
  let picked;
  try {
    const pr = await readPrState(record, ghRead);
    if (!/^[0-9a-f]{40}$/.test(pr.head)) throw new Error('unreadable head');
    // Gate (approval.py GitHub.pr) không duyệt PR đã đóng/merge: `done` lúc đó chỉ còn duyệt hộ PR khác chung issue.
    if (pr.state !== 'OPEN') {
      return { toastText: `PR #${record.pr} không còn mở (${pr.state || 'không rõ trạng thái'}): không ghi done.`, showAlert: true };
    }
    if (pr.head !== head) {
      return {
        toastText: `Head đã đổi (${head.slice(0, 7)} → ${pr.head.slice(0, 7)}). Dùng tin mới nhất của PR này.`,
        showAlert: true,
      };
    }
    const comments = opts.readComments ? await opts.readComments(record) : await readApprovalComments(record, pr.issues, ghRead);
    picked = await approvalSource(comments, { ...record, repo, head }, permissionLookup(repo, ghRead));
  } catch (err) {
    // Toast giữ chung cho người bấm; nguyên nhân thật (gh thiếu, timeout 15 s, JSON/thời điểm hỏng) ghi log để khoanh vùng.
    logStructured('warn', 'sb_approve_read_failed', { repo, pr: record.pr, error: err?.killed ? 'gh timeout (15 s)' : err?.message });
    return { toastText: 'Không đọc được approval-request.', showAlert: true };
  }
  if (!picked.source) return { toastText: picked.why, showAlert: true };
  const source = picked.source;
  try {
    await gh(['api', '--method', 'POST', `repos/${repo}/issues/${source}/comments`, '-f', 'body=done']);
  } catch {
    return { toastText: 'Không ghi được comment done.', showAlert: true };
  }
  return { toastText: 'Đã ghi done trên đúng nguồn duyệt.', showAlert: false };
}

/** Chat lạ: trả lời từ chối, không comment, không gán chatId. */
export async function refuseForeignTelegramChat(apiCaller, botToken, callbackQuery) {
  await apiCaller(botToken, 'answerCallbackQuery', {
    callback_query_id: callbackQuery?.id,
    text: 'Chat này không được phép duyệt.',
    show_alert: true,
  });
  return { refused: true };
}
export async function handleTelegramCallback(callbackQuery, opts = {}) {
  const { stateDir, nowMs = Date.now(), repos } = opts;
  const data = String(callbackQuery?.data || '').trim();

  if (data.startsWith('sb:ap:')) {
    return approveSuperBoardCallback(data.slice('sb:ap:'.length), opts);
  }
  await maybeSyncLiveQuotas(stateDir, nowMs, data === 'act:refresh');

  if (data === 'act:balance_repos' || data === 'act:swap_repos') {
    const mode = data === 'act:swap_repos' ? 'swap' : 'even';
    balanceRepoAccounts({ repos, mode });
    const report = getStatusReport({ stateDir, nowMs, repos });
    const bannerNote = mode === 'swap'
      ? '🔀 ĐÃ ĐẢO NHÓM 3/3 REPO GIỮA FINOS ↔ FINOS TEAM'
      : '⚖️ ĐÃ CHIA ĐỀU 6 REPO (3 FINOS · 3 FINOS TEAM)';
    return {
      toastText: mode === 'swap'
        ? '🔀 Đã đảo nhóm 3/3 Repo giữa FinOS & FinOS Team!'
        : '⚖️ Đã chia đều 3 Repo FinOS & 3 Repo FinOS Team!',
      showAlert: false,
      dashboard: buildTelegramDashboard(report, { bannerNote }),
    };
  }

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
      const report = getStatusReport({ stateDir, nowMs, repos });
      const bannerNote = `✅ ĐÃ CHUYỂN SANG: ${res.activeProfile.name}`;
      return {
        toastText: `✅ Đã chuyển sang ${res.activeProfile.shortLabel || res.activeProfile.name}`,
        showAlert: false,
        dashboard: buildTelegramDashboard(report, { bannerNote }),
      };
    } catch (err) {
      const report = getStatusReport({ stateDir, nowMs, repos });
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
    const report = getStatusReport({ stateDir, nowMs, repos });
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
    const report = getStatusReport({ stateDir, nowMs, repos });
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
    const report = getStatusReport({ stateDir, nowMs, repos });
    return {
      toastText: `🛡 Đã đặt thời gian nghỉ chống ban: ${minutes} phút`,
      showAlert: false,
      dashboard: buildTelegramDashboard(report, {
        bannerNote: `🛡 ĐÃ CẬP NHẬT COOLDOWN CHỐNG BAN: ${minutes} PHÚT`,
      }),
    };
  }

  // Mac dinh: act:refresh hoac callback bat ky -> lam moi bang dieu khien va % quota
  const report = getStatusReport({ stateDir, nowMs, repos });
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
