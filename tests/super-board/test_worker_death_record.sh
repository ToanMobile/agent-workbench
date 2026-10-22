#!/usr/bin/env bash
# Test hồi quy #237 (22/10): worker QA chết im lặng sau >1 giờ, log chỉ có dòng prompt, không có mã thoát, tín hiệu hay thời gian sống.
# Luật:
#  - super-board-worker-wrap.sh chạy lệnh worker và ghi `worker_exit: exit=<mã> signal=<tên|none> elapsed=<s>s` vào log khi nó kết thúc,
#    kể cả khi worker bị SIGKILL; mã thoát của worker không đổi.
#  - reap_finished_locks ghi dòng đó vào runner.log và comment lên thẻ (một lần mỗi lần chết) khi worker không thoát bằng 0.
#  - note_worker_limit đọc được thông báo hết hạn mức nằm trong luồng stream-json, dù dòng worker_exit nằm cuối log.
#  - resume_hint chỉ nhắc "tiếp tục từ commit/comment cuối" khi lần giao trước chết bất thường.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
WRAP="$ROOT/.claude/bin/super-board-worker-wrap.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-worker-death.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# ── A: wrapper ghi exit/signal/elapsed khi worker tự SIGKILL.
LOG="$TMP/a.log"
bash "$WRAP" bash -c 'echo working; kill -9 $$' >> "$LOG" 2>&1; rc=$?
if [ "$rc" -eq 137 ] && grep -Eq '^worker_exit: exit=137 signal=KILL elapsed=[0-9]+s$' "$LOG"; then
  ok "A: SIGKILL worker -> log has exit=137 signal=KILL elapsed, wrapper returns 137"
else
  fail "A: no exit record for killed worker (rc=$rc log: $(tr '\n' '|' < "$LOG" 2>/dev/null))"
fi

# ── B: worker thoát bình thường: exit=0 signal=none, mã thoát giữ nguyên.
LOG="$TMP/b.log"
bash "$WRAP" bash -c 'echo done; exit 3' >> "$LOG" 2>&1; rc=$?
if [ "$rc" -eq 3 ] && grep -Eq '^worker_exit: exit=3 signal=none elapsed=[0-9]+s$' "$LOG" && grep -qx done "$LOG"; then
  ok "B: normal exit code passed through and recorded"
else
  fail "B: exit code or record wrong (rc=$rc log: $(tr '\n' '|' < "$LOG" 2>/dev/null))"
fi

unset SB_GITHUB_READ_STRICT
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="$TMP/wl"; mkdir -p "$WORKER_LOG_DIR"
BOT_LOGIN=""
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
note_early_death() { :; }
sleep 0 & DEAD=$!; wait "$DEAD"

# ── C: reap ghi lý do vào runner.log và comment thẻ đúng một lần.
: > "$TMP/writes"; : > "$TMP/log"
printf '=== dispatch lane=qa issue=#223 at 2026-10-22T16:50:00Z ===\nprompt: x\n\nworker_exit: exit=137 signal=KILL elapsed=6360s\n' > "$WORKER_LOG_DIR/worker-qa-223.log"
printf 'PID=%s\nLANE=qa\nSTARTED=2026-10-22T16:50:00Z\nWORKER_LOG=%s\n' "$DEAD" "$WORKER_LOG_DIR/worker-qa-223.log" > "$INFLIGHT_DIR/223"
reap_finished_locks
n=$(grep -c "^gh issue comment 223" "$TMP/writes")
if grep -q "exit=137 signal=KILL elapsed=6360s" "$TMP/log" && [ "$n" = "1" ] && grep -q "signal=KILL" "$TMP/writes"; then
  ok "C: reap logs the exit record and posts one card comment"
else
  fail "C: reap did not record the death (comments=$n log: $(tr '\n' '|' < "$TMP/log") writes: $(tr '\n' '|' < "$TMP/writes"))"
fi

# ── D: worker thoát 0: không comment.
: > "$TMP/writes"; : > "$TMP/log"
printf '=== dispatch lane=qa issue=#224 at x ===\nprompt: x\n\nworker_exit: exit=0 signal=none elapsed=300s\n' > "$WORKER_LOG_DIR/worker-qa-224.log"
printf 'PID=%s\nLANE=qa\nSTARTED=2026-10-22T16:50:00Z\nWORKER_LOG=%s\n' "$DEAD" "$WORKER_LOG_DIR/worker-qa-224.log" > "$INFLIGHT_DIR/224"
reap_finished_locks
if ! grep -q "^gh issue comment" "$TMP/writes"; then ok "D: clean exit posts no comment"; else fail "D: clean exit commented"; fi

# ── E: hết hạn mức trong stream-json + dòng worker_exit cuối log -> ghi usage của account.
STATE="$TMP/state"; SB_ACCOUNT_STATE_DIR="$STATE"; : > "$TMP/log"
LIM="$TMP/lim.log"
{
  printf '=== dispatch lane=qa issue=#74 at x ===\nprompt: x\n\n'
  printf 'account_pool: engine=claude account=finos config_dir=/x\n'
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 10:50pm (Asia/Saigon)"}]}}\n'
  printf '{"type":"result","is_error":true,"result":"You'"'"'ve hit your session limit · resets 10:50pm (Asia/Saigon)"}\n'
  printf 'worker_exit: exit=1 signal=none elapsed=5400s\n'
} > "$LIM"
note_worker_limit "$LIM"
if [ -f "$STATE/usage-finos.json" ]; then ok "E: stream-json limit notice recorded for account finos"; else fail "E: no usage file (log: $(cat "$TMP/log" 2>/dev/null))"; fi

# ── F: resume_hint chỉ khi lần giao trước chết bất thường.
H1=$(resume_hint "$WORKER_LOG_DIR/worker-qa-223.log")
H2=$(resume_hint "$WORKER_LOG_DIR/worker-qa-224.log")
H3=$(resume_hint "$TMP/does-not-exist.log")
printf '=== dispatch lane=qa issue=#9 at x ===\nprompt: x\n' > "$TMP/nrec.log"
H4=$(resume_hint "$TMP/nrec.log")
if [ -n "$H1" ] && echo "$H1" | grep -q "git log" && [ -z "$H2" ] && [ -z "$H3" ] && [ -n "$H4" ]; then
  ok "F: resume hint after a killed or unrecorded worker only"
else
  fail "F: resume_hint wrong (killed='$H1' clean='$H2' none='$H3' unrecorded='$H4')"
fi

[ "$FAILS" -eq 0 ] && echo "ALL PASS" || { echo "$FAILS FAIL"; exit 1; }
