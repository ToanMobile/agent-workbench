#!/usr/bin/env bash
# Regression test (issue #363, extra AC): the fallback path that `agent-kit githooks install` writes into .git/hooks/* (shared by every
# worktree) must outlive a worktree, and SessionStart heal must repair a hook whose fallback points at a path that no longer exists
# (24/10: install ran in the worktree issue-316-build, the worktree was removed, every commit and merge through the hooks failed).
#   1 install from a linked worktree, remove the worktree: every fallback path still exists (the main checkout's kit; commit 74586478)
#   2 a hook whose fallback path is gone (the kit it was installed from moved away): `worktree heal` rewrites it, the paths exist again
#   3 heal leaves alone a hook that is fine, a project's own (foreign) hook, and a repo with no DevKit hook at all
# Every case runs in a scratch repo with a fake kit copy (never the real hooks). bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export DEVKIT_LANG=en
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WTPY="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
GITHOOKS_SRC="${GITHOOKS_SRC:-$DEVKIT_DIR/scripts/git/githooks.sh}"   # overridable: the RED run uses the version before #376

mkkit() { # <dir>: a kit copy holding what githooks.sh install needs
  local k="$1" f
  mkdir -p "$k/profiles" "$k/scripts/git" "$k/scripts/governance"; touch "$k/profiles/.keep"
  for f in scripts/git/git-pre-commit.sh scripts/git/git-commit-msg.sh scripts/governance/i18n.sh scripts/governance/relink_check.py; do
    cp "$DEVKIT_DIR/$f" "$k/$f" || fail "fixture: cannot copy $f"
  done
  cp "$GITHOOKS_SRC" "$k/scripts/git/githooks.sh"
}
# every absolute fallback path the DevKit stubs in <hooks dir> name (the `VAR=<path>` lines after the repo-relative lookups)
fallbacks() { grep -hE '^\[ -f "\$(DEVKIT_HOOK|RELINK)" \] \|\| (DEVKIT_HOOK|RELINK)=/' "$1"/* 2>/dev/null | sed -E 's/^.*\|\| (DEVKIT_HOOK|RELINK)=//' | sed -E 's/\\(.)/\1/g'; }
all_exist() { local p n=0; while IFS= read -r p; do [ -n "$p" ] || continue; n=$((n + 1)); [ -f "$p" ] || { echo "missing: $p"; return 1; }; done <<EOF
$(fallbacks "$1")
EOF
  [ "$n" -gt 0 ]; }

# 1) install from a linked worktree, then remove the worktree
M="$TMP/main1"; mkkit "$M/kit"
( cd "$M" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -qm init --no-verify \
  && git worktree add -q "$TMP/wt1" HEAD ) >"$TMP/s1.log" 2>&1 || fail "fixture 1: $(tail -2 "$TMP/s1.log")"
bash "$TMP/wt1/kit/scripts/git/githooks.sh" install "$TMP/wt1" >"$TMP/i1.log" 2>&1
git -C "$M" worktree remove --force "$TMP/wt1" >/dev/null 2>&1
H1="$(git -C "$M" rev-parse --path-format=absolute --git-common-dir)/hooks"
GOT="$(all_exist "$H1")"; rc=$?
[ "$rc" = 0 ] && ok "1: hooks installed from a worktree: after the worktree is removed every fallback path still exists" \
  || fail "1: a fallback outlived its worktree: $GOT ($(tail -2 "$TMP/i1.log" | tr '\n' ' '))"

# 2) a fallback path that is gone: heal reinstalls
R="$TMP/repo2"; mkkit "$TMP/kit2"; mkdir -p "$R"
( cd "$R" && git init -q . && git config user.email t@t && git config user.name t && echo a > a.txt && git add -A && git commit -qm init --no-verify ) >/dev/null 2>&1
bash "$TMP/kit2/scripts/git/githooks.sh" install "$R" >"$TMP/i2.log" 2>&1
H2="$(git -C "$R" rev-parse --path-format=absolute --git-path hooks)"
rm -rf "$TMP/kit2"                                   # the kit the hooks were installed from is gone: their fallback dangles
GOT="$(all_exist "$H2")"; [ $? != 0 ] && ok "2 setup: the fallback paths dangle ($GOT)" || fail "2 setup: the fallbacks did not dangle"
( cd "$R" && python3 "$WTPY" heal >"$TMP/h2.log" 2>&1 ); rc=$?
GOT="$(all_exist "$H2")"; rc2=$?
[ "$rc" = 0 ] && [ "$rc2" = 0 ] && [ -x "$H2/pre-commit" ] && grep -q "universal-agent-devkit:githook" "$H2/pre-commit" \
  && ok "2: heal rewrote the hooks: every fallback path exists again, the hook is still the DevKit's and executable" \
  || fail "2: heal did not repair (rc=$rc): $GOT / $(cat "$TMP/h2.log" | tail -3)"

# 3) nothing to repair: a healthy hook is not rewritten, a foreign hook is never touched, no hook means no hook
SUM="$(cat "$H2"/* | cksum)"; ( cd "$R" && python3 "$WTPY" heal >/dev/null 2>&1 )
[ "$(cat "$H2"/* | cksum)" = "$SUM" ] && ok "3: a healthy hook set is left byte for byte as it was" || fail "3: heal rewrote healthy hooks"
F="$TMP/repo3"; mkdir -p "$F"; ( cd "$F" && git init -q . && git config user.email t@t && git config user.name t && echo a > a.txt && git add -A && git commit -qm init --no-verify ) >/dev/null 2>&1
HF="$(git -C "$F" rev-parse --path-format=absolute --git-path hooks)"; mkdir -p "$HF"
printf '#!/bin/sh\n# project hook, mentions universal-agent-devkit only in words\n[ -f "$DEVKIT_HOOK" ] || DEVKIT_HOOK=/gone/git-pre-commit.sh\nexit 0\n' > "$HF/pre-commit"; chmod +x "$HF/pre-commit"
SUM="$(cat "$HF/pre-commit" | cksum)"; ( cd "$F" && python3 "$WTPY" heal >"$TMP/h3.log" 2>&1 )
[ "$(cat "$HF/pre-commit" | cksum)" = "$SUM" ] && ! grep -qi "hook" "$TMP/h3.log" && ok "  … a project's own hook (no DevKit marker) is not rewritten, not even attempted or mentioned" || fail "  … heal touched a foreign hook: $(cat "$TMP/h3.log")"
N="$TMP/repo4"; mkdir -p "$N"; ( cd "$N" && git init -q . && git config user.email t@t && git config user.name t && echo a > a.txt && git add -A && git commit -qm init --no-verify ) >/dev/null 2>&1
( cd "$N" && python3 "$WTPY" heal >/dev/null 2>&1 ); HN="$(git -C "$N" rev-parse --path-format=absolute --git-path hooks)"
[ ! -e "$HN/pre-commit" ] && [ ! -e "$HN/commit-msg" ] && ok "  … a repo with no DevKit hook gets none (heal repairs, it does not install)" || fail "  … heal installed hooks into a repo that had none"

# 4) a fallback path that printf %q escapes (a space: `kit\ 5`; a tab: `$'kit\t6'`): heal must read it back the same way, not skip the hook
N5=0
for V in "kit 5" "kit"$'\t'"6"; do
  N5=$((N5 + 1)); R="$TMP/repo5-$N5"; mkdir -p "$R"; mkkit "$TMP/$V"
  ( cd "$R" && git init -q . && git config user.email t@t && git config user.name t && echo a > a.txt && git add -A && git commit -qm init --no-verify ) >/dev/null 2>&1
  bash "$TMP/$V/scripts/git/githooks.sh" install "$R" >"$TMP/i5.log" 2>&1
  H5="$(git -C "$R" rev-parse --path-format=absolute --git-path hooks)"
  Q="$(printf %q "$V")"; Q="${Q#\$\'}"; Q="${Q%\'}"   # how %q wrote the kit folder's name inside the path
  grep -qF "$Q" "$H5/pre-commit" || fail "4 setup: the hook does not carry the escaped path $Q"
  SUM="$(cat "$H5"/* | cksum)"; ( cd "$R" && python3 "$WTPY" heal >/dev/null 2>&1 )
  [ "$(cat "$H5"/* | cksum)" = "$SUM" ] && ok "4: a healthy hook whose kit path needs %q escaping is left alone ($Q)" || fail "4: heal rewrote a healthy hook ($Q)"
  rm -rf -- "$TMP/$V"
  ( cd "$R" && python3 "$WTPY" heal >"$TMP/h5.log" 2>&1 )
  ! grep -qF "$Q" "$H5/pre-commit" && ok "4: a dangling %q-escaped fallback ($Q) is read back and repaired" \
    || fail "4: heal skipped a dangling escaped fallback ($Q): $(tail -2 "$TMP/h5.log")"
done

if [ "$FAILS" -ne 0 ]; then echo "githooks_heal: $FAILS FAILED"; exit 1; fi
echo "githooks_heal: all checks passed"
