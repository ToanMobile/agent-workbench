#!/usr/bin/env bash
# Test hồi quy #137 (20/10, OfficeReader): QA #100 (cần máy thật) được giao 5 lần trong 40 phút, mỗi worker thoát sau
# 60–120 s, không chuyển cột, không comment, nên runner hoãn 600 s rồi giao lại và lane QA quay tại chỗ.
# Luật:
#  - Worker lane qa/review thoát (lock chết) mà thẻ vẫn ở cột lúc giao VÀ không có comment mới trên issue thì là no-op:
#    ghi một dòng vào sổ inflight/noops/<issue>.
#  - Từ SB_NOOP_MAX (mặc định 2) no-op liên tiếp trở lên: thẻ sang Blocked kèm comment theo block-template (dòng cuối
#    `blocked-by:  -`, kèm dòng cuối log worker; thẻ 📱 nếu dòng đó nhắc máy thật/thiết bị, còn lại ❓), không giao lại.
#  - Worker đã chuyển cột hoặc đã comment thì không tính no-op và xoá sổ của thẻ.
#  - Không đọc được số comment hiện tại: không kết luận gì (không tính, không xoá).
#  - dispatch_lane ghi FROM_COL và COMMENTS0 vào lock; lane build do reclaim_dead_builds lo.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-noop-worker.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

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
COMMENTS_NOW=3
issue_comment_count() { printf '%s' "$COMMENTS_NOW"; }

sleep 0 & DEAD=$!; wait "$DEAD"

set_card() {   # set_card <number> <status>
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$1\",\"status\":\"$2\",\"labels\":[\"qa\"],\"content\":{\"type\":\"Issue\",\"number\":$1,\"title\":\"card $1\",\"assignees\":[\"sb-bot\"]}}]}"
}
lock() {   # lock <issue> <lane> <from-col> <comments0>
  printf 'PID=%s\nLANE=%s\nSTARTED=2026-10-20T13:10:00Z\nWORKER_LOG=%s\nFROM_COL=%s\nCOMMENTS0=%s\n' \
    "$DEAD" "$2" "$WORKER_LOG_DIR/worker-$2-$1.log" "$3" "$4" > "$INFLIGHT_DIR/$1"
}
noop_cycle() {   # one worker death + the expensive tick that follows
  reap_finished_locks
  block_noop_workers
}
reset_case() { : > "$TMP/writes"; : > "$TMP/log"; rm -rf "$INFLIGHT_DIR"/*; NOOP_CHECK=""; NOOP_MOVED=0; COMMENTS_NOW=3; }

cd "$TMP" || exit 1

# ── A: stub worker QA thoát ngay không ghi gì, hai lần liên tiếp: lần 1 chỉ ghi sổ; lần 2 chuyển Blocked (lần 3 không giao lại).
reset_case
printf 'Đang chạy QA\nthiếu máy thật RFCWA1KQT1Y để đo 60 FPS\n' > "$WORKER_LOG_DIR/worker-qa-100.log"
set_card 100 QA
lock 100 qa QA 3; noop_cycle
n1=$(wc -l < "$INFLIGHT_DIR/noops/100" 2>/dev/null | tr -d ' ')
moved1=$(grep -c "^move " "$TMP/writes")
lock 100 qa QA 3; noop_cycle
if [ "${n1:-0}" = "1" ] && [ "$moved1" = "0" ] \
   && grep -qx "move PVTI_100 Blocked" "$TMP/writes" \
   && grep -q "blocked-by:  -" "$TMP/writes" \
   && grep -q "thiếu máy thật RFCWA1KQT1Y để đo 60 FPS" "$TMP/writes" \
   && grep -q "Reason tag:  📱" "$TMP/writes" \
   && [ "${NOOP_MOVED:-0}" = "1" ]; then
  ok "A: 2 no-op QA exits -> #100 Blocked 📱 with block-template comment carrying the worker's last log line"
else
  fail "A: no-op block failed (ledger1=${n1:-} moved1=$moved1 writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── B: log cuối không nhắc thiết bị -> ❓.
reset_case
printf 'worker exited without doing anything\n' > "$WORKER_LOG_DIR/worker-review-101.log"
set_card 101 Review
lock 101 review Review 3; noop_cycle
lock 101 review Review 3; noop_cycle
if grep -qx "move PVTI_101 Blocked" "$TMP/writes" && grep -q "Reason tag:  ❓" "$TMP/writes" && ! grep -q "Reason tag:  📱" "$TMP/writes"; then
  ok "B: no-op review worker with no device mention -> Blocked ❓"
else
  fail "B: wrong reason tag (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── C: worker thoát sớm nhưng đã chuyển thẻ (QA -> Review) -> không phải no-op, sổ bị xoá.
reset_case
mkdir -p "$INFLIGHT_DIR/noops"; echo "$(date +%s) qa" > "$INFLIGHT_DIR/noops/102"
set_card 102 Review
lock 102 qa QA 3; noop_cycle
if ! grep -q "^move " "$TMP/writes" && [ ! -e "$INFLIGHT_DIR/noops/102" ]; then
  ok "C: worker moved the card QA -> Review -> not a no-op, ledger cleared"
else
  fail "C: moved card counted as no-op (writes: $(tr '\n' ';' < "$TMP/writes") ledger=$([ -e "$INFLIGHT_DIR/noops/102" ] && echo yes || echo no))"
fi

# ── D: thẻ vẫn ở QA nhưng worker đã comment ([qa] [blocker]) -> không tính no-op, sổ bị xoá.
reset_case
mkdir -p "$INFLIGHT_DIR/noops"; echo "$(date +%s) qa" > "$INFLIGHT_DIR/noops/103"
set_card 103 QA; COMMENTS_NOW=4
lock 103 qa QA 3; noop_cycle
if ! grep -q "^move " "$TMP/writes" && [ ! -e "$INFLIGHT_DIR/noops/103" ]; then
  ok "D: card still in QA but a new comment exists -> not a no-op, ledger cleared"
else
  fail "D: commented worker counted as no-op (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── E: không đọc được số comment -> không kết luận: không ghi sổ, không Blocked.
reset_case
set_card 104 QA; COMMENTS_NOW=""
lock 104 qa QA 3; noop_cycle
lock 104 qa QA 3; noop_cycle
lock 104 qa QA 3; noop_cycle
if ! grep -q "^move " "$TMP/writes" && [ ! -e "$INFLIGHT_DIR/noops/104" ]; then
  ok "E: comment count unreadable -> nothing concluded, nothing blocked"
else
  fail "E: unreadable count still blocked/counted (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── F: lane build không đi qua đường này (reclaim_dead_builds lo thẻ Building).
reset_case
set_card 105 Building
lock 105 build Building 3; noop_cycle
lock 105 build Building 3; noop_cycle
if ! grep -q "^move " "$TMP/writes" && [ ! -e "$INFLIGHT_DIR/noops/105" ]; then
  ok "F: build lane exits are left to reclaim_dead_builds"
else
  fail "F: build lane counted by the no-op path (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── G: lock cũ không có FROM_COL (giao trước bản vá) -> không kết luận.
reset_case
set_card 106 QA
printf 'PID=%s\nLANE=qa\nSTARTED=2026-10-20T13:10:00Z\n' "$DEAD" > "$INFLIGHT_DIR/106"; noop_cycle
printf 'PID=%s\nLANE=qa\nSTARTED=2026-10-20T13:10:00Z\n' "$DEAD" > "$INFLIGHT_DIR/106"; noop_cycle
if ! grep -q "^move " "$TMP/writes" && [ ! -e "$INFLIGHT_DIR/noops/106" ]; then
  ok "G: legacy lock without FROM_COL -> not counted"
else
  fail "G: legacy lock counted (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── H: dòng sổ cũ hơn SB_NOOP_WINDOW_S không tính "liên tiếp" -> lần này chỉ là no-op thứ 1.
reset_case
mkdir -p "$INFLIGHT_DIR/noops"; echo "$(( $(date +%s) - 90000 )) qa" > "$INFLIGHT_DIR/noops/107"
set_card 107 QA
lock 107 qa QA 3; noop_cycle
if ! grep -q "^move " "$TMP/writes"; then
  ok "H: a no-op older than the window does not count toward the cap"
else
  fail "H: stale ledger line blocked the card (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── I: stamp_dispatch_baseline ghi FROM_COL và COMMENTS0 vào lock, và lock vẫn đọc được bằng read_lock.
reset_case
set_card 108 QA; COMMENTS_NOW=7
printf 'PID=%s\nLANE=qa\nSTARTED=2026-10-20T13:10:00Z\nWORKER_LOG=x\n' "$DEAD" > "$INFLIGHT_DIR/108"
stamp_dispatch_baseline 108 qa
read_lock 108
if [ "${FROM_COL:-}" = "QA" ] && [ "${COMMENTS0:-}" = "7" ] && [ "${LANE:-}" = "qa" ]; then
  ok "I: stamp_dispatch_baseline records FROM_COL=QA COMMENTS0=7 in the lock"
else
  fail "I: baseline not stamped (FROM_COL=${FROM_COL:-} COMMENTS0=${COMMENTS0:-} lock: $(tr '\n' ';' < "$INFLIGHT_DIR/108"))"
fi

# ── J (nối dây): dispatch_lane gọi stamp_dispatch_baseline; vòng chính gọi block_noop_workers ở expensive tick, không ở cheap tick.
disp=$(awk '/^dispatch_lane\(\) \{/{on=1} on{print} on && /^}/{exit}' "$RUNNER")
exp_section=$(awk '/Expensive-tick path/{on=1} on{print} on && /count_board/{exit}' "$RUNNER")
cheap_section=$(awk '/^while true; do/{on=1} on{print} on && /Expensive-tick path/{exit}' "$RUNNER")
case "$disp" in *stamp_dispatch_baseline*) d_ok=1 ;; *) d_ok=0 ;; esac   # no pipe: the runner's pipefail turns grep -q's early exit into SIGPIPE flakes
case "$exp_section" in *block_noop_workers*) e_ok=1 ;; *) e_ok=0 ;; esac
case "$cheap_section" in *block_noop_workers*) c_bad=1 ;; *) c_bad=0 ;; esac
if [ "$d_ok" = 1 ] && [ "$e_ok" = 1 ] && [ "$c_bad" = 0 ]; then
  ok "J: dispatch_lane stamps the baseline; main loop runs block_noop_workers in the expensive tick only"
else
  fail "J: wiring for the no-op path missing"
fi

[ "$FAILS" -eq 0 ] && echo "✅ test_runner_noop_worker: all passed" || { echo "❌ test_runner_noop_worker: $FAILS failed"; exit 1; }
