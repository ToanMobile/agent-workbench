// Quan ly 6 profile CC Switch, co che Anti-Ban Guard (Cooldown 15 phut & Dong bang 5h khi dinh 429) va dong bo SQLite.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
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
    shortLabel: '1. FinOS (5x)',
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

  // Tim ung vien khong bi dong bang theo thu tu 1 -> 2 -> 3 -> 4 -> 5 -> 6
  let chosen = null;
  if (freshState.policy.preferCrossVendorOnCooldown && isClaudeInCooldown) {
    for (let offset = 1; offset <= DEFAULT_PROFILES.length; offset += 1) {
      const candidate = DEFAULT_PROFILES[(currentIdx + offset) % DEFAULT_PROFILES.length];
      const frozenUntilMs = freshState.frozenUntil[candidate.id] || 0;
      if (frozenUntilMs > nowMs) continue;
      if (candidate.vendor === 'anthropic') continue;
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
 * Dong bang 5h va xoay sang tai khoan an toan ke tiep.
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

  // Tim tai khoan tiep theo khong bi dong bang
  const currentIdx = DEFAULT_PROFILES.findIndex((p) => p.id === limitedProfile.id);
  let nextCandidate = null;
  for (let offset = 1; offset <= DEFAULT_PROFILES.length; offset += 1) {
    const cand = DEFAULT_PROFILES[(currentIdx + offset) % DEFAULT_PROFILES.length];
    if ((state.frozenUntil[cand.id] || 0) <= nowMs) {
      nextCandidate = cand;
      break;
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

/**
 * Tong hop bao cao trang thai 6 profile kem thong ke token/chi phi.
 */
export function getStatusReport(opts = {}) {
  const { stateDir, nowMs = Date.now() } = opts;
  const state = loadSwitcherState(stateDir);
  const usage = readUsageStatsFromDb(stateDir);

  const lastClaudeEvent = Math.max(state.lastClaudeSwitchAtMs || 0, state.lastClaudeRateLimitAtMs || 0);
  const claudeCooldownMs = (state.policy.claudeSwitchCooldownSec ?? 900) * 1000;
  const claudeCooldownRemainSec = lastClaudeEvent > 0
    ? Math.max(0, Math.ceil((claudeCooldownMs - (nowMs - lastClaudeEvent)) / 1000))
    : 0;

  const profiles = DEFAULT_PROFILES.map((p) => {
    const frozenUntilMs = state.frozenUntil[p.id] || 0;
    const isFrozen = frozenUntilMs > nowMs;
    const freezeRemainMin = isFrozen ? Math.ceil((frozenUntilMs - nowMs) / 60000) : 0;
    return {
      ...p,
      isActive: p.id === state.activeProfileId,
      status: isFrozen ? `FROZEN (${freezeRemainMin}m left)` : (p.id === state.activeProfileId ? 'ACTIVE' : 'READY'),
      isFrozen,
      freezeRemainMin,
    };
  });

  return {
    activeProfileId: state.activeProfileId,
    activeProfile: profiles.find((p) => p.isActive) || profiles[0],
    claudeCooldownRemainSec,
    policy: state.policy,
    usage,
    profiles,
    recentSwitches: state.switchHistory.slice(-5),
  };
}
