#!/usr/bin/env bash
# #1146 (agent-workbench): checkout chính của repo chứa kit là nơi `.agents/devkit` của mọi repo app trỏ tới. Nó đứng detached ở một nhánh
# issue 30 giờ (11/11 03:05 +07) mà `agent-kit health` không báo gì; một .git/index.lock 0 byte do lệnh git đã chết để lại nằm đó 36 giờ
# và làm mọi lệnh git ghi chỉ mục của checkout ấy lỗi, cũng không ai báo.
# `agent-health.py` nay in một dòng khi checkout đó detached hoặc lệch khỏi nhánh trunk, và một dòng khi index.lock của nó cũ hơn
# 10 phút mà không tiến trình git nào giữ file. Chỉ báo: không bao giờ xoá khoá, không bao giờ đổi nhánh.
# Checkout nào: checkout CHÍNH của repo chứa kit đang chạy (qua symlink .agents/devkit), không phải HEAD của worktree health chạy trong
# đó (worktree lane detached là bình thường) và không phải nhánh riêng của repo app. Các dòng này không tính điểm.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'jobs -p | xargs kill 2>/dev/null; rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
export HOME="$TMP/home"; mkdir -p "$HOME"
export DEVKIT_LANG=en
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
strip() { sed 's/\x1b\[[0-9;]*m//g'; }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

# H = repo chứa một bản sao kit (không có tests: không cần và chiếm phần lớn dung lượng)
H="$TMP/host"; mkdir -p "$H/universal-agent-devkit"
( cd "$DEVKIT_DIR" && tar -cf - --exclude=./tests --exclude=./.git . ) | ( cd "$H/universal-agent-devkit" && tar -xf - )
git -C "$H" init -q -b main && git -C "$H" config user.email t@t && git -C "$H" config user.name t
echo note > "$H/note.txt"
git -C "$H" add -A >/dev/null 2>&1 && git -C "$H" commit -qm kit
# A = repo app có .agents/devkit là symlink tới kit trong H (cách 5 repo app được nối)
A="$TMP/app"; mkdir -p "$A/.agents"
git -C "$A" init -q -b main && git -C "$A" config user.email t@t && git -C "$A" config user.name t
ln -s "$H/universal-agent-devkit" "$A/.agents/devkit"
echo x > "$A/a.txt" && git -C "$A" add a.txt && git -C "$A" commit -qm i

# health <script health của kit> <target> -> output đã bỏ màu
health() { python3 "$1" -t "$2" 2>&1 | strip; }
HEALTH_APP="$A/.agents/devkit/bin/agent-health.py"
n_head() { grep -cE "is detached at|is on branch" <<< "$1"; }
n_lock() { grep -c "index.lock" <<< "$1"; }

# 1. host khoẻ: không có dòng nào
out="$(health "$HEALTH_APP" "$A")"
[ "$(n_head "$out")" = 0 ] && [ "$(n_lock "$out")" = 0 ] && ok "main checkout on main, no lock: health prints neither line" \
  || fail "healthy host got a line: $(grep -E 'is detached at|is on branch|index.lock' <<< "$out" | head -2)"
total_of() { grep -Eo '[0-9]+/[0-9]+ checks measured' <<< "$1" | head -1 | sed 's|^[0-9]*/\([0-9]*\) .*|\1|'; }
score_ok="$(total_of "$out")"

# 2. detached: đúng một dòng, nêu checkout, commit và nhánh trunk; nhánh không bị đổi, cây không bị đụng
sha="$(git -C "$H" rev-parse --short HEAD)"
git -C "$H" checkout -q --detach
echo dirty >> "$H/note.txt"
out="$(health "$HEALTH_APP" "$A")"
[ "$(n_head "$out")" = 1 ] && grep -E "is detached at" <<< "$out" | grep -qF "$H" && grep -E "is detached at" <<< "$out" | grep -qF "$sha" \
  && grep -E "is detached at" <<< "$out" | grep -qF "main" \
  && ok "detached main checkout: one line with the path, the commit and the trunk branch" \
  || fail "detached: $(grep -E 'is detached at|is on branch' <<< "$out" | head -3)"
[ -z "$(git -C "$H" symbolic-ref -q HEAD)" ] && git -C "$H" status --short | grep -q note.txt \
  && ok "health did not switch the branch and did not touch the tree" || fail "health changed the main checkout"
[ "$(total_of "$out")" = "$score_ok" ] && ok "the line is not scored (checks measured: $score_ok before and after)" \
  || fail "the number of checks changed: $score_ok -> $(total_of "$out")"
git -C "$H" checkout -q -- . && git -C "$H" switch -q main

# 3. ở nhánh khác: một dòng nêu tên nhánh
git -C "$H" switch -q -c issue-774-x
out="$(health "$HEALTH_APP" "$A")"
[ "$(n_head "$out")" = 1 ] && grep -E "is on branch" <<< "$out" | grep -qF "issue-774-x" \
  && ok "main checkout on another branch: one line naming it" || fail "branch: $(grep -E 'is detached at|is on branch' <<< "$out" | head -3)"
git -C "$H" switch -q main

# 4. index.lock: cũ hơn 10 phút và không tiến trình git giữ -> một dòng nêu file; mới, hoặc git đang giữ -> không dòng nào; không bao giờ bị xoá
LOCK="$H/.git/index.lock"
HAVE_LSOF=0; command -v lsof >/dev/null 2>&1 && HAVE_LSOF=1   # không có lsof thì health im lặng về khoá (không biết ai giữ): các ca cần lsof thật được bỏ qua
: > "$LOCK"; touch -t "$(date -v-11M +%Y%m%d%H%M 2>/dev/null || date -d '11 minutes ago' +%Y%m%d%H%M)" "$LOCK"
out="$(health "$HEALTH_APP" "$A")"
if [ "$HAVE_LSOF" = 1 ]; then
  [ "$(n_lock "$out")" = 1 ] && grep "index.lock" <<< "$out" | grep -qF "$LOCK" \
    && ok "11 minute old lock, no git process: one line naming the file" || fail "stale lock: $(grep index.lock <<< "$out" | head -2)"
else
  [ "$(n_lock "$out")" = 0 ] && ok "no lsof: an old lock is not reported (nobody can tell who holds it)" || fail "reported without lsof"
fi
[ -e "$LOCK" ] && ok "health did not remove the lock" || fail "health removed the lock"
touch "$LOCK"
out="$(health "$HEALTH_APP" "$A")"
[ "$(n_lock "$out")" = 0 ] && ok "a fresh lock (a git command is probably running): no line" || fail "fresh lock reported"
touch -t "$(date -v-11M +%Y%m%d%H%M 2>/dev/null || date -d '11 minutes ago' +%Y%m%d%H%M)" "$LOCK"
# một tiến trình git đang mở file: khoá còn sống. Ở đây không thể đặt tên lệnh `git` cho một tiến trình (lsof in tên chương trình đã
# resolve, macOS giết bản sao của binary hệ thống), nên một lsof giả báo người giữ đúng định dạng -F của lsof; lsof thật được dùng ở các
# ca còn lại (không ai giữ, một tiến trình không phải git đang đọc).
mkdir -p "$TMP/fakebin"
printf '#!/bin/sh\nprintf "p4242\\ncgit\\nf3\\n"\nexit 0\n' > "$TMP/fakebin/lsof" && chmod +x "$TMP/fakebin/lsof"
out="$(PATH="$TMP/fakebin:$PATH" health "$HEALTH_APP" "$A")"
[ "$(n_lock "$out")" = 0 ] && ok "an old lock lsof says a git process holds open: no line" || fail "a live lock was reported: $(grep index.lock <<< "$out" | head -1)"
printf '#!/bin/sh\nexit 2\n' > "$TMP/fakebin/lsof"
out="$(PATH="$TMP/fakebin:$PATH" health "$HEALTH_APP" "$A")"
[ "$(n_lock "$out")" = 0 ] && ok "lsof failing: nothing is said (the lock may be live)" || fail "reported with a broken lsof"
rm -f "$TMP/fakebin/lsof"
# một tiến trình không phải git đang đọc nó (language server của Antigravity trong sự cố): khoá vẫn là khoá cũ
if [ "$HAVE_LSOF" = 1 ]; then   # hai ca dưới cần lsof thật (không có lsof thì health im lặng, xem ca lsof lỗi ở trên)
  ( exec 3<"$LOCK"; exec sleep 60 ) & reader=$!
  sleep 1
  out="$(health "$HEALTH_APP" "$A")"
  [ "$(n_lock "$out")" = 1 ] && ok "an old lock only a non-git process has open: reported" || fail "reader-only lock not reported"
  kill "$reader" 2>/dev/null; wait "$reader" 2>/dev/null
  rm -f "$LOCK"
  # `git commit` chờ trình soạn thảo: git đã đóng fd nhưng vẫn giữ index.lock; tiến trình git còn sống với cwd là checkout chính, khoá không được báo là mồ côi
  echo more >> "$H/note.txt"
  ( cd "$H" && GIT_EDITOR="sleep 20; true" git commit -q -a >/dev/null 2>&1 ) & gc=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -e "$LOCK" ] && break; sleep 0.5; done
  if [ -e "$LOCK" ]; then
    touch -t "$(date -v-11M +%Y%m%d%H%M 2>/dev/null || date -d '11 minutes ago' +%Y%m%d%H%M)" "$LOCK"
    out="$(health "$HEALTH_APP" "$A")"
    [ "$(n_lock "$out")" = 0 ] && ok "an old lock a live git commit holds (editor open, fd closed): no line" \
      || fail "a live git commit's lock was reported as orphaned: $(grep index.lock <<< "$out" | head -1 | cut -c1-120)"
  else
    echo "skip: this git does not hold index.lock while the editor is open"
  fi
  pkill -P "$gc" 2>/dev/null; kill "$gc" 2>/dev/null; wait "$gc" 2>/dev/null
  rm -f "$LOCK"; git -C "$H" checkout -q -- . 2>/dev/null
else
  echo "skip: no lsof on this machine"
fi
rm -f "$LOCK"   # luôn dọn, kể cả khi bỏ qua các ca trên: mục 5 chạy git worktree add / switch ở H

# 5. worktree liên kết của H: health chạy từ đó kiểm H (checkout chính), không kiểm HEAD detached của chính worktree
git -C "$H" worktree add -q --detach "$H/.claude/worktrees/lane" HEAD
out="$(health "$H/.claude/worktrees/lane/universal-agent-devkit/bin/agent-health.py" "$H/.claude/worktrees/lane")"
[ "$(n_head "$out")" = 0 ] && ok "run from a detached lane worktree while main is on main: no line" || fail "worktree HEAD was flagged: $(grep -E 'is detached at' <<< "$out" | head -1)"
git -C "$H" checkout -q --detach
out="$(health "$H/.claude/worktrees/lane/universal-agent-devkit/bin/agent-health.py" "$H/.claude/worktrees/lane")"
[ "$(n_head "$out")" = 1 ] && grep -E "is detached at" <<< "$out" | grep -qF "$H " && ! grep -E "is detached at" <<< "$out" | grep -qF "/.claude/worktrees/lane" \
  && ok "run from a lane worktree while main is detached: the line names the main checkout" || fail "worktree run: $(grep -E 'is detached at' <<< "$out" | head -2)"
git -C "$H" switch -q main

# 6. nhánh riêng của repo app không bị xét; kit nằm ngoài mọi repo git thì im lặng
git -C "$A" switch -q -c feature
out="$(health "$HEALTH_APP" "$A")"
[ "$(n_head "$out")" = 0 ] && ok "the app repo on a feature branch: no line" || fail "the app's own branch was flagged"
P="$TMP/plain"; mkdir -p "$P" && ( cd "$H/universal-agent-devkit" && tar -cf - . ) | ( cd "$P" && tar -xf - )
out="$(health "$P/bin/agent-health.py" "$A")"
[ "$(n_head "$out")" = 0 ] && [ "$(n_lock "$out")" = 0 ] && ok "a kit that is not in a git repo: silent" || fail "non-git kit printed a line"

[ "$FAILS" -eq 0 ] && echo "✅ test_health_kit_host_checkout: all passed" || { echo "❌ test_health_kit_host_checkout: $FAILS failed"; exit 1; }
