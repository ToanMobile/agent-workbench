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
import { panelUrl } from './panel.js';

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
 * Bang dieu khien CC Switcher da chuyen khoi Telegram sang trang web Agent Office. Telegram chi con gui canh bao
 * (429, doi tai khoan) va nut duyet super-board; moi tin nhan/nut cu cua bang dieu khien chi nhan duoc link nay.
 */
export function panelMovedText() {
  return `🎛 Bảng điều khiển CC Switcher đã chuyển sang web: ${panelUrl()}\n(Mở trên chính máy Mac. Telegram chỉ còn gửi cảnh báo 429/đổi tài khoản và nút duyệt super-board.)`;
}

/** Bo ban phim ghim o day man hinh ma bang dieu khien cu da gan. */
export const REMOVE_REPLY_KEYBOARD = Object.freeze({ remove_keyboard: true });

/**
 * Don giao dien bang dieu khien cu tren Telegram: xoa danh sach lenh (/status, /menu, /rotate, /limit, /unfreeze)
 * va tra nut Menu ve mac dinh. Goi mot lan khi daemon khoi dong.
 */
export async function clearLegacyTelegramPanel(botToken, apiCaller = callTelegramApi) {
  if (!botToken) return false;
  try {
    await apiCaller(botToken, 'deleteMyCommands', {});
    await apiCaller(botToken, 'setChatMenuButton', { menu_button: { type: 'default' } });
    return true;
  } catch (err) {
    logStructured('warn', 'telegram_menu_cleanup_failed', { error: maskSecret(err?.message, [botToken]) });
    return false;
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
  const data = String(callbackQuery?.data || '').trim();
  if (data.startsWith('sb:ap:')) {
    return approveSuperBoardCallback(data.slice('sb:ap:'.length), opts);
  }
  // Nut cua bang dieu khien cu (sw:, fsw:, act:, cd:) con nam trong tin nhan cu: khong doi tai khoan, chi chi duong sang web
  // va go bo hang nut khoi tin nhan do.
  return {
    toastText: `Bảng điều khiển đã chuyển sang web: ${panelUrl()}`,
    showAlert: true,
    clearButtons: true,
  };
}

/**
 * Gui canh bao ve dien thoai qua Telegram (chi van ban, kem link bang dieu khien web; khong con ban phim bang dieu khien).
 */
export async function sendTelegramNotification(text, opts = {}) {
  const cfg = loadTelegramConfig(opts.stateDir);
  if (!cfg.botToken || !cfg.chatId) {
    return { sent: false, reason: 'missing_token_or_chat_id' };
  }
  try {
    const body = {
      chat_id: cfg.chatId,
      text: `${text}\n\n🎛 Chi tiết: ${panelUrl()}`,
    };
    if (opts.reply_markup) body.reply_markup = opts.reply_markup;
    await callTelegramApi(cfg.botToken, 'sendMessage', body);
    return { sent: true };
  } catch (err) {
    logStructured('warn', 'telegram_notify_failed', { error: maskSecret(err?.message, [cfg.botToken]) });
    return { sent: false, reason: maskSecret(err?.message, [cfg.botToken]) };
  }
}

/**
 * Tin nhan van ban gui toi bot (/status, /switch, /rotate, nut ban phim cu...): bang dieu khien da chuyen sang web,
 * nen moi tin nhan chi nhan lai link. Khong lenh nao doi tai khoan tu Telegram nua.
 */
export async function handleTelegramCommand() {
  return panelMovedText();
}
