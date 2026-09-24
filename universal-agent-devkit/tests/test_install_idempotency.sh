#!/usr/bin/env bash
# Regression test: re-running the installer and switching symlink <-> copy mode
# must be idempotent — the DevKit lives at .agents/devkit (one link, or a copy of
# AGENTS.md rules/ bin/), nothing is written into the devkit through a link, copies
# have no dangling links, and devkit-owned files never produce *_old backups.
set -u

DEVKIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$(mktemp -d -t devkit-idem-XXXXXX)"
trap 'rm -rf "$PROJ"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

install() { bash "$DEVKIT_ROOT/bin/install.sh" -t "$PROJ" -y -p universal -m "$1" >/dev/null 2>&1 || fail "install -m $1 exited non-zero"; }
count_old() { find "$PROJ" -maxdepth 4 \( -name "*_old" -o -name "*_old.*" -o -name "*_old_*" \) | wc -l | xargs; }
devkit_snapshot() { ls -A "$DEVKIT_ROOT/rules" "$DEVKIT_ROOT/skills" "$DEVKIT_ROOT/commands" "$DEVKIT_ROOT/bin"; }
DK="$PROJ/.agents/devkit"

before="$(devkit_snapshot)"

install symlink
install symlink
[ "$(count_old)" = 0 ] && ok "symlink re-install creates no *_old" || { fail "symlink re-install created *_old: $(count_old)"; find "$PROJ" -maxdepth 4 -name "*_old*"; }
[ -L "$DK" ] && [ -f "$DK/rules/essentials.md" ] && ok "symlink mode: .agents/devkit is one link to the DevKit" || fail ".agents/devkit is not a link to the DevKit"
for n in rules skills commands; do [ -e "$PROJ/$n" ] && fail "root $n/ created"; done

install copy
[ -d "$DK" ] && [ ! -L "$DK" ] && [ -d "$DK/rules" ] && [ ! -L "$DK/rules" ] && ok "switch to copy replaces the link with a real .agents/devkit/rules" || fail ".agents/devkit/rules is not a real dir after copy install"
[ -e "$DEVKIT_ROOT/rules/rules" ] || [ -e "$DEVKIT_ROOT/devkit" ] && fail "copy install wrote INTO the devkit" || ok "devkit untouched by copy install"
dangling="$(find "$DK" -type l ! -exec test -e {} \; -print | wc -l | xargs)"
[ "$dangling" = 0 ] && ok "copied tree has no dangling links" || fail "copied tree has $dangling dangling links"

install copy
install copy
[ "$(count_old)" = 0 ] && ok "copy re-installs create no *_old" || { fail "copy re-install created *_old:"; find "$PROJ" -maxdepth 4 -name "*_old*"; }

install symlink
[ -L "$DK" ] && [ ! -e "$DEVKIT_ROOT/rules/rules" ] && ok "switch back to symlink leaves one clean link" || fail ".agents/devkit not a clean link after switching back"
[ "$(count_old)" = 0 ] && ok "copy -> symlink creates no *_old" || { fail "copy -> symlink created *_old:"; find "$PROJ" -maxdepth 4 -name "*_old*"; }

# A user edit to a copied DevKit file is kept in the project tier (only the edited file),
# never silently overwritten; the DevKit copy is refreshed.
install copy
echo "TEAM EDIT" >> "$DK/rules/core-rules.md"
install copy
if grep -qs "TEAM EDIT" "$PROJ/.agents/local/rules/core-rules.md"; then ok "user edit kept in .agents/local/rules/"; else fail "user edit lost"; fi
[ "$(find "$PROJ/.agents/local/rules" -type f ! -name .devkit_backups.log | wc -l | xargs)" = 1 ] \
  && ok "only the edited file is kept, not a stale copy of rules/" || fail "project tier holds more than the edit"
! grep -qs "TEAM EDIT" "$DK/rules/core-rules.md" && [ -f "$DK/rules/.devkit-copy" ] \
  && ok ".agents/devkit/rules is a fresh DevKit copy again" || fail ".agents/devkit/rules not refreshed"

# 1.2 layout: root rules/ skills/ commands/ links and .agents/devkit/AGENTS.md are migrated.
rm -rf "$PROJ/.agents/local" "$DK"
mkdir -p "$DK" && ln -s "$DEVKIT_ROOT/AGENTS.md" "$DK/AGENTS.md"
for n in rules skills commands; do ln -s "$DEVKIT_ROOT/$n" "$PROJ/$n"; done
install symlink
[ ! -e "$PROJ/rules" ] && [ ! -L "$PROJ/skills" ] && [ ! -L "$PROJ/commands" ] && [ -L "$DK" ] && [ "$(count_old)" = 0 ] \
  && ok "1.2 root links and .agents/devkit/AGENTS.md migrated to one .agents/devkit link" || fail "1.2 layout not migrated cleanly"

[ "$(devkit_snapshot)" = "$before" ] && ok "devkit rules/skills/commands/bin listing unchanged" || fail "devkit tree changed during install runs"

if [ "$FAILS" -ne 0 ]; then echo "install idempotency: $FAILS FAILED"; exit 1; fi
echo "install idempotency: all checks passed"
