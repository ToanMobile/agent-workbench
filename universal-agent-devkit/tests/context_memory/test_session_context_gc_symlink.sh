#!/usr/bin/env bash
# Test hồi quy (#427 vòng 2): hooks/session_context.sh — reaper (`worktree.py gc --merged`) im lặng khi .claude hay .claude/worktrees là
# symlink. gc in "• gc --merged: <đường dẫn> is a symlink: no worktree removed" nhưng hook chạy gc nền với stdout vào /dev/null, nên không
# ai biết worktree đã gộp không còn được gỡ. Nay stdout của gc nằm ở <git-common-dir>/devkit-gc.out và lần mở phiên sau ở main checkout đưa
# ĐÚNG dòng đó vào context; mọi dòng gc khác vẫn im, WORKTREE_GC=0 / WORKTREE_GC_MERGED=0 và worktree liên kết không thấy gì.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="${SCG_KIT:-$(cd "$(dirname "$0")/../.." && pwd)}"   # SCG_KIT: chạy cùng bộ ca trên một bản kit khác (RED trên bản gốc)
HOOK="$DEVKIT_DIR/hooks/session_context.sh"
TMP="$(mktemp -d)"; TMPR="$(cd "$TMP" && pwd -P)"   # git names paths by their real path (/private/var/… on macOS)
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset WORKTREE_GC WORKTREE_GC_MERGED
ctx() { printf '{"session_id":"scg","hook_event_name":"SessionStart"}' | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>/dev/null; }
gc_wait() { sleep 1; for _ in $(seq 1 100); do pgrep -f "worktree.py gc --log=$TMPR" >/dev/null || break; sleep 0.1; done; }
gc_done() { # gc_done <repo>: gc nền đã ghi xong devkit-gc.out (dòng cuối gc in là "✔ gc: …"; tối đa 30 s, máy tải cao), rồi không còn gc nào chạy
  for _ in $(seq 1 300); do grep -q '^✔ gc' "$TMP/$1/.git/devkit-gc.out" 2>/dev/null && break; sleep 0.1; done; gc_wait; }
repo() { mkdir -p "$TMP/$1" && ( cd "$TMP/$1" && git init -q . && git config user.email t@t && git config user.name t \
  && echo x > a.txt && git add -A && git commit -qm init ); }
gcline() { printf '%s\n' "$1" | grep -c '^\[DevKit\] • gc --merged: .*symlink: '; }   # dòng symlink của gc trong output của hook
other_gc() { printf '%s\n' "$1" | grep -E '(^|\] )(✔|•) gc' | grep -v 'symlink: ' | head -1; }   # mọi dòng gc khác

# 1. .claude/worktrees là symlink: lần mở phiên đầu chạy gc (nền), lần sau đưa đúng một dòng symlink vào context.
repo wtl; mkdir -p "$TMP/elsewhere" "$TMP/wtl/.claude"; ln -s "$TMP/elsewhere" "$TMP/wtl/.claude/worktrees"
ctx "$TMP/wtl" >/dev/null; gc_done wtl
first="$(cat "$TMP/wtl/.git/devkit-gc.out" 2>/dev/null)"   # cả output của lượt gc đầu
out="$(ctx "$TMP/wtl")"; gc_wait
[ "$(gcline "$out")" = 1 ] && printf '%s' "$out" | grep -q '\.claude/worktrees.*symlink: ' \
  && ok ".claude/worktrees a symlink: the next session start says the reaper removed nothing (exactly one line)" \
  || fail ".claude/worktrees symlink not surfaced: $(printf '%s' "$out" | grep -i 'gc' | head -3) | gc out: $(printf '%s' "$first" | head -3)"
[ -z "$(other_gc "$out")" ] && printf '%s\n' "$first" | grep -q '^✔ gc' \
  && ok "  … and the other gc lines (here '✔ gc: …') stay out of the context" \
  || fail "another gc line reached the context: '$(other_gc "$out")' (gc out: $(printf '%s' "$first" | head -3))"

# 2. .claude itself a symlink (to a folder with a worktrees/ in it).
repo cl; mkdir -p "$TMP/cl-target/worktrees"; ln -s "$TMP/cl-target" "$TMP/cl/.claude"
ctx "$TMP/cl" >/dev/null; gc_done cl
out="$(ctx "$TMP/cl")"; gc_wait
[ "$(gcline "$out")" = 1 ] && ok ".claude a symlink: surfaced too" \
  || fail ".claude symlink not surfaced: $(printf '%s' "$out" | grep -i 'gc' | head -3)"

# 3. Đối chứng: repo thường (không symlink) — gc chạy hai lần, context không có dòng gc nào.
repo plain
ctx "$TMP/plain" >/dev/null; gc_done plain
out="$(ctx "$TMP/plain")"; gc_wait
[ "$(gcline "$out")" = 0 ] && [ -z "$(other_gc "$out")" ] && ok "plain repo: no gc line in the context" \
  || fail "plain repo got a gc line: $(printf '%s' "$out" | grep -i 'gc' | head -3)"

# 4. Đối chứng: công tắc tắt reaper, và một worktree liên kết của repo symlink (gc không chạy từ đó), không thấy dòng nào.
out="$(WORKTREE_GC=0 ctx "$TMP/wtl")"
[ "$(gcline "$out")" = 0 ] && ok "WORKTREE_GC=0: nothing surfaced" || fail "WORKTREE_GC=0 still surfaced the gc line"
rm -f "$TMP/wtl/.git/devkit-gc.out"; out="$(WORKTREE_GC_MERGED=0 ctx "$TMP/wtl")"; gc_done wtl
[ "$(gcline "$out")" = 0 ] && ok "WORKTREE_GC_MERGED=0: nothing surfaced" || fail "WORKTREE_GC_MERGED=0 still surfaced the gc line"
rm -f "$TMP/wtl/.git/devkit-gc.out"; ctx "$TMP/wtl" >/dev/null; gc_done wtl   # devkit-gc.out có lại dòng symlink cho ca dưới
git -C "$TMP/wtl" worktree add -q --detach "$TMP/wtl-linked" 2>/dev/null
out="$(ctx "$TMP/wtl-linked")"
grep -q 'symlink: ' "$TMP/wtl/.git/devkit-gc.out" 2>/dev/null && [ "$(gcline "$out")" = 0 ] \
  && ok "a linked worktree's session start (gc runs from the main checkout only) surfaces nothing" \
  || fail "linked worktree: gc line=$(gcline "$out") (gc out: $(head -2 "$TMP/wtl/.git/devkit-gc.out" 2>&1))"

gc_wait   # no sweep left running into the EXIT trap
[ "$FAILS" -eq 0 ] && echo "✅ test_session_context_gc_symlink: all passed" || { echo "❌ test_session_context_gc_symlink: $FAILS failed"; exit 1; }
