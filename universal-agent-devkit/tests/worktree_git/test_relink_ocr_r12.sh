#!/usr/bin/env bash
# Regression test (OCR r12, 26/10, #443): relink_check on layouts the installer does not make.
#  a. a kit with no skills/ dir: rc 0 (os.listdir raised).
#  b. `.claude -> <kit>/.claude`: missing() wrote links into the kit.
#  c. `.claude/commands -> ../shared` (a folder inside the project): missing() and dangling() skipped it, the repo never healed.
#  d. `git rm -r .claude/commands`: nobody rebuilt the links.
#  e. a FileExistsError race is not counted as a restored link.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en DEVKIT_INCIDENT=0
unset DEVKIT_RELINK
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

mkkit() {   # $1 dir, $2 = with-skills | no-skills; one command (a.md) the project may lack
  local K="$1"; mkdir -p "$K/profiles" "$K/commands" "$K/scripts/governance" "$K/rules" "$K/.claude/commands"
  echo r > "$K/rules/essentials.md"; echo c > "$K/commands/a.md"; : > "$K/scripts/governance/context_sync.py"
  cp "$DEVKIT_DIR/scripts/governance/relink_check.py" "$K/scripts/governance/relink_check.py"
  [ "$2" = with-skills ] && { mkdir -p "$K/skills/s1"; echo s > "$K/skills/s1/SKILL.md"; }
  return 0
}
mkproj() {   # $1 kit, $2 dir
  local P="$2"; mkdir -p "$P/.claude" "$P/.agents/context"; git -C "$P" init -q -b main
  echo '{}' > "$P/.agents/active-profile.json"; echo '{}' > "$P/.claude/settings.json"; ln -s "$1" "$P/.agents/devkit"
}

# a. kit without skills/
K="$TMP/a/kit"; P="$TMP/a/p"; mkdir -p "$TMP/a"; mkkit "$K" no-skills; mkproj "$K" "$P"; mkdir -p "$P/.claude/commands" "$P/.agents/skills"
python3 "$K/scripts/governance/relink_check.py" "$P" --quiet; rc=$?
[ "$rc" -eq 0 ] && ok "a: kit without skills/ exits 0" || fail "a: rc=$rc"

# b. .claude -> <kit>/.claude
K="$TMP/b/kit"; P="$TMP/b/p"; mkdir -p "$TMP/b" "$P/.agents/context"; mkkit "$K" with-skills; git -C "$P" init -q -b main
echo '{}' > "$P/.agents/active-profile.json"; ln -s "$K" "$P/.agents/devkit"; ln -s "$K/.claude" "$P/.claude"; mkdir -p "$P/.agents/skills"
python3 "$K/scripts/governance/relink_check.py" "$P" --quiet
[ -z "$(ls -A "$K/.claude/commands")" ] && [ ! -e "$K/.claude/commands/a.md" ] \
  && ok "b: nothing written into the kit through a symlinked .claude" || fail "b: kit got links: $(ls "$K/.claude/commands")"

# c. .claude/commands -> ../shared (inside the project): missing link restored, dangling kit link pruned
K="$TMP/c/kit"; P="$TMP/c/p"; mkdir -p "$TMP/c"; mkkit "$K" with-skills; mkproj "$K" "$P"
mkdir -p "$P/shared"; ln -s "$K/commands/zz-gone.md" "$P/shared/zz-gone.md"; ln -s ../shared "$P/.claude/commands"
python3 "$K/scripts/governance/relink_check.py" "$P" --quiet
[ -L "$P/shared/a.md" ] && [ ! -L "$P/shared/zz-gone.md" ] && ok "c: a link dir symlinked inside the project heals" \
  || fail "c: shared holds: $(ls -A "$P/shared" | tr '\n' ' ')"

# d. the whole link dir removed
K="$TMP/d/kit"; P="$TMP/d/p"; mkdir -p "$TMP/d"; mkkit "$K" with-skills; mkproj "$K" "$P"
python3 "$K/scripts/governance/relink_check.py" "$P" --quiet
[ -L "$P/.claude/commands/a.md" ] && ok "d: .claude/commands rebuilt after it was removed whole" || fail "d: commands dir not rebuilt"

# e. a FileExistsError race is not a restored link
K="$TMP/e/kit"; P="$TMP/e/p"; mkdir -p "$TMP/e"; mkkit "$K" with-skills; mkproj "$K" "$P"; mkdir -p "$P/.claude/commands"
out="$(python3 - "$K/scripts/governance" "$P" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1]); import relink_check as r
def boom(*a, **k): raise FileExistsError
os.symlink = boom
left, raced = [], []
res = r.relink(sys.argv[2], [".claude/commands/a.md"], raced)
print(len(res), len(raced))
PY
)"
[ "$out" = "0 1" ] && ok "e: the race is reported apart from the restored links" || fail "e: relink returned '$out'"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
