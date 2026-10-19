// Quan ly 6 profile CC Switch, co che Anti-Ban Guard (Cooldown 15 phut & Dong bang 5h khi dinh 429) va dong bo SQLite.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import {
  AppError,
  resolveStateDir,
  readJsonSafe,
  writeJsonAtomic,
  logStructured,
} from './errors.js';

/**
 * Danh sach 6 profile chuan da cau hinh tren may Mac cua nguoi dung.
 */
export const DEFAULT_PROFILES = [
  {
    index: 1,
    id: 'finos',
    shortLabel: '1. FinOS',
    name: '1. FinOS — toan.huynh@finos.asia (5x Team)',
    vendor: 'anthropic',
    appType: 'claude',
    configDir: path.join(os.homedir(), '.claude-finos'),
    settingsKey: 'currentProviderClaude',
    settingsValue: 'finos',
  },
  {
    index: 2,
    id: 'finos_team',
    shortLabel: '2. FinOS Team',
    name: '2. FinOS Team — linhnt@finos.asia (5x Team)',
    vendor: 'anthropic',
    appType: 'claude',
    configDir: path.join(os.homedir(), '.claude-finos_team'),
    settingsKey: 'currentProviderClaude',
    settingsValue: 'finos_team',
  },
  {
    index: 3,
    id: 'max',
    shortLabel: '3. Claude Max',
    name: '3. Personal 5x Max — toan.huynh@finos.asia',
    vendor: 'anthropic',
    appType: 'claude',
    configDir: path.join(os.homedir(), '.claude-max'),
    settingsKey: 'currentProviderClaude',
    settingsValue: 'max',
  },
  {
    index: 4,
    id: 'antigravity',
    shortLabel: '4. AGY Ultra',
    name: '4. Antigravity Ultra — phathuy.vetgo@gmail.com (Gemini 4 Argon High)',
    vendor: 'google',
    appType: 'gemini',
    configDir: path.join(os.homedir(), '.gemini'),
    settingsKey: 'currentProviderGemini',
    settingsValue: 'antigravity',
  },
  {
    index: 5,
    id: 'antigravity_pro',
    shortLabel: '5. AGY Pro',
    name: '5. Antigravity Pro — alex.1993.dev@gmail.com (Gemini 4 Argon High)',
    vendor: 'google',
    appType: 'gemini',
    configDir: path.join(os.homedir(), '.gemini'),
    settingsKey: 'currentProviderGemini',
    settingsValue: 'antigravity_pro',
  },
  {
    index: 6,
    id: 'grok',
    shortLabel: '6. Grok 4.7',
    name: '6. Grok CLI — grok-4.7 (xhigh)',
    vendor: 'xai',
    appType: 'grokbuild',
    configDir: path.join(os.homedir(), '.config', 'grok'),
    settingsKey: 'currentProviderGrokbuild',
    settingsValue: 'grokbuild-official',
  },
];

const DEFAULT_POLICY = {
  // Khoang nghi an toan giua 2 tai khoan Claude lien tiep (mac dinh 900s = 15 phut) de chong quet Sybil/Multi-account
  claudeSwitchCooldownSec: 900,
  // Thoi gian dong bang tai khoan vua dinh Rate Limit 429 (mac dinh 18000s = 5 tieng theo cua so truot cua Claude)
  rateLimitFreezeSec: 18000,
  // Tu dong uu tien nhay sang provider khac (Antigravity/Grok) neu Claude dang trong vung cooldown
  preferCrossVendorOnCooldown: false,
};

function stateFilePath(stateDir) {
  return path.join(resolveStateDir(stateDir), 'switcher-state.json');
}

function ccSwitchSettingsPath(stateDir) {
  return path.join(resolveStateDir(stateDir), 'settings.json');
}

function ccSwitchDbPath(stateDir) {
  return path.join(resolveStateDir(stateDir), 'cc-switch.db');
}

/**
 * Nap trang thai hien tai cua Bo Chuyen Doi (Switcher State).
 */
export function loadSwitcherState(stateDir) {
  const dir = resolveStateDir(stateDir);
  const existing = readJsonSafe(stateFilePath(dir), null);
  const ccSettings = readJsonSafe(ccSwitchSettingsPath(dir), {});
  const initialActive = existing?.activeProfileId || ccSettings?.currentProviderClaude || 'finos';

  return {
    activeProfileId: initialActive,
    lastClaudeSwitchAtMs: existing?.lastClaudeSwitchAtMs || 0,
    lastClaudeRateLimitAtMs: existing?.lastClaudeRateLimitAtMs || 0,
    frozenUntil: existing?.frozenUntil || {},
    quotaCache: existing?.quotaCache || {},
    quotaFetchedAtMs: existing?.quotaFetchedAtMs || 0,
    switchHistory: Array.isArray(existing?.switchHistory) ? existing.switchHistory.slice(-50) : [],
    policy: {
      ...DEFAULT_POLICY,
      ...(existing?.policy || {}),
    },
  };
}

/**
 * Luu trang thai Switcher nguyen khoi.
 */
export function saveSwitcherState(stateDir, state) {
  const dir = resolveStateDir(stateDir);
  writeJsonAtomic(stateFilePath(dir), state, 0o600);
  return state;
}

/**
 * Cap nhat chinh sach Anti-Ban.
 */
export function updateAntiBanPolicy(stateDir, partialPolicy = {}) {
  const state = loadSwitcherState(stateDir);
  if (typeof partialPolicy.claudeSwitchCooldownSec === 'number' && partialPolicy.claudeSwitchCooldownSec >= 0) {
    state.policy.claudeSwitchCooldownSec = Math.round(partialPolicy.claudeSwitchCooldownSec);
  }
  if (typeof partialPolicy.rateLimitFreezeSec === 'number' && partialPolicy.rateLimitFreezeSec >= 60) {
    state.policy.rateLimitFreezeSec = Math.round(partialPolicy.rateLimitFreezeSec);
  }
  if (typeof partialPolicy.preferCrossVendorOnCooldown === 'boolean') {
    state.policy.preferCrossVendorOnCooldown = partialPolicy.preferCrossVendorOnCooldown;
  }
  return saveSwitcherState(stateDir, state).policy;
}

/**
 * Xoa toan bo trang thai dong bang 429 va bo dem Cooldown 15 phut (khi nguoi dung bam Mo khoa tren UI).
 */
export function resetLocks(stateDir) {
  const state = loadSwitcherState(stateDir);
  state.frozenUntil = {};
  state.lastClaudeSwitchAtMs = 0;
  state.lastClaudeRateLimitAtMs = 0;
  if (state.quotaCache && typeof state.quotaCache === 'object') {
    for (const k of Object.keys(state.quotaCache)) {
      if (state.quotaCache[k]?.isRateLimited) {
        delete state.quotaCache[k];
      }
    }
  }
  return saveSwitcherState(stateDir, state);
}

/**
 * Tim profile theo index (1..6) hoac id ('finos', 'finos_team', ...).
 */
export function resolveProfile(target) {
  if (target === undefined || target === null || target === '') {
    throw new AppError('INVALID_PROFILE', 'Chua chi dinh profile can chuyen sang.');
  }
  const str = String(target).trim().toLowerCase();
  const num = Number(str);
  const found = DEFAULT_PROFILES.find(
    (p) => p.id.toLowerCase() === str || (Number.isInteger(num) && p.index === num),
  );
  if (!found) {
    throw new AppError(
      'PROFILE_NOT_FOUND',
      `Khong tim thay profile "${target}". Chi chap nhan so 1..6 hoac id: ${DEFAULT_PROFILES.map((p) => p.id).join(', ')}`,
    );
  }
  return found;
}

/**
 * Dong bo trang thai sang settings.json va cc-switch.db cua ung dung CC Switch.
 */
function syncToCcSwitchApp(stateDir, profile) {
  const dir = resolveStateDir(stateDir);
  const settingsFile = ccSwitchSettingsPath(dir);
  const currentSettings = readJsonSafe(settingsFile, {});
  currentSettings.currentProviderClaude = profile.id;
  if (profile.settingsKey) {
    currentSettings[profile.settingsKey] = profile.settingsValue;
  }
  writeJsonAtomic(settingsFile, currentSettings, 0o600);

  const dbFile = ccSwitchDbPath(dir);
  if (fs.existsSync(dbFile) && /^[a-z0-9_]+$/i.test(profile.id)) {
    try {
      execFileSync(
        'sqlite3',
        [
          '-cmd',
          'PRAGMA busy_timeout = 2000;',
          '-cmd',
          `.param set :pid ${profile.id}`,
          dbFile,
          "UPDATE providers SET is_current = CASE WHEN id = :pid THEN 1 ELSE 0 END WHERE app_type = 'claude';",
        ],
        { timeout: 3000, stdio: 'ignore' },
      );
    } catch (err) {
      logStructured('warn', 'sqlite_sync_skipped', { error: err?.message });
    }
  }
}

/**
 * Doc thong ke chi phi va token tu bang usage_daily_rollups trong cc-switch.db neu co.
 */
function readUsageStatsFromDb(stateDir) {
  const dbFile = ccSwitchDbPath(stateDir);
  if (!fs.existsSync(dbFile)) return { totalRequests: 0, totalCostUsd: 0 };
  try {
    const out = execFileSync(
      'sqlite3',
      [
        '-cmd',
        'PRAGMA busy_timeout = 2000;',
        dbFile,
        'SELECT COALESCE(SUM(request_count),0), COALESCE(ROUND(SUM(CAST(total_cost_usd AS REAL)),2),0) FROM usage_daily_rollups;',
      ],
      { encoding: 'utf8', timeout: 3000 },
    ).trim();
    const lastLine = out.split(/\r?\n/).filter(Boolean).pop() || '';
    const [reqs, cost] = lastLine.split('|');
    return {
      totalRequests: Number(reqs) || 0,
      totalCostUsd: Number(cost) || 0,
    };
  } catch (err) {
    logStructured('warn', 'sqlite_usage_read_failed', { error: err?.message });
    return { totalRequests: 0, totalCostUsd: 0 };
  }
}

/**
 * Tao bien moi truong an toan chong lo fingerprint thiet bi cho profile.
 */
export function buildSafeEnvForProfile(profile) {
  const env = {
    CLAUDE_DISABLE_TELEMETRY: '1',
    DISABLE_TELEMETRY: '1',
    DO_NOT_TRACK: '1',
    CC_SWITCH_ACTIVE_PROFILE: profile.id,
  };
  if (profile.vendor === 'anthropic') {
    env.CLAUDE_CONFIG_DIR = profile.configDir;
  }
  return env;
}

/**
 * Chuyen sang mot profile chi dinh voi rao chan Anti-Ban Cooldown.
 */
export function switchProfile(opts = {}) {
  const {
    stateDir,
    target,
    nowMs = Date.now(),
    enforceCooldown = true,
    reason = 'manual_switch',
  } = opts;

  const profile = resolveProfile(target);
  const state = loadSwitcherState(stateDir);
  const currentProfile = DEFAULT_PROFILES.find((p) => p.id === state.activeProfileId) || DEFAULT_PROFILES[0];

  // Kiem tra xem profile dich co dang bi dong bang 5h do dinh 429 khong
  const frozenUntilMs = state.frozenUntil[profile.id] || 0;
  if (enforceCooldown && frozenUntilMs > nowMs) {
    const remainMin = Math.ceil((frozenUntilMs - nowMs) / 60000);
    throw new AppError(
      'PROFILE_FROZEN_429',
      `COOLDOWN_ACTIVE: Profile "${profile.name}" dang ngu dong cho hoi quota (con ${remainMin} phut).`,
      { hint: 'Chon profile khac hoac truyen enforceCooldown=false neu chac chan da reset.' },
    );
  }

  // Kiem tra khoang nghi 15 phut khi chuyen giua 2 tai khoan Claude (Anthropic -> Anthropic)
  if (
    enforceCooldown &&
    profile.vendor === 'anthropic' &&
    profile.id !== currentProfile.id
  ) {
    const lastClaudeEvent = Math.max(state.lastClaudeSwitchAtMs || 0, state.lastClaudeRateLimitAtMs || 0);
    const cooldownMs = (state.policy.claudeSwitchCooldownSec ?? 900) * 1000;
    if (lastClaudeEvent > 0 && nowMs - lastClaudeEvent < cooldownMs) {
      const remainSec = Math.ceil((cooldownMs - (nowMs - lastClaudeEvent)) / 1000);
      throw new AppError(
        'CLAUDE_COOLDOWN_ACTIVE',
        `COOLDOWN_ACTIVE: Can nghi an toan them ${remainSec}s (${Math.ceil(remainSec / 60)} phut) truoc khi chuyen sang tai khoan Claude "${profile.name}" de tranh bi Anthropic quet ban.`,
        { hint: 'Co the chuyen ngay sang Antigravity (4, 5) hoac Grok (6) ma khong can doi.' },
      );
    }
  }

  const changed = profile.id !== currentProfile.id;
  state.activeProfileId = profile.id;
  if (profile.vendor === 'anthropic' && (changed || !state.lastClaudeSwitchAtMs)) {
    state.lastClaudeSwitchAtMs = nowMs;
  }
  if (frozenUntilMs <= nowMs) {
    delete state.frozenUntil[profile.id];
  }
  if (changed) {
    state.switchHistory.push({
      from: currentProfile.id,
      to: profile.id,
      reason,
      at: new Date(nowMs).toISOString(),
    });
  }

  saveSwitcherState(stateDir, state);
  syncToCcSwitchApp(stateDir, profile);

  return {
    previousProfile: currentProfile,
    activeProfile: profile,
    env: buildSafeEnvForProfile(profile),
    policy: state.policy,
  };
}

/**
 * Xoay vong sang profile kha dung tiep theo theo thu tu 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 1.
 */
export function rotateNextProfile(opts = {}) {
  const {
    stateDir,
    nowMs = Date.now(),
    markCurrentLimited = false,
    reason = 'auto_rotate',
  } = opts;

  const state = loadSwitcherState(stateDir);
  const currentIdx = Math.max(
    0,
    DEFAULT_PROFILES.findIndex((p) => p.id === state.activeProfileId),
  );
  const currentProfile = DEFAULT_PROFILES[currentIdx];

  if (markCurrentLimited) {
    const freezeMs = (state.policy.rateLimitFreezeSec ?? 18000) * 1000;
    state.frozenUntil[currentProfile.id] = nowMs + freezeMs;
    if (currentProfile.vendor === 'anthropic') {
      state.lastClaudeRateLimitAtMs = nowMs;
    }
    saveSwitcherState(stateDir, state);
  }

  const freshState = loadSwitcherState(stateDir);
  const prevClaudeEvent = Math.max(state.lastClaudeSwitchAtMs || 0, currentProfile.vendor === 'anthropic' && markCurrentLimited ? nowMs : (state.lastClaudeRateLimitAtMs || 0));
  const claudeCooldownMs = (freshState.policy.claudeSwitchCooldownSec ?? 900) * 1000;
  const isClaudeInCooldown = prevClaudeEvent > 0 && nowMs - prevClaudeEvent < claudeCooldownMs;

  // Tim ung vien khong bi dong bang: neu dang trong Cooldown cua Claude va bat che do uu tien khac hang,
  // xoay theo dung thu tu chong ban: Grok CLI (6) -> AGY Ultra (4) -> AGY Pro (5)
  const crossVendorOrder = ['grok', 'antigravity', 'antigravity_pro'];
  let chosen = null;
  if (freshState.policy.preferCrossVendorOnCooldown && isClaudeInCooldown) {
    for (const candId of crossVendorOrder) {
      const candidate = DEFAULT_PROFILES.find((p) => p.id === candId);
      if (!candidate) continue;
      const frozenUntilMs = freshState.frozenUntil[candidate.id] || 0;
      if (frozenUntilMs > nowMs) continue;
      chosen = candidate;
      break;
    }
  }

  // Xoay tuan tu qua 6 tai khoan (bo qua tai khoan dang dong bang 5h)
  let requiredWaitSec = 0;
  if (!chosen) {
    for (let offset = 1; offset <= DEFAULT_PROFILES.length; offset += 1) {
      const candidate = DEFAULT_PROFILES[(currentIdx + offset) % DEFAULT_PROFILES.length];
      const frozenUntilMs = freshState.frozenUntil[candidate.id] || 0;
      if (frozenUntilMs <= nowMs) {
        chosen = candidate;
        if (candidate.vendor === 'anthropic' && isClaudeInCooldown) {
          requiredWaitSec = Math.ceil((claudeCooldownMs - (nowMs - prevClaudeEvent)) / 1000);
        }
        break;
      }
    }
  }

  if (!chosen) {
    // Moi profile deu dang dong bang -> chon profile sap het dong bang som nhat
    chosen = [...DEFAULT_PROFILES].sort(
      (a, b) => (freshState.frozenUntil[a.id] || 0) - (freshState.frozenUntil[b.id] || 0),
    )[0];
    requiredWaitSec = Math.max(0, Math.ceil(((freshState.frozenUntil[chosen.id] || 0) - nowMs) / 1000));
  }

  const switched = switchProfile({
    stateDir,
    target: chosen.id,
    nowMs,
    enforceCooldown: false,
    reason,
  });

  return {
    ...switched,
    requiredWaitSec,
  };
}

/**
 * Bao cao tai khoan hien tai cham Rate Limit (429 / Quota Exhausted):
 * Dong bang 5h va de xuat tai khoan du phong khac hang theo thu tu Grok CLI -> AGY Ultra -> AGY Pro (khong nhay cheo Claude).
 */
export function reportRateLimit(opts = {}) {
  const { stateDir, profileId, nowMs = Date.now(), reason = '429_rate_limit' } = opts;
  const state = loadSwitcherState(stateDir);
  const targetId = profileId || state.activeProfileId;
  const limitedProfile = resolveProfile(targetId);

  const freezeMs = (state.policy.rateLimitFreezeSec ?? 18000) * 1000;
  state.frozenUntil[limitedProfile.id] = nowMs + freezeMs;
  if (limitedProfile.vendor === 'anthropic') {
    state.lastClaudeRateLimitAtMs = nowMs;
  }
  saveSwitcherState(stateDir, state);

  // Neu tai khoan vua cham limit la Claude, uu tien chuyen thang sang Khac Hang (Grok CLI -> AGY Ultra -> AGY Pro)
  // de tuyet doi khong nhay cheo giua cac tai khoan Claude tren cung Repo.
  let nextCandidate = null;
  if (limitedProfile.vendor === 'anthropic') {
    for (const candId of ['grok', 'antigravity', 'antigravity_pro']) {
      const cand = DEFAULT_PROFILES.find((p) => p.id === candId);
      if (cand && (state.frozenUntil[cand.id] || 0) <= nowMs) {
        nextCandidate = cand;
        break;
      }
    }
  }
  if (!nextCandidate) {
    const currentIdx = DEFAULT_PROFILES.findIndex((p) => p.id === limitedProfile.id);
    for (let offset = 1; offset <= DEFAULT_PROFILES.length; offset += 1) {
      const cand = DEFAULT_PROFILES[(currentIdx + offset) % DEFAULT_PROFILES.length];
      if ((state.frozenUntil[cand.id] || 0) <= nowMs) {
        nextCandidate = cand;
        break;
      }
    }
  }

  return {
    limitedProfile,
    frozenUntilIso: new Date(state.frozenUntil[limitedProfile.id]).toISOString(),
    freezeMinutes: Math.round(freezeMs / 60000),
    recommendedCooldownSec: limitedProfile.vendor === 'anthropic' ? state.policy.claudeSwitchCooldownSec : 0,
    nextProfile: nextCandidate,
    reason,
  };
}

export function formatLocalTimeHHMM(tsMs) {
  if (!tsMs || tsMs <= 0) return '';
  return new Intl.DateTimeFormat('vi-VN', {
    timeZone: 'Asia/Ho_Chi_Minh',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(new Date(tsMs));
}

export function formatRemainDuration(remainMs) {
  if (!remainMs || remainMs <= 0) return '0p';
  const totalMin = Math.max(1, Math.ceil(remainMs / 60000));
  const h = Math.floor(totalMin / 60);
  const m = totalMin % 60;
  if (h > 0 && m > 0) return `${h}h ${m}p`;
  if (h > 0) return `${h}h`;
  return `${m}p`;
}

/**
 * Truy van truc tiep % Quota 5h & 7d va gio mo khoa tu Anthropic OAuth Usage API qua Keychain cua tung profile.
 * Luu y quan trong:
 * - Khi Quota 5h cua Claude cham 100% (con 0%), endpoint /api/oauth/usage VAN tra ve HTTP 200 kem five_hour.utilization = 100.
 * - Khi endpoint /api/oauth/usage tra ve HTTP 429 (hoac 401 do accessToken cua tai khoan standby het han), do la rate-limit cua
 *   chinh HTTP endpoint kiem tra chu KHONG phai tai khoan Claude het quota! Tuyet doi khong quy HTTP 429 nay thanh remainingPct = 0.
 */
export async function fetchAnthropicProfileQuotaLive(profile, nowMs = Date.now(), opts = {}) {
  if (profile.vendor !== 'anthropic' || !profile.configDir) return null;
  const { tokenReader, httpFetcher = globalThis.fetch } = opts;

  let oauth = null;
  if (typeof tokenReader === 'function') {
    oauth = tokenReader(profile);
  } else {
    const hash = crypto.createHash('sha256').update(profile.configDir).digest('hex').slice(0, 8);
    const svc = `Claude Code-credentials-${hash}`;
    try {
      const raw = execFileSync('security', ['find-generic-password', '-s', svc, '-w'], {
        encoding: 'utf8',
        timeout: 3000,
        stdio: ['ignore', 'pipe', 'ignore'],
      }).trim();
      oauth = JSON.parse(raw)?.claudeAiOauth || null;
    } catch (err) {
      logStructured('warn', 'keychain_quota_read_skipped', { profileId: profile.id, error: err?.message });
      return null;
    }
  }

  const token = oauth?.accessToken || '';
  if (!token) return null;

  // Neu tai khoan dang o che do standby va accessToken da het han -> bo qua khong spam /api/oauth/usage gay 429
  if (typeof oauth?.expiresAt === 'number' && oauth.expiresAt > 0 && oauth.expiresAt <= nowMs) {
    logStructured('info', 'oauth_token_expired_skip_usage_poll', { profileId: profile.id });
    return null;
  }

  try {
    const res = await httpFetcher('https://api.anthropic.com/api/oauth/usage', {
      headers: {
        Authorization: `Bearer ${token}`,
        'anthropic-beta': 'oauth-2025-04-20',
        Accept: 'application/json',
      },
      signal: AbortSignal.timeout(8000),
    });

    if (res.status === 200) {
      const body = await res.json().catch(() => ({}));
      const usedPct = Math.min(100, Math.max(0, Math.round(Number(body?.five_hour?.utilization ?? 0))));
      const remainingPct = Math.max(0, 100 - usedPct);
      const rawResetIso =
        body?.five_hour?.resets_at ||
        body?.limits?.find((l) => l.group === 'session')?.resets_at ||
        '';
      const rawResetMs = rawResetIso ? Date.parse(rawResetIso) : 0;
      // Luon giu moc gio reset 5h (resets_at) do Anthropic OAuth Usage API tra ve de hien thi ⏰ dong nhat tren ca 3 tai khoan
      const resetAtMs = Number.isFinite(rawResetMs) && rawResetMs > 0 ? rawResetMs : 0;
      const weeklyUsed = Number(
        body?.seven_day?.utilization ??
          body?.limits?.find((l) => l.group === 'weekly')?.percent ??
          0,
      );
      const weeklyRemainingPct = Math.max(0, 100 - Math.round(weeklyUsed));
      return {
        remainingPct,
        usedPct,
        resetAtMs,
        weeklyRemainingPct,
        isRateLimited: remainingPct <= 0,
        source: 'anthropic_oauth',
        updatedAtMs: nowMs,
      };
    }

    if (res.status === 429) {
      logStructured('warn', 'usage_endpoint_throttled_429', { profileId: profile.id });
      return null;
    }
  } catch (err) {
    logStructured('warn', 'anthropic_quota_fetch_failed', { profileId: profile.id, error: err?.message });
  }
  return null;
}

/**
 * Dong bo % Quota thuc te cua cac tai khoan vao switcher-state.json va tu dong cap nhat moc mo khoa (frozenUntil).
 */
export async function syncLiveQuotas(opts = {}) {
  const {
    stateDir,
    nowMs = Date.now(),
    forceRefresh = false,
    ttlMs = 45_000,
    quotaFetcher = fetchAnthropicProfileQuotaLive,
  } = opts;

  const state = loadSwitcherState(stateDir);
  if (!forceRefresh && state.quotaFetchedAtMs && nowMs - state.quotaFetchedAtMs < ttlMs) {
    return state.quotaCache;
  }

  let updated = false;
  for (const p of DEFAULT_PROFILES) {
    try {
      const q = await quotaFetcher(p, nowMs);
      if (q && typeof q.remainingPct === 'number') {
        state.quotaCache[p.id] = {
          ...q,
          updatedAtMs: nowMs,
        };
        if (q.remainingPct <= 0 && q.resetAtMs > nowMs) {
          state.frozenUntil[p.id] = q.resetAtMs;
        } else if (q.remainingPct > 0 && state.frozenUntil[p.id]) {
          delete state.frozenUntil[p.id];
        }
        updated = true;
      } else if (state.quotaCache?.[p.id]?.source === 'anthropic_429_header') {
        // Tu dong xoa cache 0% gia do loi quy chup HTTP 429 cua endpoint /api/oauth/usage truoc day
        delete state.quotaCache[p.id];
        delete state.frozenUntil[p.id];
        updated = true;
      }
    } catch (err) {
      logStructured('warn', 'sync_profile_quota_error', { profileId: p.id, error: err?.message });
    }
  }

  if (updated) {
    state.quotaFetchedAtMs = nowMs;
    saveSwitcherState(stateDir, state);
  }
  return state.quotaCache;
}

/**
 * Danh sach 6 Repo mac dinh tren may Mac, chia deu 3 repo -> finos va 3 repo -> finos_team
 * giup co lap 100% session theo tung du an va nhan doi bang thong (5x + 5x = 10x) ma khong bi ban.
 */
export const DEFAULT_REPOS = [
  {
    name: 'agent-workbench',
    path: '/Volumes/Data/Toan/agent-workbench',
    defaultAccount: 'finos',
  },
  {
    name: 'OfficeReader',
    path: '/Volumes/Data/Toan/OfficeReader/OfficeReader',
    defaultAccount: 'finos',
  },
  {
    name: 'Neighbours-From-Hell',
    path: '/Volumes/Data/Toan/Game/Neighbours-From-Hell',
    defaultAccount: 'finos',
  },
  {
    name: 'GeelyEx2',
    path: '/Volumes/Data/Toan/GeelyEx2',
    defaultAccount: 'finos_team',
  },
  {
    name: 'Goods-Triple-Shelf-Match-3D',
    path: '/Volumes/Data/Toan/Game/Goods-Triple-Shelf-Match-3D',
    defaultAccount: 'finos_team',
  },
  {
    name: 'Humans-vs.-UFOs',
    path: '/Volumes/Data/Toan/Game/Humans-vs.-UFOs',
    defaultAccount: 'finos_team',
  },
];

/**
 * Doc danh sach phan bo tai khoan (.claude/settings.local.json -> account) cua 6 repo.
 */
export function getRepoAssignments(opts = {}) {
  const repos = Array.isArray(opts.repos) && opts.repos.length > 0 ? opts.repos : DEFAULT_REPOS;
  return repos.map((r, idx) => {
    const settingsPath = path.join(r.path, '.claude', 'settings.local.json');
    let account = '';
    let exists = false;
    try {
      if (fs.existsSync(settingsPath)) {
        exists = true;
        const parsed = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
        if (typeof parsed.account === 'string') {
          account = parsed.account.trim();
        }
      }
    } catch (err) {
      logStructured('warn', 'read_repo_settings_failed', { repo: r.name, error: err?.message });
    }
    const fallbackAccount = r.defaultAccount || (idx < Math.ceil(repos.length / 2) ? 'finos' : 'finos_team');
    return {
      name: r.name,
      path: r.path,
      account: account || fallbackAccount,
      pinnedInFile: Boolean(account),
      exists,
    };
  });
}

/**
 * Tu dong chia deu hoac dao nhom 3 repo -> finos, 3 repo -> finos_team trong .claude/settings.local.json,
 * giu nguyen 100% cac khoa cau hinh hien co (autoMemoryDirectory, hooks, permissions...).
 */
export function balanceRepoAccounts(opts = {}) {
  const repos = Array.isArray(opts.repos) && opts.repos.length > 0 ? opts.repos : DEFAULT_REPOS;
  const mode = opts.mode || 'even'; // 'even' | 'swap' | 'all_finos' | 'all_finos_team'
  const half = Math.ceil(repos.length / 2);

  const results = [];
  repos.forEach((r, idx) => {
    if (!fs.existsSync(r.path)) return;
    const claudeDir = path.join(r.path, '.claude');
    const settingsPath = path.join(claudeDir, 'settings.local.json');
    let existing = {};
    try {
      if (fs.existsSync(settingsPath)) {
        existing = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
      }
    } catch (err) {
      logStructured('warn', 'parse_existing_settings_failed', { repo: r.name, error: err?.message });
    }

    let nextAccount = r.defaultAccount || (idx < half ? 'finos' : 'finos_team');
    if (mode === 'swap') {
      const currentAcc = existing.account || nextAccount;
      nextAccount = currentAcc === 'finos' ? 'finos_team' : 'finos';
    } else if (mode === 'all_finos') {
      nextAccount = 'finos';
    } else if (mode === 'all_finos_team') {
      nextAccount = 'finos_team';
    }

    const updated = {
      ...existing,
      account: nextAccount,
    };
    writeJsonAtomic(settingsPath, updated);
    results.push({
      name: r.name,
      path: r.path,
      account: nextAccount,
      settingsPath,
    });
  });

  logStructured('info', 'repo_accounts_balanced', { mode, count: results.length });
  return results;
}

/**
 * Tong hop bao cao trang thai 6 profile kem % Quota con lai, thanh tien trinh, gio mo khoa va phan bo 6 repo.
 */
export function getStatusReport(opts = {}) {
  const { stateDir, nowMs = Date.now(), repos } = opts;
  const state = loadSwitcherState(stateDir);
  const usage = readUsageStatsFromDb(stateDir);
  const repoAssignments = getRepoAssignments({ repos });

  const lastClaudeEvent = Math.max(state.lastClaudeSwitchAtMs || 0, state.lastClaudeRateLimitAtMs || 0);
  const claudeCooldownMs = (state.policy.claudeSwitchCooldownSec ?? 900) * 1000;
  const claudeCooldownRemainSec = lastClaudeEvent > 0
    ? Math.max(0, Math.ceil((claudeCooldownMs - (nowMs - lastClaudeEvent)) / 1000))
    : 0;

  const profiles = DEFAULT_PROFILES.map((p) => {
    const cachedQuota = state.quotaCache?.[p.id] || null;
    const rawFrozenMs = state.frozenUntil[p.id] || 0;
    const quotaResetMs = cachedQuota?.resetAtMs || 0;
    const effectiveResetMs = rawFrozenMs > nowMs ? rawFrozenMs : (quotaResetMs > nowMs ? quotaResetMs : 0);

    const isQuotaZero = cachedQuota && typeof cachedQuota.remainingPct === 'number' && cachedQuota.remainingPct <= 0 && effectiveResetMs > nowMs;
    const isFrozen = rawFrozenMs > nowMs || Boolean(isQuotaZero);
    const freezeRemainMin = isFrozen ? Math.max(1, Math.ceil((effectiveResetMs - nowMs) / 60000)) : 0;

    let remainingPct = 100;
    if (isFrozen) {
      remainingPct = 0;
    } else if (cachedQuota && typeof cachedQuota.remainingPct === 'number') {
      // Neu cua so 5h truoc da qua gio reset -> tu dong hoi phuc 100%
      remainingPct = quotaResetMs > 0 && quotaResetMs <= nowMs ? 100 : cachedQuota.remainingPct;
    }
    const usedPct = Math.max(0, 100 - remainingPct);
    const resetTimeFormatted = effectiveResetMs > nowMs ? formatLocalTimeHHMM(effectiveResetMs) : '';
    const resetRemainHuman = effectiveResetMs > nowMs ? formatRemainDuration(effectiveResetMs - nowMs) : '';

    const assignedRepoCount = repoAssignments.filter((r) => r.account === p.id).length;
    const isParallelActive = !isFrozen && (p.id === state.activeProfileId || assignedRepoCount > 0);

    return {
      ...p,
      isActive: p.id === state.activeProfileId,
      isParallelActive,
      assignedRepoCount,
      status: isFrozen
        ? `LIMIT 0% (Mở ${resetTimeFormatted || `${freezeRemainMin}p`})`
        : isParallelActive
          ? `ACTIVE (${remainingPct}%)`
          : `READY (${remainingPct}%)`,
      isFrozen,
      freezeRemainMin,
      remainingPct,
      usedPct,
      weeklyRemainingPct: cachedQuota?.weeklyRemainingPct ?? null,
      resetAtMs: effectiveResetMs,
      resetTimeFormatted,
      resetRemainHuman,
    };
  });

  return {
    activeProfileId: state.activeProfileId,
    activeProfile: profiles.find((p) => p.isActive) || profiles[0],
    claudeCooldownRemainSec,
    policy: state.policy,
    usage,
    profiles,
    repoAssignments,
    recentSwitches: state.switchHistory.slice(-5),
  };
}

