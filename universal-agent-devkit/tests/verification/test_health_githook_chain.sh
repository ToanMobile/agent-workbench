#!/usr/bin/env bash
# Regression (workflow audit 2026-10-04): `agent-kit health` scored 100/100 while OfficeReader's own
# .githooks/pre-commit never called the DevKit gate, so no Office commit saw the static checks. The kit
# prints the chain line on install but nothing counted a project hook that leaves it out.
#  1. githooks.sh state: one word for tools — installed | chained | project-unchained | absent
#     (the SAME detection `status` uses, not a second regex).
#  2. agent-health's git_gate_wiring: an unchained project hook is a failed check; installed / chained pass;
#     no hook at all (e.g. --no-githooks) is information only and does not move the score.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GH="$DEVKIT_DIR/scripts/git/githooks.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
repo() { R="$TMP/$1"; mkdir -p "$R" && git -C "$R" init -q . && git -C "$R" config user.email t@t && git -C "$R" config user.name t; }
state() { bash "$GH" state "$TMP/$1" 2>/dev/null; }

repo none;    s="$(state none)"
[ "$s" = absent ] && ok "no pre-commit hook → absent" || fail "no hook: '$s'"
repo ours;    bash "$GH" install "$TMP/ours" >/dev/null 2>&1; s="$(state ours)"
[ "$s" = installed ] && ok "githooks install → installed" || fail "after install: '$s'"
repo chain;   mkdir -p "$TMP/chain/.git/hooks"
printf '#!/bin/bash\nbash "$HOME/kit/scripts/git/git-pre-commit.sh" "$@" || exit 1\nexit 0\n' > "$TMP/chain/.git/hooks/pre-commit"; chmod +x "$TMP/chain/.git/hooks/pre-commit"
s="$(state chain)"; [ "$s" = chained ] && ok "a project hook that calls the DevKit gate → chained" || fail "chained hook: '$s'"
repo loose;   mkdir -p "$TMP/loose/.git/hooks"
printf '#!/bin/bash\nexit 0\n' > "$TMP/loose/.git/hooks/pre-commit"; chmod +x "$TMP/loose/.git/hooks/pre-commit"
s="$(state loose)"; [ "$s" = project-unchained ] && ok "a project hook without the DevKit gate → project-unchained" || fail "unchained hook: '$s'"
repo noexec;  bash "$GH" install "$TMP/noexec" >/dev/null 2>&1; chmod -x "$TMP/noexec/.git/hooks/pre-commit"; s="$(state noexec)"
[ "$s" = project-unchained ] && ok "a DevKit stub without the executable bit (git ignores it) → not installed" || fail "non-executable stub: '$s'"
repo cmt;     mkdir -p "$TMP/cmt/.git/hooks"
printf '#!/bin/bash\n# bash "$HOME/kit/scripts/git/git-pre-commit.sh" "$@" || exit 1\nexit 0\n' > "$TMP/cmt/.git/hooks/pre-commit"; chmod +x "$TMP/cmt/.git/hooks/pre-commit"
s="$(state cmt)"; [ "$s" = project-unchained ] && ok "a chain line that only sits in a comment → project-unchained" || fail "commented chain: '$s'"
repo hp;      mkdir -p "$TMP/hp/.githooks"; printf '#!/bin/bash\nexec bash scripts/qa/pre_commit_gate.sh\n' > "$TMP/hp/.githooks/pre-commit"; chmod +x "$TMP/hp/.githooks/pre-commit"
git -C "$TMP/hp" config core.hooksPath .githooks
s="$(state hp)"; [ "$s" = project-unchained ] && ok "core.hooksPath=.githooks, project hook without the gate (OfficeReader) → project-unchained" || fail "hooksPath case: '$s'"

# agent-health.py: the check built on the same word
out="$(DK="$DEVKIT_DIR" TMPD="$TMP" python3 - <<'PY' 2>&1
import importlib.util, io, os, contextlib
from pathlib import Path
spec = importlib.util.spec_from_file_location("health", os.path.join(os.environ["DK"], "bin", "agent-health.py"))
h = importlib.util.module_from_spec(spec); spec.loader.exec_module(h)
def run(name):
    sc = h.Score()
    with contextlib.redirect_stdout(io.StringIO()):
        h.git_gate_wiring(Path(os.environ["TMPD"]) / name, sc)
    return sc.passed, sc.total
for name in ("ours", "chain", "loose", "hp", "none", "noexec", "cmt"):
    print(name, *run(name))
PY
)"
chk() { echo "$out" | grep -qx "$1" && ok "$2" || fail "$2 (got: $(echo "$out" | grep "^${1%% *} " | head -1))"; }
chk "ours 1 1"  "health: the DevKit hook passes"
chk "chain 1 1" "health: a project hook that chains the gate passes"
chk "loose 0 1" "health: an unchained project hook FAILS the check"
chk "hp 0 1"    "health: the OfficeReader shape (.githooks without the gate) FAILS the check"
chk "none 0 0"  "health: no hook at all is information only (score unchanged)"
chk "noexec 0 1" "health: a stub git ignores FAILS the check"
chk "cmt 0 1"    "health: a commented-out chain FAILS the check"

[ "$FAILS" -eq 0 ] && echo "health git hook chain: all checks passed" || { echo "health git hook chain: $FAILS FAILED"; exit 1; }
