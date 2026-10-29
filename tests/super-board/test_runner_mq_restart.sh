#!/usr/bin/env bash
# Test (#599, Refs #537): runner restart giữa chừng với merge_queue_due chạy nền.
#  - Bộ gom giả đang chạy (.mq.pid còn sống), shell mới source lại runner cùng RUNNER_DIR + slug: không có lượt gọi thứ hai vào bộ gom.
#  - Runner cũ để lại .mq.rc: runner mới đọc lại và áp 79/9 như cũ (halt), mã khác chỉ ghi log và chạy tiếp.
# Mỗi "runner" là một tiến trình bash riêng (restart thật), gh/bộ gom là stub. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="${SB_TEST_RUNNER:-$ROOT/.claude/bin/super-board-run.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-mq-restart.XXXXXX")"
cleanup() { for p in $(cat "$TMP/gatherer-pids" 2>/dev/null); do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/run"
printf 'import sys\nsys.exit(1)\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
# Bộ gom giả: ghi một dòng mỗi lần được gọi, ngủ $MQ_SLEEP giây, thoát $MQ_RC.
cat > "$TMP/bin/super-board-merge-queue.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$STUB_DIR/mq-calls"
echo $$ >> "$STUB_DIR/gatherer-pids"
sleep "${MQ_SLEEP:-0}"
exit "${MQ_RC:-0}"
SH
chmod +x "$TMP/bin/super-board-merge-queue.sh"
echo '{"worker_backend":"claude-p"}' > "$TMP/cfg.json"
export STUB_DIR="$TMP" SB_T_RUNNER="$RUNNER" SB_MERGE_QUEUE=1 SB_MQ_TICK_WAIT=0

# runner_tick: một runner mới (bash mới, source lại runner cùng RUNNER_DIR/slug) chạy đúng một tick merge_queue_due.
runner_tick() {
  bash -c '
    SB_LIB_ONLY=1 . "$SB_T_RUNNER" || exit 99   # sourcing the runner rewrites $1/$2: pass state through env
    set +e
    SB_GITHUB_READ="$STUB_DIR/bin/super-board-github-read.py"; CONFIG_PATH="$STUB_DIR/cfg.json"
    RUNNER_DIR="$STUB_DIR/run"; CONFIG_SLUG=board; RUN_MANIFEST=/dev/null
    log() { echo "$*" >> "$STUB_DIR/log"; }
    merge_queue_due
  '
}
calls() { [ -f "$TMP/mq-calls" ] && wc -l < "$TMP/mq-calls" | tr -d ' ' || echo 0; }
wait_calls() { local i=0; while [ "$(calls)" -lt "$1" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; }
reset() {
  for p in $(cat "$TMP/gatherer-pids" 2>/dev/null); do kill "$p" 2>/dev/null; done
  rm -f "$TMP"/run/board.mq.* "$TMP/mq-calls" "$TMP/gatherer-pids"; : > "$TMP/log"; unset MQ_SLEEP MQ_RC
}

# ── 1. bộ gom đang chạy, runner khởi động lại: không bật bộ gom thứ hai
reset; export MQ_SLEEP=5 MQ_RC=79
runner_tick; r=$?; wait_calls 1
{ [ "$r" = 0 ] && [ "$(calls)" = 1 ] && [ -f "$TMP/run/board.mq.pid" ]; } && ok "runner #1 starts one background gatherer and leaves .mq.pid" || fail "runner #1: rc=$r calls=$(calls) pid=$(cat "$TMP/run/board.mq.pid" 2>/dev/null)"
runner_tick; r=$?; sleep 1
{ [ "$r" = 0 ] && [ "$(calls)" = 1 ]; } && ok "restarted runner #2 (same RUNNER_DIR + slug, gatherer alive) starts no second gatherer" || fail "restart started a second gatherer: rc=$r calls=$(calls)"
runner_tick; r=$?; sleep 1
[ "$(calls)" = 1 ] && ok "  … and neither does runner #3" || fail "runner #3 started another gatherer: calls=$(calls)"

# ── 2. gatherer xong sau restart: .mq.rc do nó ghi vẫn đọc được, runner mới áp 79 như cũ
for _ in $(seq 1 60); do [ -f "$TMP/run/board.mq.rc" ] && break; sleep 0.2; done
[ "$(cat "$TMP/run/board.mq.rc" 2>/dev/null)" = 79 ] && ok "the orphaned gatherer still writes .mq.rc after its runner is gone" || fail ".mq.rc missing/wrong: $(cat "$TMP/run/board.mq.rc" 2>/dev/null)"
runner_tick; r=$?
{ [ "$r" = 79 ] && [ "$(calls)" = 1 ] && [ ! -f "$TMP/run/board.mq.rc" ] && [ ! -f "$TMP/run/board.mq.pid" ]; } \
  && ok "new runner collects the old runner's .mq.rc: halt 79, state files removed, no new gatherer" || fail "collect after restart: rc=$r calls=$(calls) files=$(ls "$TMP"/run 2>/dev/null | tr '\n' ' ')"

# ── 3. .mq.rc do runner cũ để lại (kể cả chết cùng bộ gom): 79 và 9 halt, 3 chỉ ghi log
for code in 79 9; do
  reset; echo "$code" > "$TMP/run/board.mq.rc"; echo 999999 > "$TMP/run/board.mq.pid"
  runner_tick; r=$?
  { [ "$r" = "$code" ] && [ "$(calls)" = 0 ]; } && ok "left-over .mq.rc=$code: new runner halts with $code without calling the gatherer" || fail "left-over rc $code: rc=$r calls=$(calls)"
done
reset; echo 3 > "$TMP/run/board.mq.rc"; echo 999999 > "$TMP/run/board.mq.pid"
runner_tick; r=$?
{ [ "$r" = 0 ] && grep -q 'exited 3' "$TMP/log" && [ ! -f "$TMP/run/board.mq.rc" ]; } && ok "left-over .mq.rc=3: logged, runner keeps going, file removed" || fail "left-over rc 3: rc=$r log=$(cat "$TMP/log")"

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
