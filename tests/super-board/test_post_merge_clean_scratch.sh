#!/usr/bin/env bash
# Test hồi quy: `super-board-post-merge-clean.sh --sweep` gỡ scratch mồ côi của merge gate / merge train.
# 10/11: gate hay train bị SIGKILL (trap EXIT không chạy) để lại .merge-scratch-XXXXXX / .train-scratch-XXXXXX, có cả bản clone
# Library Unity — hàng GB mỗi thư mục, không ai dọn. Luật: tên đúng mẫu mktemp (6 ký tự), cũ hơn SB_SCRATCH_MAX_AGE_S (mặc định
# 7200 s), không tiến trình nào có cwd trong đó hay nhắc đường dẫn đó trên dòng lệnh. Bản giữ có chủ ý (.merge-scratch-keep-pr*) để yên.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEAN="${PMC_CLEAN:-$ROOT/.claude/bin/super-board-post-merge-clean.sh}"
for _dk in "$ROOT/universal-agent-devkit" "$ROOT/.agents/devkit"; do
  if [ -f "$_dk/tests/lib/clean_git_env.sh" ]; then . "$_dk/tests/lib/clean_git_env.sh"; break; fi
done
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-scratch-test.XXXXXX")"; TMP="$(cd "$TMP" && pwd -P)"
SL=""
trap '[ -n "$SL" ] && kill "$SL" 2>/dev/null; rm -rf "$TMP"' EXIT
R="$TMP/repo"; W="$R/.claude/worktrees"
git init -q -b main "$R"; git -C "$R" config user.email t@example.invalid; git -C "$R" config user.name t
echo a > "$R/a"; git -C "$R" add a; git -C "$R" commit -qm init; mkdir -p "$W"
# gh giả luôn hỏng: phần sweep đọc GitHub dừng lượt, phần scratch (chỉ cục bộ) vẫn phải chạy trước đó
mkdir -p "$TMP/bin"; printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/gh"; chmod +x "$TMP/bin/gh"
OLD=202601010000
git -C "$R" worktree add -q --detach "$W/.merge-scratch-AbC123"; touch -t "$OLD" "$W/.merge-scratch-AbC123"
mkdir -p "$W/.train-scratch-XyZ789/sub"; echo x > "$W/.train-scratch-XyZ789/sub/f"; touch -t "$OLD" "$W/.train-scratch-XyZ789"
git -C "$R" worktree add -q --detach "$W/.merge-scratch-young1"
mkdir -p "$W/.merge-scratch-busy01"; touch -t "$OLD" "$W/.merge-scratch-busy01"
mkdir -p "$W/.merge-scratch-keep-pr12-20260101-000000"; touch -t "$OLD" "$W/.merge-scratch-keep-pr12-20260101-000000"
mkdir -p "$W/.merge-scratch-other-name"; touch -t "$OLD" "$W/.merge-scratch-other-name"
(cd "$W/.merge-scratch-busy01" && exec sleep 60) & SL=$!
sleep 1
sweep() { (cd "$TMP" && env PATH="$TMP/bin:$PATH" bash "$CLEAN" --sweep "$R" --min-interval 0 "$@" > "$TMP/out" 2>&1); }

# 1 --dry-run: không xoá gì, nhưng nói sẽ xoá
sweep --dry-run
[ -d "$W/.merge-scratch-AbC123" ] && [ -d "$W/.train-scratch-XyZ789" ] && grep -q 'merge-scratch-AbC123' "$TMP/out" \
  && ok "--dry-run: không xoá, có liệt kê" || fail "--dry-run: $(cat "$TMP/out")"
sweep
# 2 scratch cũ đã đăng ký với git: gỡ cả thư mục lẫn đăng ký
[ ! -e "$W/.merge-scratch-AbC123" ] && ! git -C "$R" worktree list --porcelain | grep -q 'merge-scratch-AbC123' \
  && ok "scratch merge cũ đã đăng ký: gỡ và bỏ đăng ký" || fail "scratch merge cũ còn: $(cat "$TMP/out")"
# 3 scratch train cũ không đăng ký: xoá
[ ! -e "$W/.train-scratch-XyZ789" ] && ok "scratch train cũ mồ côi: xoá" || fail "scratch train còn: $(cat "$TMP/out")"
# 4 scratch còn trẻ: giữ (gate đang chạy)
[ -d "$W/.merge-scratch-young1" ] && ok "scratch mới tạo: giữ" || fail "xoá scratch còn trẻ"
# 5 tiến trình còn cwd trong scratch: giữ
[ -d "$W/.merge-scratch-busy01" ] && ok "scratch có tiến trình đang dùng: giữ" || fail "xoá scratch đang có tiến trình dùng"
# 6 bản giữ có chủ ý và tên lạ: giữ
[ -d "$W/.merge-scratch-keep-pr12-20260101-000000" ] && [ -d "$W/.merge-scratch-other-name" ] \
  && ok "keep-pr và tên không đúng mẫu mktemp: giữ" || fail "xoá bản keep-pr hoặc tên lạ"
# 7 tiến trình thoát: lượt sau gỡ được
kill "$SL" 2>/dev/null; wait "$SL" 2>/dev/null; SL=""
sweep
[ ! -e "$W/.merge-scratch-busy01" ] && ok "tiến trình thoát: lượt sau gỡ" || fail "scratch busy01 vẫn còn sau khi tiến trình thoát: $(cat "$TMP/out")"
[ "$FAILS" = 0 ]
