#!/usr/bin/env bash
# W1 R5c (docs/workflow-improvements.md I.0): `agent-kit worktree add` keeps the disk and the repo within bounds. Under
# WORKTREE_DISK_WARN_GIB (10) free it runs `worktree gc` first and warns; under WORKTREE_DISK_MIN_GIB (3) it creates nothing;
# at most WORKTREE_MAX (3) linked worktrees per repo — a red_proof sandbox (red-proof-*) and a registration whose folder is gone do
# not count, and two adds racing for the last slot never both get it. A refusal exits 4 and leaves no folder and no registration.
# SessionStart says the disk is low. The disk is measured for real: a threshold above this host's free space drives each case.
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

# 1 the cap: three worktrees, the fourth refused (exit 4, no folder, no registration, the existing ones named)
repo main
for n in w1 w2; do add main "$n" -u WORKTREE_MAX || fail "setup: add $n ($(cat "$TMP/out"))"; done
G "$TMP/main" worktree add -q --detach "$TMP/red-proof-abc"   # a red_proof sandbox (tempfile red-proof-*): lives a few seconds, never counts
add main w3 -u WORKTREE_MAX; rc=$?
[ "$rc" = 0 ] && ok "a red_proof sandbox does not count: the third worktree is created" || fail "third worktree refused next to a red-proof box (rc $rc): $(cat "$TMP/out")"
add main w4 -u WORKTREE_MAX; rc=$?
if [ "$rc" = 4 ] && [ ! -e "$TMP/main-w4" ] && ! G "$TMP/main" worktree list | grep -q "main-w4" && grep -q "main-w1" "$TMP/out" && grep -qE "tối đa 3|at most 3" "$TMP/out"; then
  ok "the fourth worktree is refused (exit 4, nothing created, the three named)"
else
  fail "fourth worktree: rc=$rc exists=$([ -e "$TMP/main-w4" ] && echo yes || echo no): $(cat "$TMP/out")"
fi
# 2 a registration whose folder is gone (prunable) does not hold a slot
rm -rf "$TMP/main-w3"
add main w5 -u WORKTREE_MAX; rc=$?
[ "$rc" = 0 ] && ok "a worktree whose folder is gone frees its slot" || fail "prunable worktree still counted (rc $rc): $(cat "$TMP/out")"
add main w6 -u WORKTREE_MAX; rc=$?
[ "$rc" = 4 ] && ok "  … and the cap holds again at three (exit 4)" || fail "cap not enforced after the prunable one (rc $rc)"
# 3 WORKTREE_MAX=1 lowers it, 0 lifts it, a fraction is no number of worktrees (the default)
add main w7 WORKTREE_MAX=0; rc=$?
[ "$rc" = 0 ] && ok "WORKTREE_MAX=0: no cap" || fail "WORKTREE_MAX=0 still capped (rc $rc): $(cat "$TMP/out")"
repo lo; add lo a WORKTREE_MAX=1 || fail "setup: lo-a"
add lo b WORKTREE_MAX=1; rc=$?
[ "$rc" = 4 ] && ok "WORKTREE_MAX=1: the second is refused" || fail "WORKTREE_MAX=1 not enforced (rc $rc)"
add lo c WORKTREE_MAX=0.5 || fail "setup: lo-c under the default cap of 3"
add lo d WORKTREE_MAX=0.5 || fail "setup: lo-d under the default cap of 3"
add lo e WORKTREE_MAX=0.5; rc=$?
[ "$rc" = 4 ] && ok "WORKTREE_MAX=0.5 is not 0 (off): the default cap of 3 holds" || fail "WORKTREE_MAX=0.5 lifted the cap (rc $rc)"

# 4 six adds at once with room for three: exactly three get a worktree (the count and `git worktree add` share one lock)
repo race
for i in 1 2 3 4 5 6; do
  (cd "$TMP/race" && env -u WORKTREE_MAX WORKTREE_DISK_WARN_GIB=0 WORKTREE_DISK_MIN_GIB=0 python3 "$WT" add "$TMP/race-r$i" --no-init > "$TMP/race.$i" 2>&1; echo $? > "$TMP/race.$i.rc") &
done
wait
won=0; lost4=0; for i in 1 2 3 4 5 6; do case "$(cat "$TMP/race.$i.rc")" in 0) won=$((won + 1)) ;; 4) lost4=$((lost4 + 1)) ;; esac; done
[ "$won" = 3 ] && [ "$lost4" = 3 ] && [ "$(linked race)" = 3 ] && ok "six racing adds: exactly three worktrees, the other three refused for the cap (exit 4)" \
  || fail "six racing adds: $won succeeded, $lost4 refused with exit 4, $(linked race) registered"
# 4b a lock a killed add left behind (review 14/10: two waiters both took over a dead holder's O_EXCL file, 4 in 25 runs went past the cap)
over=0
for k in 1 2 3 4 5 6 7 8 9 10; do
  repo "st$k"; printf '{"pid": 999999, "at": %s}\n' "$(date +%s)" > "$TMP/st$k/.git/devkit-worktree-add.lock"
  for i in 1 2 3 4 5 6 7 8; do
    (cd "$TMP/st$k" && env WORKTREE_MAX=1 WORKTREE_DISK_WARN_GIB=0 WORKTREE_DISK_MIN_GIB=0 python3 "$WT" add "$TMP/st$k-r$i" --no-init > /dev/null 2>&1; echo $? > "$TMP/st$k.$i.rc") &
  done
  wait
  bad=0; for i in 1 2 3 4 5 6 7 8; do case "$(cat "$TMP/st$k.$i.rc")" in 0|4) ;; *) bad=1 ;; esac; done
  { [ "$(linked "st$k")" = 1 ] && [ "$bad" = 0 ]; } || over=$((over + 1))
done
[ "$over" = 0 ] && ok "a stale lock left by a killed add: still one worktree per slot, every loser exit 4 (10 runs)" || fail "stale lock: $over of 10 runs went past the cap or refused wrongly"

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
