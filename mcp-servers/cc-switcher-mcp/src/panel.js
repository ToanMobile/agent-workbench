// Du lieu va thao tac cho bang dieu khien CC Switcher tren web (Agent Office: http://ai-factory.localhost:4317/cc-switcher).
// Bang dieu khien da chuyen khoi Telegram: moi thao tac dung lai logic cua profiles.js, khong nhan ban.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { AppError, resolveStateDir, logStructured } from './errors.js';
import {
  DEFAULT_PROFILES,
  loadSwitcherState,
  getStatusReport,
  switchProfile,
  rotateNextProfile,
  resetLocks,
  updateAntiBanPolicy,
  balanceRepoAccounts,
  syncLiveQuotas,
  setRepoAccount,
  addRepo,
  removeRepo,
} from './profiles.js';

export const DEFAULT_PANEL_URL = 'http://ai-factory.localhost:4317/cc-switcher';
export const BACKUP_ORDER = ['grok', 'antigravity', 'antigravity_pro'];
export const PANEL_ACTIONS = [
  'refresh', 'switch', 'rotate', 'limit', 'unfreeze', 'balance', 'cooldown', 'repo_assign', 'repo_add', 'repo_remove',
];
const BALANCE_MODES = new Set(['even', 'swap']);

/** Link bang dieu khien web (ghi de bang CC_SWITCHER_PANEL_URL). */
export function panelUrl() {
  return process.env.CC_SWITCHER_PANEL_URL || DEFAULT_PANEL_URL;
}

function isDefaultStateDir(stateDir) {
  return resolveStateDir(stateDir) === resolveStateDir();
}

// Chi dong bo quota live (Keychain + Anthropic) voi thu muc trang thai that, giong Telegram truoc day: test dung thu muc tam.
async function maybeSync(stateDir, nowMs, force, quotaFetcher) {
  if (quotaFetcher) return syncLiveQuotas({ stateDir, nowMs, forceRefresh: force, quotaFetcher });
  if (isDefaultStateDir(stateDir)) return syncLiveQuotas({ stateDir, nowMs, forceRefresh: force });
  return null;
}

function fileInfo(file) {
  try {
    const st = fs.statSync(file);
    return { exists: true, mtimeMs: Math.round(st.mtimeMs) };
  } catch {
    return { exists: false, mtimeMs: 0 };
  }
}

function daemonHealth(probe) {
  if (typeof probe === 'function') return probe();
  try {
    const out = execFileSync('pgrep', ['-f', 'cc-switcher-mcp.js --daemon'], {
      encoding: 'utf8',
      timeout: 2000,
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    const pids = out.split(/\s+/).filter((x) => /^\d+$/.test(x)).map(Number);
    return { running: pids.length > 0, pids };
  } catch {
    return { running: false, pids: [] };
  }
}

// Chi bao "da cau hinh hay chua": token va chat id khong bao gio ra khoi may qua API nay.
function telegramHealth(stateDir) {
  const file = path.join(resolveStateDir(stateDir), 'telegram.env');
  let hasToken = Boolean(process.env.TELEGRAM_BOT_TOKEN);
  let hasChat = Boolean(process.env.TELEGRAM_CHAT_ID);
  try {
    for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
      const m = /^\s*(TELEGRAM_BOT_TOKEN|TELEGRAM_CHAT_ID)\s*=\s*(\S+)/.exec(line);
      if (m && m[1] === 'TELEGRAM_BOT_TOKEN') hasToken = true;
      if (m && m[1] === 'TELEGRAM_CHAT_ID') hasChat = true;
    }
  } catch {
    // khong co file: chua cau hinh
  }
  return { configured: hasToken, chatBound: hasChat, alertsOnly: true };
}

function profileView(p, state, nowMs) {
  const q = state.quotaCache?.[p.id] || null;
  const frozenUntilMs = state.frozenUntil?.[p.id] || 0;
  return {
    id: p.id,
    index: p.index,
    shortLabel: p.shortLabel,
    name: p.name,
    vendor: p.vendor,
    appType: p.appType,
    isActive: p.isActive,
    isParallelActive: p.isParallelActive,
    assignedRepoCount: p.assignedRepoCount,
    status: p.status,
    isFrozen: p.isFrozen,
    freezeRemainMin: p.freezeRemainMin,
    frozenUntilMs: frozenUntilMs > nowMs ? frozenUntilMs : 0,
    remainingPct: p.remainingPct,
    usedPct: p.usedPct,
    weeklyRemainingPct: p.weeklyRemainingPct,
    resetAtMs: p.resetAtMs,
    resetTimeFormatted: p.resetTimeFormatted,
    resetRemainHuman: p.resetRemainHuman,
    quota: q
      ? { source: q.source || '', updatedAtMs: q.updatedAtMs || 0, live: q.source === 'anthropic_oauth' }
      : { source: '', updatedAtMs: 0, live: false },
    backupPriority: BACKUP_ORDER.indexOf(p.id) + 1 || 0,
  };
}

/**
 * Trang thai day du cho trang web: 6 tai khoan (quota 5h/7 ngay, gio reset, dong bang), cooldown chong ban,
 * chi phi, phan bo repo, lich su chuyen va suc khoe he thong. Khong chua token/chat id/duong dan config.
 */
export async function buildPanelState(opts = {}) {
  const { stateDir, nowMs = Date.now(), repos, sync = true, forceRefresh = false, quotaFetcher, daemonProbe, claudeHomes } = opts;
  let syncError = '';
  if (sync) {
    try {
      await maybeSync(stateDir, nowMs, forceRefresh, quotaFetcher);
    } catch (err) {
      syncError = String(err?.message || err);
      logStructured('warn', 'panel_quota_sync_failed', { error: syncError });
    }
  }
  const report = getStatusReport({ stateDir, nowMs, repos });
  const state = loadSwitcherState(stateDir);
  const dir = resolveStateDir(stateDir);
  const profiles = report.profiles.map((p) => profileView(p, state, nowMs));
  const cooldownSec = report.policy?.claudeSwitchCooldownSec ?? 900;
  return {
    ok: true,
    generatedAtMs: nowMs,
    panelUrl: panelUrl(),
    activeProfileId: report.activeProfileId,
    activeProfile: profiles.find((p) => p.isActive) || profiles[0],
    profiles,
    backupOrder: BACKUP_ORDER,
    antiBan: {
      claudeCooldownRemainSec: report.claudeCooldownRemainSec,
      claudeSwitchCooldownSec: cooldownSec,
      cooldownMinutes: Math.round(cooldownSec / 60),
      rateLimitFreezeSec: report.policy?.rateLimitFreezeSec ?? 18000,
      preferCrossVendorOnCooldown: Boolean(report.policy?.preferCrossVendorOnCooldown),
      lastClaudeSwitchAtMs: state.lastClaudeSwitchAtMs || 0,
      lastClaudeRateLimitAtMs: state.lastClaudeRateLimitAtMs || 0,
    },
    usage: report.usage,
    repoAssignments: repoRows(report, profiles, claudeHomes),
    claudeAccounts: profiles.filter((p) => p.vendor === 'anthropic').map((p) => p.id),
    history: state.switchHistory.slice().reverse(),
    health: {
      quotaFetchedAtMs: state.quotaFetchedAtMs || 0,
      quotaSyncError: syncError,
      stateFile: fileInfo(path.join(dir, 'switcher-state.json')),
      ccSwitchDb: fileInfo(path.join(dir, 'cc-switch.db')),
      daemon: daemonHealth(daemonProbe),
      telegram: telegramHealth(stateDir),
    },
  };
}

// ---- Repo <-> tai khoan -------------------------------------------------------------------------------------

/** Ten thu muc du an cua Claude Code trong <configDir>/projects: moi ky tu khong phai chu/so thanh '-'. */
export function claudeProjectKey(absPath) {
  return String(absPath).replace(/[^a-zA-Z0-9]/g, '-');
}

/** Duong dan cac git worktree cua repo (doc file gitdir trong .git/worktrees, khong goi git). */
export function listGitWorktrees(repoPath) {
  const dir = path.join(repoPath, '.git', 'worktrees');
  let names = [];
  try { names = fs.readdirSync(dir); } catch { return []; }
  const out = [];
  for (const n of names) {
    try {
      const gitdir = fs.readFileSync(path.join(dir, n, 'gitdir'), 'utf8').trim();
      if (gitdir) out.push(path.dirname(gitdir));
    } catch { /* worktree hong: bo qua */ }
  }
  return out.sort();
}

function claudeHomesDefault() {
  return Object.fromEntries(DEFAULT_PROFILES.filter((p) => p.vendor === 'anthropic').map((p) => [p.id, p.configDir]));
}

/**
 * Lan cuoi repo duoc Claude Code dung (mtime file phien *.jsonl moi nhat) va tai khoan nao, tinh ca worktree
 * (<repo>/.claude/worktrees/* va git worktree). Chi doc mtime, khong doc noi dung phien.
 */
export function repoLastUsed(repoPath, worktrees = [], claudeHomes = claudeHomesDefault()) {
  const keys = [repoPath, ...worktrees].map(claudeProjectKey);
  const ownWt = `${claudeProjectKey(repoPath)}--claude-worktrees-`;
  let best = { atMs: 0, account: '' };
  for (const [account, home] of Object.entries(claudeHomes)) {
    const projects = path.join(home, 'projects');
    let dirs = [];
    try { dirs = fs.readdirSync(projects); } catch { continue; }
    for (const d of dirs) {
      if (!keys.includes(d) && !d.startsWith(ownWt)) continue;
      let files = [];
      try { files = fs.readdirSync(path.join(projects, d)); } catch { continue; }
      for (const f of files) {
        if (!f.endsWith('.jsonl')) continue;
        try {
          const m = fs.statSync(path.join(projects, d, f)).mtimeMs;
          if (m > best.atMs) best = { atMs: Math.round(m), account };
        } catch { /* file vua bi xoa */ }
      }
    }
  }
  return best;
}

/**
 * Tai khoan repo dang dung THUC TE luc nay, theo dung luat cua ham claude() trong ~/.zshrc + chong ban:
 * - chua ghim account -> lenh claude dung ~/.claude mac dinh;
 * - tai khoan Claude duoc gan dang 429/het quota -> KHONG nhay cheo Claude, Super-Board xoay khac hang Grok -> AGY Ultra -> AGY Pro.
 */
export function effectiveRepoAccount(row, profilesById) {
  if (!row.pathExists) return { kind: 'missing', account: '', note: 'Không thấy thư mục repo trên máy.' };
  if (!row.pinnedInFile) {
    return { kind: 'unpinned', account: '', note: 'Chưa ghim "account" trong .claude/settings.local.json: lệnh claude dùng ~/.claude mặc định.' };
  }
  const p = profilesById[row.account];
  if (!p) return { kind: 'unknown', account: '', note: `"${row.account}" không phải tài khoản cc-switcher biết.` };
  if (!p.isFrozen) return { kind: 'assigned', account: p.id, note: '' };
  const until = p.resetTimeFormatted ? ` tới ${p.resetTimeFormatted}` : '';
  const fb = BACKUP_ORDER.map((id) => profilesById[id]).find((b) => b && !b.isFrozen);
  if (!fb) {
    return { kind: 'blocked', account: '', note: `${p.shortLabel || p.name} chạm 429/hết quota${until}; cả 3 dự phòng khác hãng cũng đang khóa.` };
  }
  return {
    kind: 'fallback',
    account: fb.id,
    note: `${p.shortLabel || p.name} chạm 429/hết quota${until} → không nhảy chéo Claude, Super-Board xoay sang ${fb.shortLabel || fb.name}.`,
  };
}

function groupLabel(row, profilesById) {
  if (row.source === 'custom') return 'Tự thêm';
  const p = profilesById[row.defaultAccount];
  return p ? `Nhóm ${p.shortLabel || p.name}` : 'Mặc định';
}

function repoRows(report, profiles, claudeHomes) {
  const byId = Object.fromEntries(profiles.map((p) => [p.id, p]));
  return report.repoAssignments.map((r) => {
    const worktrees = r.pathExists ? listGitWorktrees(r.path) : [];
    const last = r.pathExists ? repoLastUsed(r.path, worktrees, claudeHomes) : { atMs: 0, account: '' };
    const eff = effectiveRepoAccount(r, byId);
    return {
      name: r.name,
      path: r.path,
      account: r.account,
      pinnedInFile: r.pinnedInFile,
      settingsExists: r.exists,
      pathExists: r.pathExists,
      source: r.source,
      group: groupLabel(r, byId),
      effective: eff,
      differs: eff.kind !== 'assigned',
      worktrees,
      lastUsedAtMs: last.atMs,
      lastUsedAccount: last.account,
    };
  });
}

function badInput(message) {
  return new AppError('INVALID_INPUT', message);
}

/**
 * Thuc hien mot thao tac tu trang web. Tra ve { ok, message, ...extra }; loi nghiep vu (cooldown, dong bang) tra ok:false
 * kem needsForce de trang hoi "Ep chuyen" ro rang, khong nem ra ngoai.
 */
export async function runPanelAction(action, params = {}, opts = {}) {
  const { stateDir, nowMs = Date.now(), repos, quotaFetcher } = opts;
  if (!PANEL_ACTIONS.includes(action)) throw badInput(`Thao tác không hợp lệ: ${action}`);

  if (action === 'refresh') {
    await maybeSync(stateDir, nowMs, true, quotaFetcher);
    return { ok: true, message: 'Đã cập nhật quota và trạng thái mới nhất.' };
  }

  if (action === 'switch') {
    const target = String(params.target ?? '').trim();
    if (!DEFAULT_PROFILES.some((p) => p.id === target)) throw badInput('Chọn một tài khoản hợp lệ.');
    const force = params.force === true;
    try {
      const res = switchProfile({
        stateDir,
        target,
        nowMs,
        enforceCooldown: !force,
        reason: force ? 'web_ui_force_switch' : 'web_ui_switch',
      });
      return {
        ok: true,
        message: `Đã chuyển sang ${res.activeProfile.shortLabel || res.activeProfile.name}.`,
        from: res.previousProfile.id,
        to: res.activeProfile.id,
      };
    } catch (err) {
      if (err?.code === 'CLAUDE_COOLDOWN_ACTIVE' || err?.code === 'PROFILE_FROZEN_429') {
        return { ok: false, needsForce: true, code: err.code, message: err.message, hint: err.hint || '', target };
      }
      throw err;
    }
  }

  if (action === 'rotate' || action === 'limit') {
    const limit = action === 'limit';
    const res = rotateNextProfile({
      stateDir,
      nowMs,
      markCurrentLimited: limit,
      reason: limit ? 'web_ui_limit_429' : 'web_ui_rotate',
    });
    const to = res.activeProfile.shortLabel || res.activeProfile.name;
    return {
      ok: true,
      message: limit
        ? `Đã đóng băng ${res.previousProfile.shortLabel || res.previousProfile.id} và chuyển sang ${to}.`
        : `Đã xoay sang ${to}.`,
      from: res.previousProfile.id,
      to: res.activeProfile.id,
      requiredWaitSec: res.requiredWaitSec || 0,
    };
  }

  if (action === 'unfreeze') {
    resetLocks(stateDir);
    return { ok: true, message: 'Đã mở khóa toàn bộ 429 và xóa cooldown.' };
  }

  if (action === 'balance') {
    const mode = String(params.mode || 'even');
    if (!BALANCE_MODES.has(mode)) throw badInput('Chế độ chia repo không hợp lệ (even | swap).');
    const res = balanceRepoAccounts({ repos, stateDir, mode });
    return {
      ok: true,
      message: mode === 'swap' ? 'Đã đảo nhóm repo giữa FinOS và FinOS Team.' : 'Đã chia đều repo cho FinOS và FinOS Team.',
      changed: res.length,
    };
  }

  if (action === 'repo_assign' || action === 'repo_add' || action === 'repo_remove') {
    const repoPath = String(params.repo ?? '').trim();
    if (!repoPath) throw badInput('Thiếu đường dẫn repo.');
    const label = (id) => DEFAULT_PROFILES.find((p) => p.id === id)?.shortLabel || id;
    if (action === 'repo_assign') {
      const res = setRepoAccount({ stateDir, repos, repoPath, account: String(params.account ?? '') });
      return { ok: true, message: `${res.name}: ${res.previous ? `${label(res.previous)} → ` : ''}${label(res.account)}.`, repo: res };
    }
    if (action === 'repo_add') {
      const res = addRepo({ stateDir, repos, repoPath, account: String(params.account ?? ''), name: params.name });
      return { ok: true, message: `Đã thêm ${res.name} → ${label(res.account)}.`, repo: res };
    }
    const res = removeRepo({ stateDir, repos, repoPath });
    return { ok: true, message: `Đã gỡ ${res.name} khỏi cc-switcher${res.previous ? ` (bỏ ghim ${label(res.previous)})` : ''}.`, repo: res };
  }

  // cooldown
  const minutes = Number(params.minutes);
  if (!Number.isInteger(minutes) || minutes < 0 || minutes > 1440) throw badInput('Số phút nghỉ phải là số nguyên 0 - 1440.');
  const policy = updateAntiBanPolicy(stateDir, { claudeSwitchCooldownSec: minutes * 60 });
  return { ok: true, message: `Đã đặt thời gian nghỉ chống ban: ${minutes} phút.`, claudeSwitchCooldownSec: policy.claudeSwitchCooldownSec };
}
