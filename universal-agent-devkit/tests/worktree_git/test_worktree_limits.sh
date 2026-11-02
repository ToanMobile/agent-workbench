#!/usr/bin/env bash
# W1 R5c (docs/workflow-improvements.md I.0): `agent-kit worktree add` keeps the disk within bounds. Under
# WORKTREE_DISK_WARN_GIB (10) free it runs `worktree gc` first and warns; under WORKTREE_DISK_MIN_GIB (3) it creates nothing
# (exit 4, no folder, no registration). #607: there is no count of worktrees. SessionStart says the disk is low. The disk is measured for real: a threshold above this host's free space drives each case.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WT="$DEVKIT_DIR/scripts/git/worktree.py"
HOOK="$DEVKIT_DIR/hooks/session_context.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
repo() { mkdir -p "$TMP/$1" && G "$TMP/$1" init -q -b main . && echo base > "$TMP/$1/app.txt" && G "$TMP/$1" add -A && G "$TMP/$1" commit -qm base; }
add() {   # add <repo> <name> [-u VAR | VAR=value]: run `worktree add` from the repo, its output in $TMP/out, its exit code returned
  local r="$1" n="$2"; shift 2
  (cd "$TMP/$r" && env "$@" WORKTREE_DISK_WARN_GIB=0 WORKTREE_DISK_MIN_GIB=0 python3 "$WT" add "$TMP/$r-$n" --no-init > "$TMP/out" 2>&1)
}
linked() { G "$TMP/$1" worktree list --porcelain | grep -c '^worktree ' | awk '{print $1 - 1}'; }

# 1 #607: no count of worktrees, whatever WORKTREE_MAX says (only the disk floor guards); a merge-train scratch and subagent worktrees
#   filled the old default of 3 and refused every manual add
repo off; for n in a b c d; do add off "$n" -u WORKTREE_MAX || fail "#607: add $n refused with WORKTREE_MAX unset (rc $?): $(cat "$TMP/out")"; done
add off e WORKTREE_MAX=1 || fail "#607: add e refused with a leftover WORKTREE_MAX=1 (rc $?): $(cat "$TMP/out")"
[ "$(linked off)" = 5 ] && ok "#607: no cap on the number of worktrees (five, WORKTREE_MAX unset or 1)" || fail "#607: $(linked off) of 5 worktrees"

# 5 the disk floor: under WORKTREE_DISK_MIN_GIB nothing is created (exit 4), the free space is named
repo disk
(cd "$TMP/disk" && env WORKTREE_DISK_MIN_GIB=100000 WORKTREE_DISK_WARN_GIB=0 python3 "$WT" add "$TMP/disk-full" --no-init > "$TMP/out" 2>&1); rc=$?
if [ "$rc" = 4 ] && [ ! -e "$TMP/disk-full" ] && [ "$(linked disk)" = 0 ] && grep -q "GiB" "$TMP/out"; then
  ok "under the disk floor: refused (exit 4), no folder, no registration"
else
  fail "disk floor: rc=$rc linked=$(linked disk): $(cat "$TMP/out")"
fi
# 6 under the warning line: gc runs first (a bookkeeping-only leftover goes, logged), a warning, the worktree is created
mkdir -p "$TMP/disk-gate-orphan/.claude/audit-gate" && echo log > "$TMP/disk-gate-orphan/.claude/audit-gate/run.log"
(cd "$TMP/disk" && env WORKTREE_DISK_WARN_GIB=100000 WORKTREE_DISK_MIN_GIB=0 WORKTREE_GC_MIN_AGE_S=0 python3 "$WT" add "$TMP/disk-ok" --no-init > "$TMP/out" 2>&1); rc=$?
if [ "$rc" = 0 ] && [ -d "$TMP/disk-ok" ] && [ ! -e "$TMP/disk-gate-orphan" ] && grep -q "GiB" "$TMP/out" \
    && grep -q "disk-gate-orphan" "$TMP/disk/.claude/audit-gate/worktree_gc.log" 2>/dev/null; then
  ok "under the warning line: gc ran (the leftover deleted and logged), a warning, the worktree created"
else
  fail "disk warning: rc=$rc orphan=$([ -e "$TMP/disk-gate-orphan" ] && echo kept || echo gone): $(cat "$TMP/out")"
fi

# 7 SessionStart names a low disk once, and says nothing when there is room
ctx() { printf '{"session_id":"lim","hook_event_name":"SessionStart"}' | env SESSION_FETCH=0 WORKTREE_GC=0 "$@" CLAUDE_PROJECT_DIR="$TMP/disk" bash "$HOOK" 2>/dev/null; }
out="$(ctx WORKTREE_DISK_WARN_GIB=100000)"
echo "$out" | grep -q "GiB" && ok "SessionStart warns when the disk is under the warning line" || fail "no SessionStart disk warning: $out"
out="$(ctx WORKTREE_DISK_WARN_GIB=0 WORKTREE_DISK_MIN_GIB=100000)"
echo "$out" | grep -q "GiB" && ok "  … and under the floor with the warning line off" || fail "no SessionStart line under the floor (warning off): $out"
echo "$out" | grep -q "đang dọn nền" && fail "SessionStart claims a background gc it does not know runs (WORKTREE_GC=0 here): $out" || ok "  … without claiming a background gc it does not know runs"
out="$(ctx WORKTREE_DISK_WARN_GIB=1 WORKTREE_DISK_MIN_GIB=1)"
echo "$out" | grep -q "GiB" && fail "SessionStart warned with room on the disk: $out" || ok "  … and stays quiet when there is room"

echo
[ "$FAILS" -eq 0 ] && { echo "test_worktree_limits: PASS"; exit 0; } || { echo "test_worktree_limits: FAIL ($FAILS)"; exit 1; }
