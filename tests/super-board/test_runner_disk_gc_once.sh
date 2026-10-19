#!/usr/bin/env bash
# Test hồi quy (OCR batch 19/10, MEDIUM): dưới sàn đĩa, `worktree_disk_room` của runner gọi `_make_room` (một `worktree gc` đầy đủ)
# mỗi lần một lane định giao thẻ — tới 3 lần mỗi tick, tick này qua tick khác, dù lần gc trước không giải phóng được gì.
# Luật ở đây:
#  1. dưới sàn, gc chạy MỘT lần rồi nghỉ 300 s (cố định, không có biến môi trường); trong lúc nghỉ chỉ đọc dung lượng trống (rẻ), vẫn từ chối giao.
#  2. người dùng dọn đĩa trong lúc nghỉ: lần kiểm kế tiếp thấy có chỗ ngay, không phải chờ hết thời gian nghỉ.
#  3. hết thời gian nghỉ mà vẫn dưới sàn: gc chạy lại một lần.
# DevKit giả: worktree.py chỉ có free_gib / DISK_MIN_GIB / _make_room, đếm số lần gc. Chạy offline. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-disk-gc.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/.agents/devkit/scripts/git"
cat > "$TMP/repo/.agents/devkit/scripts/git/worktree.py" <<'PY'
import os
DISK_MIN_GIB = 3.0
def free_gib(path):
    return float(os.environ.get("FAKE_FREE_GIB", "1"))
def _make_room(main, wt):
    with open(os.environ["FAKE_GC_LOG"], "a") as f:
        f.write("gc\n")
    if free_gib(wt) < DISK_MIN_GIB:
        raise SystemExit(4)   # NO_ROOM, as the DevKit's _make_room
PY
export FAKE_GC_LOG="$TMP/gc.log" PYTHONDONTWRITEBYTECODE=1
: > "$FAKE_GC_LOG"

SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
log() { echo "$*" >> "$TMP/log"; }
REPO_ROOT="$TMP/repo"
gcs() { grep -c gc "$FAKE_GC_LOG" 2>/dev/null || true; }

# ── 1. under the floor: three lanes in one tick, then the next tick — one gc, every check refuses
export FAKE_FREE_GIB=1
r=""
for lane in review qa build review qa build; do worktree_disk_room "$REPO_ROOT/.claude/worktrees/issue-5-$lane"; r="$r $?"; done
[ "$(gcs)" = 1 ] && ok "under the floor: one worktree gc for six checks (two ticks of three lanes)" || fail "gc ran $(gcs) times for six checks"
case "$r" in *" 0"*) fail "a check under the floor said there was room:$r" ;; *) ok "  … and every check still refuses to dispatch" ;; esac
d=$(( ${DISK_GC_NEXT:-0} - $(date +%s) ))
[ "$d" -ge 295 ] && [ "$d" -le 300 ] && ok "  … and the rest ends ~300 s after that gc" || fail "rest ends in ${d}s, want ~300"

# ── 2. space freed by hand during the pause: room at once, no gc
export FAKE_FREE_GIB=50
worktree_disk_room "$REPO_ROOT/.claude/worktrees/issue-6-build"; rc=$?
[ "$rc" = 0 ] && [ "$(gcs)" = 1 ] && ok "space freed during the pause: room at the next check, without a gc" || fail "freed space: rc $rc, gc $(gcs)"
export FAKE_FREE_GIB=1   # back under the floor soon after: the old rest is gone, its gc runs at once
worktree_disk_room "$REPO_ROOT/.claude/worktrees/issue-6-build"; rc=$?
[ "$rc" != 0 ] && [ "$(gcs)" = 2 ] && ok "  … and a new fall under the floor gets its own gc at once (the rest was cleared)" || fail "fall after room: rc $rc, gc $(gcs)"

# ── 3. the pause is over and the disk is still full: one more gc
export FAKE_FREE_GIB=1
DISK_GC_NEXT=$(( $(date +%s) - 1 ))   # the 300 s rest has passed
worktree_disk_room "$REPO_ROOT/.claude/worktrees/issue-7-build"; rc=$?
[ "$rc" != 0 ] && [ "$(gcs)" = 3 ] && ok "after the pause, still under the floor: gc runs again (once)" || fail "after the pause: rc $rc, gc $(gcs)"

# ── 4. under the runner's own `set -euo pipefail`, called as dispatch_lane calls it: the check never ends the run loop, and the rest
#    is a fixed 300 s — no environment knob (review 19/10: `5m` / `08` in a knob ended the whole loop as "finished")
( set -euo pipefail; DISK_GC_NEXT=0; export SB_DISK_GC_BACKOFF_S=08
  if ! worktree_disk_room "$REPO_ROOT/.claude/worktrees/issue-9-build"; then :; fi
  echo "survived $(( DISK_GC_NEXT - $(date +%s) ))" ) > "$TMP/strict.out" 2>&1
grep -Eq "^survived (29[5-9]|300)$" "$TMP/strict.out" && ok "strict mode: the check goes on and rests a fixed 300 s (a stray knob is ignored)" \
  || fail "strict mode: $(tail -1 "$TMP/strict.out")"

[ "$FAILS" -eq 0 ] && echo "✅ test_runner_disk_gc_once: all passed" || { echo "❌ test_runner_disk_gc_once: $FAILS failed"; exit 1; }
