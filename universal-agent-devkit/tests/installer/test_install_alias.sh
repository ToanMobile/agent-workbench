#!/usr/bin/env bash
# test_install_alias.sh — B4 (audit 2026-10-09): quick-install.sh promises a STABLE symlink
# (~/.universal-agent-devkit -> the checkout) so projects keep working when the checkout moves.
# install.sh, the adapters and agent-config.py resolved the kit with `pwd -P` and wrote the
# checkout's real path into every link: install through the alias, move the checkout, re-point
# the alias → every hook exited 127 and ~100 links dangled. Links now go through the alias.
# Also: a later run through the REAL path still owns those links (no project-tier "backups" of
# DevKit links), uninstall removes them, and a self-install through the alias stays a self-install.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export DEVKIT_LANG=en

SRC_DEVKIT="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-alias.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# The quick-install layout: a checkout holding the kit, and a stable alias pointing at it.
mkdir -p "$TMP/repo/universal-agent-devkit"
(cd "$SRC_DEVKIT" && tar --exclude=./node_modules --exclude=./.git -cf - .) | (cd "$TMP/repo/universal-agent-devkit" && tar -xf -)
ALIAS="$TMP/alias"
ln -s "$TMP/repo/universal-agent-devkit" "$ALIAS"

P="$TMP/proj"
mkdir -p "$P" && (cd "$P" && git init -q && git config user.email t@t && git config user.name t \
  && git config commit.gpgsign false && echo x > a && git add a && git commit -qm init)
dangling() { find "$P" -path "$P/.git" -prune -o -type l ! -exec test -e {} \; -print | wc -l | xargs; }
into_kit() { # links in the project whose real target is inside the kit (at its current place)
  python3 - "$P" "$(cd "$ALIAS" && pwd -P)" <<'PY'
import os, sys
p, kit = sys.argv[1], sys.argv[2]
n = 0
for root, dirs, files in os.walk(p):   # a link to a folder is listed in dirs, never entered
    for name in dirs + files:
        f = os.path.join(root, name)
        if os.path.islink(f) and (os.path.realpath(f) + os.sep).startswith(kit + os.sep):
            n += 1
    dirs[:] = [d for d in dirs if d != ".git"]
print(n)
PY
}

bash "$ALIAS/bin/agent-kit" init "$P" -y -p game -a all --no-githooks > "$TMP/i1.out" 2>&1 \
  && ok "install through the alias: exit 0" || { fail "install through the alias failed"; tail -5 "$TMP/i1.out"; }
[ "$(readlink "$P/.agents/devkit")" = "$ALIAS" ] && ok ".agents/devkit points at the alias" \
  || fail ".agents/devkit -> $(readlink "$P/.agents/devkit") (not the alias $ALIAS)"
[ -e "$P/.claude/hooks/validate-assets.sh" ] && [ -e "$P/.agents/active-profile/profile.json" ] \
  && ok "profile links (active-profile, game hook) resolve" || fail "profile links broken right after install"
[ "$(dangling)" = 0 ] && ok "no dangling link after the install" || fail "$(dangling) dangling links right after install"

# Move the checkout, re-point the alias (what a user does after relocating ~/.agent-workbench).
mv "$TMP/repo" "$TMP/repo-moved"
ln -sfn "$TMP/repo-moved/universal-agent-devkit" "$ALIAS"
n="$(dangling)"
if [ "$n" = 0 ]; then ok "checkout moved, alias re-pointed: no dangling link"
else fail "checkout moved, alias re-pointed: $n dangling links:"; find "$P" -path "$P/.git" -prune -o -type l ! -exec test -e {} \; -print | sed "s|$P/||" | head -5; fi
[ -f "$P/.agents/devkit/rules/essentials.md" ] && [ -e "$P/.claude/hooks/session_context.sh" ] \
  && [ -f "$P/.agents/skills/qc/SKILL.md" ] && [ -f "$P/.claude/commands/qc.md" ] \
  && ok "the DevKit, hooks, skills and commands are reachable after the move" || fail "DevKit not reachable after the move"

# A later run through the REAL path recognises the alias links as the DevKit's own.
REAL="$TMP/repo-moved/universal-agent-devkit"
bash "$REAL/bin/install.sh" -t "$P" -y --no-githooks > "$TMP/i2.out" 2>&1 || { fail "re-init through the real path failed"; tail -5 "$TMP/i2.out"; }
[ ! -e "$P/.agents/local/hooks" ] && [ ! -e "$P/.agents/local/commands" ] && [ ! -e "$P/.agents/local/skills" ] \
  && ! grep -q "PROJECT TIER\|X_old" "$TMP/i2.out" \
  && [ -z "$(find "$P" -path "$P/.git" -prune -o \( -name '*_old' -o -name '*_old.*' -o -name '*_old_*' \) -print)" ] \
  && ok "re-init through the real path: alias links are the DevKit's (no project-tier copies, no *_old)" \
  || { fail "re-init through the real path treated DevKit links as the user's:"; ls "$P/.agents/local" 2>&1 | head -5; }

# Uninstall (through the alias) after an alias install leaves no link into the kit.
bash "$ALIAS/bin/agent-kit" init "$P" -y --no-githooks > /dev/null 2>&1
bash "$ALIAS/bin/agent-kit" uninstall "$P" --apply > "$TMP/u.out" 2>&1
n="$(into_kit)"
[ "$n" = 0 ] && [ ! -L "$P/.agents/devkit" ] && ok "uninstall removes every alias link (.agents/devkit included)" \
  || fail "uninstall left $n links into the kit (.agents/devkit: $(readlink "$P/.agents/devkit" 2>/dev/null))"

# A self-install through the alias is still a self-install: no .agents/devkit link inside the kit.
bash "$ALIAS/bin/install.sh" -t "$ALIAS" -y -p universal -a claude --no-githooks > "$TMP/s.out" 2>&1
[ ! -e "$REAL/.agents/devkit" ] && [ ! -L "$REAL/.agents/devkit" ] && grep -q "Target Project:  $REAL" "$TMP/s.out" \
  && ok "self-install through the alias: treated as the DevKit itself" || { fail "self-install through the alias treated the kit as a project"; grep "Target Project" "$TMP/s.out"; }

if [ "$FAILS" -ne 0 ]; then echo "install through alias: $FAILS FAILED"; exit 1; fi
echo "install through alias: all checks passed"
