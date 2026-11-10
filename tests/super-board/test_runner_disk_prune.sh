#!/usr/bin/env bash
# Test hồi quy (10/11): trước khi giao thẻ, `worktree_disk_room` của runner tỉa cache build khi đĩa dưới CACHE_PRUNE_GIB của DevKit,
# kể cả khi đĩa còn trên sàn và kể cả khi lane dùng lại worktree có sẵn (build worker vẫn build, vẫn tốn đĩa).
#  1. dưới ngưỡng tỉa, trên sàn: tỉa MỘT lần rồi nghỉ 300 s như gc; vẫn giao thẻ.
#  2. worktree lane có sẵn: vẫn tỉa (sau thời gian nghỉ), vẫn giao thẻ, không bao giờ từ chối vì sàn.
#  3. kit cũ không có CACHE_PRUNE_GIB: không lỗi, không cảnh báo, giao thẻ như trước.
# DevKit giả, chạy offline. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-disk-prune.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/.agents/devkit/scripts/git"
KIT="$TMP/repo/.agents/devkit/scripts/git/worktree.py"
cat > "$KIT" <<'PY'
import os
DISK_MIN_GIB = 15.0
CACHE_PRUNE_GIB = 25.0
def free_gib(path):
    return float(os.environ.get("FAKE_FREE_GIB", "1"))
def _prune_caches():
    with open(os.environ["FAKE_LOG"], "a") as f:
        f.write("prune\n")
def _make_room(main, wt):
    with open(os.environ["FAKE_LOG"], "a") as f:
        f.write("gc\n")
    if free_gib(wt) < DISK_MIN_GIB:
        raise SystemExit(4)
PY
export FAKE_LOG="$TMP/fake.log" PYTHONDONTWRITEBYTECODE=1; : > "$FAKE_LOG"
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
log() { echo "$*" >> "$TMP/log"; }
REPO_ROOT="$TMP/repo"
n() { grep -c "^$1\$" "$FAKE_LOG" 2>/dev/null || true; }

# 1 trên sàn, dưới ngưỡng tỉa
export FAKE_FREE_GIB=20
worktree_disk_room "$REPO_ROOT/.claude/worktrees/issue-5-build"; r1=$?
worktree_disk_room "$REPO_ROOT/.claude/worktrees/issue-5-qa"; r2=$?
[ "$r1" = 0 ] && [ "$r2" = 0 ] && [ "$(n prune)" = 1 ] && [ "$(n gc)" = 0 ] \
  && ok "dưới ngưỡng tỉa, trên sàn: tỉa một lần, nghỉ, vẫn giao thẻ" || fail "tỉa: r1=$r1 r2=$r2 prune=$(n prune) gc=$(n gc)"
grep -q '⚠' "$TMP/log" 2>/dev/null && fail "  … có cảnh báo lạ: $(cat "$TMP/log")"

# 2 worktree lane có sẵn
git init -q "$REPO_ROOT/.claude/worktrees/issue-6-build"
DISK_GC_NEXT=0; export FAKE_FREE_GIB=5
worktree_disk_room "$REPO_ROOT/.claude/worktrees/issue-6-build"; rc=$?
[ "$rc" = 0 ] && [ "$(n prune)" = 2 ] && [ "$(n gc)" = 0 ] \
  && ok "worktree có sẵn: vẫn tỉa, vẫn giao (không từ chối vì sàn)" || fail "worktree có sẵn: rc=$rc prune=$(n prune) gc=$(n gc)"

# 3 kit cũ không có CACHE_PRUNE_GIB
sed -i.bak '/^CACHE_PRUNE_GIB/d' "$KIT"; : > "$TMP/log"; DISK_GC_NEXT=0; export FAKE_FREE_GIB=20
worktree_disk_room "$REPO_ROOT/.claude/worktrees/issue-7-build"; rc=$?
[ "$rc" = 0 ] && [ "$(n prune)" = 2 ] && ! grep -q '⚠' "$TMP/log" 2>/dev/null \
  && ok "kit cũ: không tỉa, không cảnh báo, giao thẻ" || fail "kit cũ: rc=$rc prune=$(n prune) log=$(cat "$TMP/log" 2>/dev/null)"
[ "$FAILS" = 0 ]
