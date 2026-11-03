// Doi id 4 tai khoan (finos->finos_toan, finos_team->finos_linh, max->finos_toan_max, antigravity->antigravity_ultra) tren may.
// Chi sua: khoa "account" trong .claude/settings.local.json cua cac repo va switcher-state.json cua cc-switcher.
// KHONG cham: thu muc ~/.claude-* (Keychain luu dang nhap theo sha256(duong dan), doi ten la mat dang nhap), ~/.cc-switch/cc-switch.db
// va settings.json cua app CC Switch (app ben thu ba, van dung id cu qua appProviderId), ~/.zshrc.
import fs from 'node:fs';
import path from 'node:path';
import { AppError, resolveStateDir, readJsonSafe, writeJsonAtomic, logStructured } from './errors.js';
import { canonicalProfileId, canonicalKeys, listKnownRepos } from './profiles.js';

/**
 * @param {{stateDir?: string, repos?: Array<{name: string, path: string}>, dryRun?: boolean}} opts
 * @returns {{dryRun: boolean, repoPins: Array, skipped: Array, state: {changed: boolean, file: string}}}
 */
export function migrateIds(opts = {}) {
  const dryRun = Boolean(opts.dryRun);
  const stateDir = resolveStateDir(opts.stateDir);
  const repos = Array.isArray(opts.repos) && opts.repos.length > 0 ? opts.repos : listKnownRepos({ stateDir: opts.stateDir });
  const repoPins = [];
  const skipped = [];

  for (const r of repos) {
    const settingsPath = path.join(r.path, '.claude', 'settings.local.json');
    if (!fs.existsSync(settingsPath)) continue;
    let data;
    try {
      data = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
      if (!data || typeof data !== 'object' || Array.isArray(data)) throw new AppError('INVALID_INPUT', 'not a JSON object');
    } catch (err) {
      // File hong: giu nguyen tung byte, chi bao (nhu balanceRepoAccounts).
      skipped.push({ name: r.name, path: r.path, error: err?.message || String(err) });
      logStructured('warn', 'migrate_ids_settings_unreadable', { repo: r.name, error: err?.message });
      continue;
    }
    const from = typeof data.account === 'string' ? data.account : '';
    const to = canonicalProfileId(from);
    if (!from || to === from) continue;
    repoPins.push({ name: r.name, path: r.path, from, to });
    if (!dryRun) writeJsonAtomic(settingsPath, { ...data, account: to });
  }

  const stateFile = path.join(stateDir, 'switcher-state.json');
  const raw = readJsonSafe(stateFile, null);
  let changed = false;
  if (raw && typeof raw === 'object') {
    const next = { ...raw };
    if (typeof raw.activeProfileId === 'string') next.activeProfileId = canonicalProfileId(raw.activeProfileId);
    if (raw.frozenUntil) next.frozenUntil = canonicalKeys(raw.frozenUntil);
    if (raw.quotaCache) next.quotaCache = canonicalKeys(raw.quotaCache);
    changed = JSON.stringify(next) !== JSON.stringify(raw);
    if (changed && !dryRun) writeJsonAtomic(stateFile, next, 0o600);
  }

  logStructured('info', 'migrate_ids', { dryRun, repoPins: repoPins.length, skipped: skipped.length, stateChanged: changed });
  return { dryRun, repoPins, skipped, state: { changed, file: stateFile } };
}
