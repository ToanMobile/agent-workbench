#!/usr/bin/env bash
# #869 (tách từ #742, PR A5): bin/ocr-review treo khi `ocr` quá hạn mà một tiến trình cháu ở process group KHÁC còn giữ pipe:
# sau killpg, p.communicate() không có hạn nên helper chờ tới lúc cháu thoát (review_gate / lane chờ theo).
# `ocr` giả trên PATH: `delegate preview` sinh một cháu tự tách session (os.setsid, killpg không chạm tới) giữ stdout/stderr
# 90 s, rồi tự ngủ quá DELEGATE_TIMEOUT_S (6 s). Helper phải trả về exit 1 kèm "timed out" trong 60 s (6 s + 30 s grace + dư),
# không chờ cháu. Trên code chưa sửa: helper còn chạy ở giây 75 (test giết nó) ⇒ ĐỎ.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$DEVKIT_DIR/bin/ocr-review"
TMP="$(mktemp -d)"
cleanup() {   # cháu tự tách session sống tiếp sau khi helper bị giết: giết đúng PID nó ghi lại
  [ -s "$TMP/orphan.pid" ] && kill "$(cat "$TMP/orphan.pid")" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"; mkdir -p "$R" && cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
printf 'def f(x):\n    return x\n' > a.py && git add -A && git commit -qm init
printf 'def f(x):\n    return 1 / x\n' > a.py

mkdir -p "$TMP/bin"
cat > "$TMP/bin/ocr" <<'SH'
#!/bin/sh
case "$1 $2" in
  "delegate preview")
    python3 -c 'import os, sys, time
os.setsid()
open(sys.argv[1], "w").write(str(os.getpid()))
time.sleep(90)' "$ORPHAN_PID" &
    sleep 60 ;;
  *) echo '{}' ;;
esac
SH
chmod +x "$TMP/bin/ocr"

start=$(date +%s)
PATH="$TMP/bin:$PATH" ORPHAN_PID="$TMP/orphan.pid" python3 "$HELPER" --delegate-only > "$TMP/out" 2> "$TMP/err" &
hp=$!
i=0
while kill -0 "$hp" 2>/dev/null && [ "$i" -lt 75 ]; do sleep 1; i=$((i + 1)); done
if kill -0 "$hp" 2>/dev/null; then
  kill -9 "$hp" 2>/dev/null; wait "$hp" 2>/dev/null
  fail "ocr-review still running after 75 s: it waits for ocr's grandchild that holds the pipes"
else
  wait "$hp"; rc=$?
  el=$(( $(date +%s) - start ))
  [ "$el" -lt 60 ] && ok "ocr-review returned after ${el}s (bounded reap after SIGKILL)" || fail "ocr-review took ${el}s"
  [ "$rc" = 1 ] && grep -q 'timed out' "$TMP/err" && ok "exit 1 with the timeout reason" \
    || fail "rc=$rc, stderr: $(head -c 300 "$TMP/err")"
fi
[ -s "$TMP/orphan.pid" ] && ok "the grandchild ran in its own session (the hang condition was real)" \
  || fail "fake ocr never started its grandchild"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
