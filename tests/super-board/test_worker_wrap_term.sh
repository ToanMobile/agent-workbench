#!/usr/bin/env bash
# Test (#489): super-board-worker-wrap.sh phải dừng được worker dù con nuốt mất SIGTERM đầu tiên.
# Gốc lỗi: wrapper phóng con bằng `"$@" &` khi trap TERM đã cài; TERM tới con trước lúc exec bị trap kế thừa bắt rồi mất khi exec,
# con chạy tiếp (sleep 301) và wrapper chờ mãi: `kill` + `wait` của test_runner_merge_queue.sh treo tới 900 s.
# Mô phỏng tất định: worker giả bỏ qua TERM đầu tiên (đúng hiệu ứng tín hiệu bị mất), thoát ở TERM thứ hai.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WRAP="${SB_TEST_WRAP:-$ROOT/.claude/bin/super-board-worker-wrap.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-wrap-term.XXXXXX")"
WPID=""
cleanup() { [ -z "$WPID" ] || kill -KILL "$WPID" 2>/dev/null; for p in $(cat "$TMP/child-pid" 2>/dev/null); do kill -KILL "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT

cat > "$TMP/swallow-first-term" <<'SH'
#!/usr/bin/env bash
echo $$ > "$1/child-pid"
n=0
trap 'n=$((n + 1)); [ "$n" -lt 2 ] || exit 0' TERM
touch "$1/ready"
while :; do sleep 0.1; done
SH
chmod +x "$TMP/swallow-first-term"

"$WRAP" "$TMP/swallow-first-term" "$TMP" > "$TMP/log" 2>&1 &
WPID=$!
for _ in $(seq 1 50); do [ -e "$TMP/ready" ] && break; sleep 0.1; done
[ -e "$TMP/ready" ] || { fail "worker never started"; exit 1; }

kill -TERM "$WPID"
dead=0
for _ in $(seq 1 60); do kill -0 "$WPID" 2>/dev/null || { dead=1; break; }; sleep 0.1; done
if [ "$dead" = 1 ]; then ok "wrapper exits within 6 s of one TERM although the worker swallowed it"; else fail "wrapper still alive 6 s after TERM (worker ignored the first signal)"; fi
if [ "$dead" = 1 ]; then
  wait "$WPID" 2>/dev/null; rc=$?
  [ "$rc" = 0 ] && ok "wrapper exit code is the worker's (0)" || fail "wrapper exit code $rc, expected the worker's 0"
  grep -q '^worker_exit: exit=0 ' "$TMP/log" && ok "worker_exit record written" || fail "no worker_exit record: $(tail -2 "$TMP/log")"
  c=$(cat "$TMP/child-pid"); kill -0 "$c" 2>/dev/null && fail "worker $c still alive after the wrapper exited" || ok "no worker left behind"
fi

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
