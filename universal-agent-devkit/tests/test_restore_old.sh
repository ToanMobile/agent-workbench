#!/usr/bin/env bash
# test_restore_old.sh — `agent-kit restore-old` puts recorded *_old backups back, and only
# when the original location holds nothing but DevKit content. Dry-run by default.
set -u

DEVKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/restore-old-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()  { echo "✔ $1"; PASS=$((PASS + 1)); }
bad() { echo "✘ $1"; FAIL=$((FAIL + 1)); }

# shellcheck source=/dev/null
_bc="$DEVKIT/scripts/git/backup_conflict.sh"; [ -f "$_bc" ] || _bc="$DEVKIT/scripts/backup_conflict.sh"
DEVKIT_ROOT="$DEVKIT" source "$_bc" >/dev/null
export DEVKIT_ROOT="$DEVKIT"

P="$TMP/proj"
mkdir -p "$P/.claude/commands" "$P/rules"

# 1. a user file replaced by a DevKit symlink
echo "my notes" > "$P/CLAUDE.md"
backup_conflict "$P/CLAUDE.md" "$DEVKIT" >/dev/null
ln -s "$DEVKIT/AGENTS.md" "$P/CLAUDE.md"
# 2. a user command inside .claude/commands (moved to the project tier .agents/local/commands/)
echo "mine" > "$P/.claude/commands/fix.md"
backup_conflict "$P/.claude/commands/fix.md" "$DEVKIT" >/dev/null
ln -s "$DEVKIT/commands/fix.md" "$P/.claude/commands/fix.md"
# 3. a user file whose location the user has since filled with their own content again
echo "v1" > "$P/.cursorrules"
backup_conflict "$P/.cursorrules" "$DEVKIT" >/dev/null
echo "user edited after install" > "$P/.cursorrules"
# 4. a location backed up twice: the oldest backup (the original) wins
echo "original" > "$P/rules/x.md"
backup_conflict "$P/rules/x.md" "$DEVKIT" >/dev/null
echo "second" > "$P/rules/x.md"
backup_conflict "$P/rules/x.md" "$DEVKIT" >/dev/null

[ -f "$P/CLAUDE_old.md" ] && [ -f "$P/.agents/local/commands/fix.md" ] && [ -f "$P/rules/x_old.md" ] \
  && ok "setup: backups recorded" || bad "setup: backups recorded"

# dry-run changes nothing
before="$(cd "$P" && find . | LC_ALL=C sort | shasum)"
out="$(bash "$DEVKIT/bin/agent-kit" restore-old "$P" 2>&1)"; rc=$?
after="$(cd "$P" && find . | LC_ALL=C sort | shasum)"
[ "$before" = "$after" ] && ok "dry-run leaves the project untouched" || bad "dry-run leaves the project untouched"
echo "$out" | grep -q "would    CLAUDE_old.md -> CLAUDE.md" && ok "dry-run lists the CLAUDE.md restore" || bad "dry-run lists the CLAUDE.md restore: $out"
echo "$out" | grep -q "SKIP     .cursorrules" && ok "dry-run reports the location holding user content" || bad "dry-run reports .cursorrules skip: $out"
[ "$rc" -ne 0 ] && ok "a skipped restore makes the exit status non-zero" || bad "exit status with a skipped restore (rc=$rc)"

bash "$DEVKIT/bin/agent-kit" restore-old "$P" --bogus >/dev/null 2>&1
[ $? -eq 2 ] && ok "unknown option -> exit 2" || bad "unknown option -> exit 2"

out="$(bash "$DEVKIT/bin/agent-kit" restore-old "$P" --apply 2>&1)"
[ -f "$P/CLAUDE.md" ] && [ ! -L "$P/CLAUDE.md" ] && [ "$(cat "$P/CLAUDE.md")" = "my notes" ] \
  && ok "apply: CLAUDE.md is the user's file again" || bad "apply: CLAUDE.md restored: $out"
[ ! -e "$P/CLAUDE_old.md" ] && ok "apply: CLAUDE_old.md consumed" || bad "apply: CLAUDE_old.md consumed"
[ "$(cat "$P/.claude/commands/fix.md" 2>/dev/null)" = "mine" ] && [ ! -L "$P/.claude/commands/fix.md" ] \
  && ok "apply: .claude/commands/fix.md restored from .agents/local/commands/" || bad "apply: command restored: $out"
[ "$(cat "$P/.cursorrules")" = "user edited after install" ] && [ -f "$P/.cursorrules_old" ] \
  && ok "apply: user content is never overwritten" || bad "apply: .cursorrules untouched"
[ "$(cat "$P/rules/x.md" 2>/dev/null)" = "original" ] && ok "apply: oldest backup of a twice-backed-up file wins" \
  || bad "apply: oldest backup wins (got '$(cat "$P/rules/x.md" 2>/dev/null)')"
ls "$P/rules" | grep -q "x_old_" && ok "apply: the later backup is kept" || bad "apply: later backup kept"
[ -e "$DEVKIT/AGENTS.md" ] && [ -e "$DEVKIT/commands/fix.md" ] && ok "apply: DevKit sources untouched" || bad "apply: DevKit sources untouched"

# a ledger line pointing outside the project is ignored
mkdir -p "$TMP/outside"
echo "keep" > "$TMP/outside/a_old.md"
echo "2026-01-01 00:00:00 | $TMP/outside/a.md -> $TMP/outside/a_old.md" >> "$P/.devkit_backups.log"
bash "$DEVKIT/bin/agent-kit" restore-old "$P" --apply >/dev/null 2>&1
[ -f "$TMP/outside/a_old.md" ] && [ ! -e "$TMP/outside/a.md" ] && ok "ledger entries outside the project are ignored" \
  || bad "ledger entries outside the project are ignored"

echo
echo "restore-old: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] && echo "restore-old: all checks passed"
[ "$FAIL" -eq 0 ]
