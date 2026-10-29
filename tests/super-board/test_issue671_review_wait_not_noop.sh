#!/usr/bin/env bash
# Test hồi quy #671 (29/10, #659): review worker kết thúc lượt bình thường (exit=0, result success, is_error=false) khi chờ điều kiện
# (comment cuối kết thúc bằng `blocked-by:`), runner đếm là no-op rồi chặn thẻ ❓ như worker chết.
#  - 2 lượt review kết thúc sạch + comment cuối là `blocked-by:` -> KHÔNG Blocked, không ghi sổ no-op.
#  - 2 lượt thoát sạch nhưng comment cuối không có `blocked-by:` -> vẫn Blocked như cũ.
#  - 2 lượt bị kill (exit=143) hoặc result is_error -> vẫn Blocked như cũ.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-671.XXXXXX")"
trap 'rm -r "$TMP"' EXIT

unset SB_GITHUB_READ_STRICT SB_NOOP_MAX SB_NOOP_WINDOW_S
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="$TMP/wl"; mkdir -p "$WORKER_LOG_DIR"
BOT_LOGIN="sb-bot"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
note_worker_limit() { :; }
note_early_death() { :; }
fetch_project_items() { :; }
issue_comment_count() { printf '3'; }
LAST_COMMENT=""
issue_last_comment() { printf '%s' "$LAST_COMMENT"; }

sleep 0 & DEAD=$!; wait "$DEAD"

OKRES='{"type":"result","subtype":"success","is_error":false,"result":"waiting"}'
set_card() { PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$1\",\"status\":\"Review\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$1,\"title\":\"card $1\",\"assignees\":[\"sb-bot\"]}}]}"; }
lock() { printf 'PID=%s\nLANE=review\nSTARTED=2026-10-29T12:00:00Z\nWORKER_LOG=%s\nFROM_COL=Review\nCOMMENTS0=3\n' "$DEAD" "$WORKER_LOG_DIR/worker-review-$1.log" > "$INFLIGHT_DIR/$1"; }
cycle() { reap_finished_locks; block_noop_workers; }
reset_case() { : > "$TMP/writes"; : > "$TMP/log"; NOOP_CHECK=""; NOOP_MOVED=0; }
two() { lock "$1"; cycle; lock "$1"; cycle; }
cd "$TMP" || exit 1

# A: lượt sạch + chờ điều kiện (blocked-by:) hai lần -> không Blocked, không ghi sổ
reset_case; set_card 659
printf '=== dispatch x\n%s\nworker_exit: exit=0 signal=- elapsed=60s\n' "$OKRES" > "$WORKER_LOG_DIR/worker-review-659.log"
LAST_COMMENT=$'[reviewer] [report] chờ gate_receipt\nblocked-by: gate_receipt'
two 659
if ! grep -q "^move " "$TMP/writes" && [ ! -s "$INFLIGHT_DIR/noops/659" ]; then ok "A: 2 clean waiting review turns -> not Blocked"
else fail "A: waiting turns blocked/counted (writes: $(tr '\n' ';' < "$TMP/writes"))"; fi

# B: lượt sạch nhưng comment cuối không phải blocked-by: -> vẫn Blocked
reset_case; set_card 660
printf '=== dispatch x\n%s\nworker_exit: exit=0 signal=- elapsed=60s\n' "$OKRES" > "$WORKER_LOG_DIR/worker-review-660.log"
LAST_COMMENT=$'[reviewer] [report] xong'
two 660
if grep -qx "move PVTI_660 Blocked" "$TMP/writes"; then ok "B: clean exit without blocked-by -> still Blocked"
else fail "B: not blocked (writes: $(tr '\n' ';' < "$TMP/writes"))"; fi

# C: worker bị TERM hai lần (dù comment cuối có blocked-by:) -> vẫn Blocked
reset_case; set_card 661
printf '=== dispatch x\nworker_exit: exit=143 signal=TERM elapsed=99s\n' > "$WORKER_LOG_DIR/worker-review-661.log"
LAST_COMMENT=$'blocked-by: gate_receipt'
two 661
if grep -qx "move PVTI_661 Blocked" "$TMP/writes"; then ok "C: killed worker twice -> still Blocked"
else fail "C: killed worker not blocked (writes: $(tr '\n' ';' < "$TMP/writes"))"; fi

# D: exit=0 nhưng result is_error -> vẫn Blocked
reset_case; set_card 662
printf '=== dispatch x\n{"type":"result","subtype":"success","is_error":true}\nworker_exit: exit=0 signal=- elapsed=60s\n' > "$WORKER_LOG_DIR/worker-review-662.log"
LAST_COMMENT=$'blocked-by: gate_receipt'
two 662
if grep -qx "move PVTI_662 Blocked" "$TMP/writes"; then ok "D: is_error result -> still Blocked"
else fail "D: is_error not blocked (writes: $(tr '\n' ';' < "$TMP/writes"))"; fi

[ "$FAILS" = 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
