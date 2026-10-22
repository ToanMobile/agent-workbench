#!/usr/bin/env bash
# Test hồi quy #183 (21/10, runner.log): worker build chết sau ~20 phút (ngoài ngưỡng early_backoff 120 s) được
# reap_finished_locks / issue_locked gỡ lock + assignee nhưng thẻ vẫn nằm ở Building, không lane nào lấy thẻ từ
# Building nên b_workers=0/10 suốt đêm.
# Luật:
#  - Lock lane=build chết (ở reap_finished_locks hoặc issue_locked) ghi nhận issue vào RECLAIM_BUILDING.
#  - Ở expensive tick (sau fetch_project_items + sweep_lane_zombies), reclaim_dead_builds trả thẻ còn ở Building
#    (không lock sống, không assignee khác bot) về Ready và ghi epoch vào sổ inflight/reclaims/<issue>.
#  - Quá trần SB_RECLAIM_MAX (mặc định 2) lần trong cửa sổ SB_RECLAIM_WINDOW_S (mặc định 86400 s) thì chuyển thẻ
#    sang Blocked kèm comment đúng block-template (có dòng cuối `blocked-by:  -`).
#  - startup_reconcile trả thẻ Building về Ready như cũ, không ghi sổ reclaims và xoá RECLAIM_BUILDING.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-reclaim-dead-build.XXXXXX")"
WORKERS=""
cleanup() {
  for p in $WORKERS; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done
  rm -rf "$TMP"
}
trap cleanup EXIT

unset SB_GITHUB_READ_STRICT SB_RECLAIM_WINDOW_S SB_RECLAIM_MAX
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="wl"
BOT_LOGIN="sb-bot"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
note_worker_limit() { :; }
fetch_project_items() { :; }

worker() { sleep 300 >/dev/null 2>&1 & W=$!; WORKERS="$WORKERS $W"; }
sleep 0 & DEAD=$!; wait "$DEAD"

set_card() {   # set_card <number> <status> [assignees-json]
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$1\",\"status\":\"$2\",\"labels\":[\"bug\"],\"content\":{\"type\":\"Issue\",\"number\":$1,\"title\":\"card $1\",\"assignees\":${3:-[\"sb-bot\"]}}}]}"
}

reset_case() {
  : > "$TMP/writes"
  : > "$TMP/log"
  rm -rf "$INFLIGHT_DIR"/*
  RECLAIM_BUILDING=""
  RECLAIM_MOVED=0
}

cd "$TMP" || exit 1

# ── A: lock PID đã chết LANE=build cho #50, thẻ Building assignees ["sb-bot"] -> về Ready, ghi 1 dòng ledger, RECLAIM_BUILDING rỗng.
reset_case
printf 'PID=%s\nLANE=build\nSTARTED=2026-10-21T22:00:00Z\n' "$DEAD" > "$INFLIGHT_DIR/50"
set_card 50 Building '["sb-bot"]'
reap_finished_locks
reclaim_dead_builds; rc=$?
lines50=$( { wc -l < "$INFLIGHT_DIR/reclaims/50"; } 2>/dev/null | tr -d ' ')
if [ "$rc" -eq 0 ] && [ "${RECLAIM_MOVED:-0}" = "1" ] && grep -qx "move PVTI_50 Ready" "$TMP/writes" \
   && [ "${lines50:-0}" = "1" ] && [ -z "${RECLAIM_BUILDING:-}" ] \
   && grep -q "its build worker died mid-run (lock reaped); the card was left in Building" "$TMP/writes"; then
  ok "A: dead build lock reaped -> card #50 moved Building -> Ready, 1 epoch in ledger, RECLAIM_BUILDING cleared"
else
  fail "A: dead build lock reclaim failed (rc=$rc moved=${RECLAIM_MOVED:-} lines=${lines50:-0} reclaim='${RECLAIM_BUILDING:-}' writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── B: lock build của worker còn sống -> không move.
reset_case
worker; live_pid=$W
printf 'PID=%s\nLANE=build\nSTARTED=2026-10-21T22:00:00Z\n' "$live_pid" > "$INFLIGHT_DIR/51"
set_card 51 Building '["sb-bot"]'
reap_finished_locks
reclaim_dead_builds
if ! grep -q "^move " "$TMP/writes" && [ ! -e "$INFLIGHT_DIR/reclaims/51" ] && [ "${RECLAIM_MOVED:-0}" = "0" ]; then
  ok "B: live build worker lock -> not moved, no ledger entry"
else
  fail "B: live build worker touched (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── C: lock chết LANE=review cho #52, thẻ ở Review -> không move.
reset_case
printf 'PID=%s\nLANE=review\nSTARTED=2026-10-21T22:00:00Z\n' "$DEAD" > "$INFLIGHT_DIR/52"
set_card 52 Review '["sb-bot"]'
reap_finished_locks
reclaim_dead_builds
if ! grep -q "^move " "$TMP/writes" && [ -z "${RECLAIM_BUILDING:-}" ] && [ ! -e "$INFLIGHT_DIR/reclaims/52" ]; then
  ok "C: dead review lock on #52 -> not queued for Building reclaim and not moved"
else
  fail "C: dead review lock moved card (reclaim='${RECLAIM_BUILDING:-}' writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── D: lock build chết, thẻ đã sang QA (worker chuyển cột rồi chết) -> không move, không ghi ledger.
reset_case
printf 'PID=%s\nLANE=build\nSTARTED=2026-10-21T22:00:00Z\n' "$DEAD" > "$INFLIGHT_DIR/53"
set_card 53 QA '["sb-bot"]'
reap_finished_locks
reclaim_dead_builds
if ! grep -q "^move " "$TMP/writes" && [ ! -e "$INFLIGHT_DIR/reclaims/53" ] && [ -z "${RECLAIM_BUILDING:-}" ] && [ "${RECLAIM_MOVED:-0}" = "0" ]; then
  ok "D: dead build lock but card #53 already in QA -> not moved, ledger untouched"
else
  fail "D: card #53 in QA was touched (ledger=$([ -e "$INFLIGHT_DIR/reclaims/53" ] && echo yes || echo no) writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── E: lock build chết, thẻ Building nhưng assignees ["alice"] -> không move.
reset_case
printf 'PID=%s\nLANE=build\nSTARTED=2026-10-21T22:00:00Z\n' "$DEAD" > "$INFLIGHT_DIR/54"
set_card 54 Building '["alice"]'
reap_finished_locks
reclaim_dead_builds
if ! grep -q "^move " "$TMP/writes" && [ ! -e "$INFLIGHT_DIR/reclaims/54" ] && [ -z "${RECLAIM_BUILDING:-}" ] && [ "${RECLAIM_MOVED:-0}" = "0" ]; then
  ok "E: dead build lock on Building card #54 assigned to alice -> not moved, ledger untouched"
else
  fail "E: human-assigned card #54 was touched (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── F: ledger #55 có sẵn 2 epoch trong cửa sổ, lock build chết, thẻ Building -> move PVTI_55 Blocked, comment có blocked-by:, KHÔNG move Ready.
reset_case
now=$(date +%s)
mkdir -p "$INFLIGHT_DIR/reclaims"
printf '%s\n%s\n' "$((now - 600))" "$((now - 300))" > "$INFLIGHT_DIR/reclaims/55"
printf 'PID=%s\nLANE=build\nSTARTED=2026-10-21T22:00:00Z\n' "$DEAD" > "$INFLIGHT_DIR/55"
set_card 55 Building '["sb-bot"]'
reap_finished_locks
reclaim_dead_builds; rc=$?
if [ "$rc" -eq 0 ] && [ "${RECLAIM_MOVED:-0}" = "1" ] \
   && grep -qx "move PVTI_55 Blocked" "$TMP/writes" \
   && ! grep -qx "move PVTI_55 Ready" "$TMP/writes" \
   && grep -q "blocked-by:  -" "$TMP/writes" \
   && grep -q "worker-build-55.log" "$TMP/writes" \
   && grep -q "🛑 #55 Building → Blocked: build worker died mid-run" "$TMP/log"; then
  ok "F: 2 prior reclaims in window -> card #55 moved to Blocked with block-template comment and blocked-by: -"
else
  fail "F: cap-reached card #55 not Blocked properly (rc=$rc moved=${RECLAIM_MOVED:-} writes: $(tr '\n' ';' < "$TMP/writes") log: $(tr '\n' ';' < "$TMP/log"))"
fi

# ── G: ledger #56 có 2 epoch cũ hơn cửa sổ (SB_RECLAIM_WINDOW_S=60, epoch = now-3600) -> về Ready.
reset_case
now=$(date +%s)
mkdir -p "$INFLIGHT_DIR/reclaims"
printf '%s\n%s\n' "$((now - 3600))" "$((now - 3500))" > "$INFLIGHT_DIR/reclaims/56"
printf 'PID=%s\nLANE=build\nSTARTED=2026-10-21T22:00:00Z\n' "$DEAD" > "$INFLIGHT_DIR/56"
set_card 56 Building '["sb-bot"]'
reap_finished_locks
SB_RECLAIM_WINDOW_S=60 reclaim_dead_builds
if grep -qx "move PVTI_56 Ready" "$TMP/writes" && ! grep -qx "move PVTI_56 Blocked" "$TMP/writes"; then
  ok "G: 2 expired ledger epochs outside SB_RECLAIM_WINDOW_S=60 -> card #56 moved back to Ready"
else
  fail "G: expired ledger epochs blocked card #56 (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── H: issue_locked gặp lock build chết (đường thứ hai) -> reclaim_dead_builds vẫn trả thẻ về Ready.
reset_case
printf 'PID=%s\nLANE=build\nSTARTED=2026-10-21T22:00:00Z\n' "$DEAD" > "$INFLIGHT_DIR/57"
set_card 57 Building '["sb-bot"]'
issue_locked 57
reclaim_dead_builds
if grep -qx "move PVTI_57 Ready" "$TMP/writes" && [ -s "$INFLIGHT_DIR/reclaims/57" ] && [ -z "${RECLAIM_BUILDING:-}" ]; then
  ok "H: dead build lock reaped via issue_locked -> reclaim_dead_builds moves #57 to Ready"
else
  fail "H: issue_locked path did not reclaim #57 (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── I (nối dây): trong nguồn runner, reclaim_dead_builds được gọi trong vòng chính sau fetch_project_items của expensive tick.
exp_section=$(awk '/Expensive-tick path/{on=1} on{print} on && /count_board/{exit}' "$RUNNER")
cheap_section=$(awk '/^while true; do/{on=1} on{print} on && /Expensive-tick path/{exit}' "$RUNNER")
if printf '%s\n' "$exp_section" | grep -q 'reclaim_dead_builds' \
   && printf '%s\n' "$exp_section" | grep -q 'RECLAIM_MOVED' \
   && ! printf '%s\n' "$cheap_section" | grep -q 'reclaim_dead_builds'; then
  ok "I: main loop calls reclaim_dead_builds in the expensive tick (after fetch_project_items, before count_board) and not in the cheap tick"
else
  fail "I: main-loop wiring for reclaim_dead_builds missing or in cheap tick"
fi

# ── J: startup_reconcile với lock build chết -> thẻ về Ready qua đường startup, ledger KHÔNG được ghi, RECLAIM_BUILDING rỗng sau đó.
reset_case
printf 'PID=%s\nLANE=build\nSTARTED=2026-10-21T22:00:00Z\n' "$DEAD" > "$INFLIGHT_DIR/58"
set_card 58 Building '["sb-bot"]'
(
  adopt_live_locks() { :; }
  gh_rate_guard() { :; }
  sweep_merged_lanes() { :; }
  fetch_project_items() { :; }
  startup_reconcile
  [ -z "${RECLAIM_BUILDING:-}" ] || exit 1
)
rc=$?
if [ "$rc" -eq 0 ] && grep -qx "move PVTI_58 Ready" "$TMP/writes" && [ ! -e "$INFLIGHT_DIR/reclaims/58" ]; then
  ok "J: startup_reconcile moves stranded #58 to Ready without writing the reclaim ledger and clears RECLAIM_BUILDING"
else
  fail "J: startup_reconcile failed (rc=$rc ledger=$([ -e "$INFLIGHT_DIR/reclaims/58" ] && echo yes || echo no) writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

[ "$FAILS" -eq 0 ] && echo "✅ test_runner_reclaim_dead_build: all passed" || { echo "❌ test_runner_reclaim_dead_build: $FAILS failed"; exit 1; }
