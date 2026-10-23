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
#  - dispatch_lane ghi FROM_COL và COMMENTS0 (đọc trước khi worker chạy) vào lock cùng lần ghi; lane build do reclaim_dead_builds lo.
#  - Dispatch merge-only / merge-train không có mốc (đúng quy trình là để thẻ ở Review, không comment). Đổi cột hoặc comment giữa hai lần giao thì xoá sổ.
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
printf 'Đang chạy QA\nthiếu máy thật RFCWA1KQT1Y để đo 60 FPS\nworker_exit: exit=0 signal=- elapsed=3s\n' > "$WORKER_LOG_DIR/worker-qa-100.log"
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
   && ! grep -q "last log line: worker_exit:" "$TMP/writes" \
   && grep -qx "gh issue edit 100 --remove-assignee sb-bot" "$TMP/writes" \
   && [ ! -e "$INFLIGHT_DIR/noops/100" ] \
   && [ "${NOOP_MOVED:-0}" = "1" ]; then
  ok "A: 2 no-op QA exits -> #100 Blocked 📱 with block-template comment carrying the worker's last log line"
else
  fail "A: no-op block failed (ledger1=${n1:-} moved1=$moved1 writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── B: log cuối không nhắc thiết bị -> ❓.
reset_case
printf 'worker exited without doing anything\nworker_exit: exit=0 signal=- elapsed=3s\n' > "$WORKER_LOG_DIR/worker-review-101.log"
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
h_n=$(wc -l < "$INFLIGHT_DIR/noops/107" 2>/dev/null | tr -d ' ')
if ! grep -q "^move " "$TMP/writes" && [ "${h_n:-0}" = "1" ]; then
  ok "H: a no-op older than the window does not count toward the cap"
else
  fail "H: stale ledger line blocked the card (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── I (R8): dispatch_baseline đọc mốc TRƯỚC khi worker chạy và lock mang mốc trong cùng một lần ghi; chỉ lane qa/review và
#    chỉ khi được phép (merge-only/merge-train: R5) hoặc đọc được cả cột lẫn số comment.
reset_case
set_card 108 QA; COMMENTS_NOW=7
out=$(dispatch_baseline 108 qa 1)
printf 'PID=%s\nLANE=qa\nSTARTED=2026-10-20T13:10:00Z\nWORKER_LOG=x\nTRAIN=""\n%s' "$DEAD" "$out" > "$INFLIGHT_DIR/108"
read_lock 108
out_mo=$(dispatch_baseline 108 review 0); out_build=$(dispatch_baseline 108 build 1)
COMMENTS_NOW=""; out_blind=$(dispatch_baseline 108 qa 1)
if [ "${FROM_COL:-}" = "QA" ] && [ "${COMMENTS0:-}" = "7" ] && [ "${LANE:-}" = "qa" ] \
   && [ -z "$out_mo" ] && [ -z "$out_build" ] && [ -z "$out_blind" ]; then
  ok "I: dispatch_baseline gives FROM_COL=QA COMMENTS0=7 for qa; nothing for merge-only, build lane or an unreadable count"
else
  fail "I: baseline wrong (FROM_COL=${FROM_COL:-} COMMENTS0=${COMMENTS0:-} mo='$out_mo' build='$out_build' blind='$out_blind')"
fi

# ── K (R6): người đổi cột hoặc comment giữa hai lần giao thì sổ no-op cũ bị xoá; không đổi gì thì giữ.
reset_case
mkdir -p "$INFLIGHT_DIR/noops"
set_card 109 QA; COMMENTS_NOW=3
echo "$(date +%s) qa QA 3" > "$INFLIGHT_DIR/noops/109"; dispatch_baseline 109 qa 1 > /dev/null
k_same=$([ -e "$INFLIGHT_DIR/noops/109" ] && echo kept || echo gone)
COMMENTS_NOW=4; dispatch_baseline 109 qa 1 > /dev/null
k_comment=$([ -e "$INFLIGHT_DIR/noops/109" ] && echo kept || echo gone)
COMMENTS_NOW=3; echo "$(date +%s) qa Review 3" > "$INFLIGHT_DIR/noops/109"; dispatch_baseline 109 qa 1 > /dev/null
k_col=$([ -e "$INFLIGHT_DIR/noops/109" ] && echo kept || echo gone)
if [ "$k_same" = kept ] && [ "$k_comment" = gone ] && [ "$k_col" = gone ]; then
  ok "K: ledger kept when column and comments match the last no-op, cleared when either changed"
else
  fail "K: ledger handling wrong (same=$k_same comment=$k_comment col=$k_col)"
fi

# ── L: worker khác đang giữ lock thẻ -> không phán xét (issue_locked && continue).
reset_case
set_card 110 QA
printf 'PID=%s\nLANE=qa\nSTARTED=2026-10-20T13:10:00Z\nFROM_COL=QA\nCOMMENTS0=3\n' "$$" > "$INFLIGHT_DIR/110"
NOOP_CHECK=" 110:qa:QA:3"; block_noop_workers
if ! grep -q "^move " "$TMP/writes" && [ ! -e "$INFLIGHT_DIR/noops/110" ]; then
  ok "L: card with a live lock is not judged"
else
  fail "L: live-lock card judged (writes: $(tr '\n' ';' < "$TMP/writes"))"
fi

# ── M: không chuyển được thẻ sang Blocked -> không comment, không báo đã chuyển, sổ giữ nguyên (lần sau thử lại).
reset_case
set_card 111 QA
set_card_status() { return 1; }
lock 111 qa QA 3; noop_cycle
lock 111 qa QA 3; noop_cycle
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
m_n=$(wc -l < "$INFLIGHT_DIR/noops/111" 2>/dev/null | tr -d ' ')
if ! grep -q "gh issue comment" "$TMP/writes" && [ "${NOOP_MOVED:-0}" = "0" ] && [ "${m_n:-0}" = "2" ] \
   && grep -q "could not be moved to Blocked" "$TMP/log"; then
  ok "M: Blocked move failing -> no comment, ledger kept, drag-by-hand warning logged"
else
  fail "M: failed move mishandled (moved=${NOOP_MOVED:-} ledger=${m_n:-} log: $(tr '\n' ';' < "$TMP/log"))"
fi

# ── J (nối dây): dispatch_lane gọi dispatch_baseline; vòng chính gọi block_noop_workers ở expensive tick, không ở cheap tick.
disp=$(awk '/^dispatch_lane\(\) \{/{on=1} on{print} on && /^}/{exit}' "$RUNNER")
exp_section=$(awk '/Expensive-tick path/{on=1} on{print} on && /count_board/{exit}' "$RUNNER")
cheap_section=$(awk '/^while true; do/{on=1} on{print} on && /Expensive-tick path/{exit}' "$RUNNER")
case "$disp" in *dispatch_baseline*) d_ok=1 ;; *) d_ok=0 ;; esac   # no pipe: the runner's pipefail turns grep -q's early exit into SIGPIPE flakes
case "$exp_section" in *block_noop_workers*) e_ok=1 ;; *) e_ok=0 ;; esac
case "$cheap_section" in *block_noop_workers*) c_bad=1 ;; *) c_bad=0 ;; esac
[ -n "$disp" ] && [ -n "$exp_section" ] && [ -n "$cheap_section" ] || { d_ok=0; echo "J: a runner section could not be cut out"; }
if [ "$d_ok" = 1 ] && [ "$e_ok" = 1 ] && [ "$c_bad" = 0 ]; then
  ok "J: dispatch_lane takes the baseline; main loop runs block_noop_workers in the expensive tick only"
else
  fail "J: wiring for the no-op path missing"
fi

# ── N (R5): merge-only và merge-train thoát đúng quy trình (để thẻ ở Review, không comment) nên dispatch_lane không bao giờ cho chúng mốc.
n_off=$(printf '%s\n' "$disp" | grep -c 'noop_judge=0')
n_use=$(printf '%s\n' "$disp" | grep -c 'dispatch_baseline "\$issue" "\$lane" "\$noop_judge"')
if [ "${n_off:-0}" -ge 2 ] && [ "${n_use:-0}" = "1" ]; then
  ok "N: dispatch_lane turns the baseline off for merge-train and merge-only dispatches"
else
  fail "N: merge-only/merge-train still get a baseline (noop_judge=0 x${n_off:-0}, baseline call x${n_use:-0})"
fi

[ "$FAILS" -eq 0 ] && echo "✅ test_runner_noop_worker: all passed" || { echo "❌ test_runner_noop_worker: $FAILS failed"; exit 1; }
