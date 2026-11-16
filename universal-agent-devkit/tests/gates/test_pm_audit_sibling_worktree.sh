#!/usr/bin/env bash
# A PM audit task opened for a linked worktree that is a SIBLING of the main checkout (agent-kit worktree add ../<name>) counts for
# the repo (same git-common-dir). A worktree of another repo, a plain dir and a missing path do not.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm" DEVKIT_PM_HOME_TEST=1 GIT_CONFIG_GLOBAL=/dev/null
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
mkrepo() { mkdir -p "$1" && git -C "$1" init -q -b main . && git -C "$1" config user.email t@t && git -C "$1" config user.name t \
  && git -C "$1" config commit.gpgsign false && echo a > "$1/a" && git -C "$1" add -A && git -C "$1" commit -qm m0; }
mkdir -p "$TMP/w"
mkrepo "$TMP/w/main"; mkrepo "$TMP/w/other"
git -C "$TMP/w/main" worktree add -q -b feat "$TMP/w/sib" 2>&1
git -C "$TMP/w/other" worktree add -q -b feat "$TMP/w/othersib" 2>&1
mkdir -p "$TMP/w/plain"
echo b > "$TMP/w/sib/b"; git -C "$TMP/w/sib" add -A; git -C "$TMP/w/sib" commit -qm pr
HEAD="$(git -C "$TMP/w/sib" rev-parse HEAD)"
task() {   # task <id> <project>
  mkdir -p "$TMP/pm/projects/p-$1/tasks/$1"
  python3 - "$TMP/pm/projects/p-$1/tasks/$1/task.json" "$1" "$2" "$HEAD" <<'PY'
import json, sys
dest, tid, proj, head = sys.argv[1:5]
json.dump({"id": tid, "project": proj, "dispatches": [], "verdicts": {"audit": {"verdict": "pass", "round": 1, "reviewer": "antigravity",
  "auditedHead": head}, "auditHistory": [{"auditedHead": head, "reviewer": "antigravity", "at": "2026-11-04T00:00:01Z"}]}}, open(dest, "w"))
PY
}
task TA "$TMP/w/sib"; task TB "$TMP/w/othersib"; task TC "$TMP/w/plain"; task TD "$TMP/w/missing"
OUT="$(PYTHONPATH="$DEVKIT_DIR/bin" python3 -c "
import push_gate as g
print(' '.join(sorted(t for t, h in g.audited_heads('$TMP/w/main'))))
print(' '.join(sorted(t for t, h in g.audited_heads('$TMP/w/sib'))))" 2>&1)"
echo "$OUT"
MAIN="$(printf '%s\n' "$OUT" | sed -n 1p)"; SIB="$(printf '%s\n' "$OUT" | sed -n 2p)"
[ "$MAIN" = "TA" ] && ok "A: sibling worktree of the same repo is seen from the main checkout" || bad "A: main sees '$MAIN'"
[ "$SIB" = "TA" ] && ok "A2: and from the sibling worktree itself" || bad "A2: sibling sees '$SIB'"
case "$MAIN" in *TB*) bad "B: worktree of a different repo accepted";; *) ok "B: different repo's worktree ignored";; esac
case "$MAIN" in *TC*|*TD*) bad "C: plain/missing dir accepted";; *) ok "C: plain dir and missing path ignored";; esac
[ "$FAILS" = 0 ]
