#!/usr/bin/env bash
# Test hồi quy #671 (29/10, #659): review worker kết thúc lượt bình thường (exit=0, result success, is_error=false) khi chờ điều kiện
# (comment cuối kết thúc bằng `blocked-by:`), runner đếm là no-op rồi chặn thẻ ❓ như worker chết.
#  - 2 lượt review kết thúc sạch + comment cuối của [reviewer] là `blocked-by: <X>` -> KHÔNG Blocked, ghi sổ review-wait (không ghi sổ no-op).
#  - 2 lượt thoát sạch nhưng comment cuối không có `blocked-by:` -> vẫn Blocked như cũ.
#  - 2 lượt bị kill (exit=143) hoặc result is_error -> vẫn Blocked như cũ (comment [reviewer] có blocked-by: để chính
#    worker_ended_clean quyết định, không phải điều kiện comment).
#  - lane khác review (qa), comment không phải của [reviewer], `blocked-by: -` (chờ người) -> Blocked.
#  - quá SB_REVIEW_WAIT_MAX lượt chờ -> Blocked "chờ <X> quá lâu"; có comment mới -> sổ review-wait bị xoá; đường log lấy từ lock.
# Lane build không bao giờ vào danh sách no-op (note_worker_end chỉ nhận qa|review), nên ca "lane khác" dùng qa.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-671.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

unset SB_GITHUB_READ_STRICT SB_NOOP_MAX SB_NOOP_WINDOW_S SB_REVIEW_WAIT_S SB_REVIEW_WAIT_MAX
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
unset SB_REVIEW_WAIT_S SB_REVIEW_WAIT_MAX
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
COUNT=3
issue_comment_count() { printf '%s' "$COUNT"; }
LAST_COMMENT=""
issue_last_comment() { printf '%s' "$LAST_COMMENT"; }

sleep 0 & DEAD=$!; wait "$DEAD"

OKRES='{"type":"result","subtype":"success","is_error":false,"result":"waiting"}'
WAITING=$'[reviewer] [report] chờ gate_receipt\nblocked-by: gate_receipt'
# set_card <issue> [cột]
set_card() { PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$1\",\"status\":\"${2:-Review}\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$1,\"title\":\"card $1\",\"assignees\":[\"sb-bot\"]}}]}"; }
# lock <issue> [lane] [cột] [đường log]
lock() { printf 'PID=%s\nLANE=%s\nSTARTED=2026-10-29T12:00:00Z\nWORKER_LOG=%s\nFROM_COL=%s\nCOMMENTS0=3\n' "$DEAD" "${2:-review}" "${4:-$WORKER_LOG_DIR/worker-${2:-review}-$1.log}" "${3:-Review}" > "$INFLIGHT_DIR/$1"; }
cycle() { reap_finished_locks; block_noop_workers; }
reset_case() { : > "$TMP/writes"; : > "$TMP/log"; NOOP_CHECK=""; NOOP_MOVED=0; COUNT=3; }
one() { lock "$@"; cycle; }
two() { lock "$@"; cycle; lock "$@"; cycle; }
# okwlog <đường log>: log của lượt kết thúc sạch
okwlog() { printf '=== dispatch x\n%s\nworker_exit: exit=0 signal=- elapsed=60s\n' "$OKRES" > "$1"; }
cd "$TMP" || exit 1

# A: lượt sạch + chờ điều kiện (blocked-by:) hai lần -> không Blocked, không ghi sổ no-op, 2 dòng sổ review-wait
reset_case; set_card 659
okwlog "$WORKER_LOG_DIR/worker-review-659.log"
LAST_COMMENT="$WAITING"
two 659
if ! grep -q "^move " "$TMP/writes" && [ ! -s "$INFLIGHT_DIR/noops/659" ] && [ "$(wc -l < "$INFLIGHT_DIR/review-wait/659" | tr -d ' ')" = 2 ]; then ok "A: 2 clean waiting review turns -> not Blocked, 2 waits in the review-wait ledger"
else fail "A: waiting turns blocked/counted (writes: $(tr '\n' ';' < "$TMP/writes"))"; fi

# B: lượt sạch nhưng comment cuối không phải blocked-by: -> vẫn Blocked
reset_case; set_card 660
okwlog "$WORKER_LOG_DIR/worker-review-660.log"
LAST_COMMENT=$'[reviewer] [report] xong'
two 660
if grep -qx "move PVTI_660 Blocked" "$TMP/writes"; then ok "B: clean exit without blocked-by -> still Blocked"
else fail "B: not blocked (writes: $(tr '\n' ';' < "$TMP/writes"))"; fi

# C: worker bị TERM hai lần (dù comment [reviewer] cuối có blocked-by:) -> vẫn Blocked: worker_ended_clean quyết định
reset_case; set_card 661
printf '=== dispatch x\nworker_exit: exit=143 signal=TERM elapsed=99s\n' > "$WORKER_LOG_DIR/worker-review-661.log"
LAST_COMMENT="$WAITING"
two 661
if grep -qx "move PVTI_661 Blocked" "$TMP/writes"; then ok "C: killed worker twice (waiting comment) -> still Blocked"
else fail "C: killed worker not blocked (writes: $(tr '\n' ';' < "$TMP/writes"))"; fi

# D: exit=0 nhưng result is_error (comment [reviewer] có blocked-by:) -> vẫn Blocked
reset_case; set_card 662
printf '=== dispatch x\n{"type":"result","subtype":"success","is_error":true}\nworker_exit: exit=0 signal=- elapsed=60s\n' > "$WORKER_LOG_DIR/worker-review-662.log"
LAST_COMMENT="$WAITING"
two 662
if grep -qx "move PVTI_662 Blocked" "$TMP/writes"; then ok "D: is_error result (waiting comment) -> still Blocked"
else fail "D: is_error not blocked (writes: $(tr '\n' ';' < "$TMP/writes"))"; fi

# E: comment cuối có blocked-by: nhưng KHÔNG phải của [reviewer] -> vẫn Blocked (R2)
reset_case; set_card 663
okwlog "$WORKER_LOG_DIR/worker-review-663.log"
LAST_COMMENT=$'[builder] [report] xong\nblocked-by: gate_receipt'
two 663
if grep -qx "move PVTI_663 Blocked" "$TMP/writes"; then ok "E: non-reviewer blocked-by comment -> still Blocked"
else fail "E: non-reviewer comment exempted (writes: $(tr '\n' ';' < "$TMP/writes"))"; fi

# F: thẻ Review vừa chờ sạch nghỉ SB_REVIEW_WAIT_S, không bị chọn lại; hết hạn thì được chọn (R2)
reset_case; set_card 664
okwlog "$WORKER_LOG_DIR/worker-review-664.log"
LAST_COMMENT=$'<!-- super-review:report -->\n[reviewer] [report] chờ\nblocked-by: gate_receipt'
two 664
issue_is_open() { return 0; }
top_card_in_column Review </dev/null; first="$TOP_ISSUE"
echo $(( $(date +%s) - 4000 )) > "$INFLIGHT_DIR/review-wait/664"
top_card_in_column Review </dev/null; second="$TOP_ISSUE"
if [ -z "$first" ] && [ "$second" = 664 ]; then ok "F: waiting review card rests, then is picked again"
else fail "F: first='$first' second='$second'"; fi

# G: worker lane khác review (qa), thoát sạch, comment [reviewer] có blocked-by: -> vẫn Blocked (nhánh miễn chỉ cho lane review)
reset_case; set_card 665 QA
okwlog "$WORKER_LOG_DIR/worker-qa-665.log"
LAST_COMMENT="$WAITING"
two 665 qa QA
if grep -qx "move PVTI_665 Blocked" "$TMP/writes" && [ ! -e "$INFLIGHT_DIR/review-wait/665" ]; then ok "G: clean qa-lane worker with a [reviewer] blocked-by comment -> still Blocked"
else fail "G: qa lane exempted (writes: $(tr '\n' ';' < "$TMP/writes"))"; fi

# H: vượt SB_REVIEW_WAIT_MAX lượt chờ -> Blocked "chờ <X> quá lâu"; dưới hoặc bằng trần thì chưa
reset_case; set_card 666
okwlog "$WORKER_LOG_DIR/worker-review-666.log"
LAST_COMMENT="$WAITING"
SB_REVIEW_WAIT_MAX=2; export SB_REVIEW_WAIT_MAX
two 666
under=0; grep -q "^move " "$TMP/writes" && under=1
one 666
unset SB_REVIEW_WAIT_MAX
if [ "$under" = 0 ] && grep -qx "move PVTI_666 Blocked" "$TMP/writes" && grep -q "quá lâu" "$TMP/writes" && grep -q "gate_receipt" "$TMP/writes" && [ ! -e "$INFLIGHT_DIR/review-wait/666" ]; then ok "H: waits over SB_REVIEW_WAIT_MAX -> Blocked (chờ gate_receipt quá lâu), within the cap -> not, ledger cleared after the move"
else fail "H: cap not enforced (under=$under writes: $(tr '\n' ';' < "$TMP/writes"))"; fi

# I: chờ người (`blocked-by: -`) -> không miễn, Blocked ngay ở lượt đầu
reset_case; set_card 667
okwlog "$WORKER_LOG_DIR/worker-review-667.log"
LAST_COMMENT=$'[reviewer] [report] cần người\nblocked-by: -'
one 667
if grep -qx "move PVTI_667 Blocked" "$TMP/writes" && [ ! -e "$INFLIGHT_DIR/review-wait/667" ] && grep -qx "blocked-by:  -" "$TMP/writes" && grep -q "waiting on a person" "$TMP/writes"; then ok "I: blocked-by: - (waiting on a person) -> Blocked at once, handed to a person, not exempted"
else fail "I: human wait exempted (writes: $(tr '\n' ';' < "$TMP/writes"))"; fi

# J: lượt sau có comment mới (tiến triển) -> xoá sổ review-wait của thẻ
reset_case; set_card 668
okwlog "$WORKER_LOG_DIR/worker-review-668.log"
LAST_COMMENT="$WAITING"
one 668
had=0; [ -s "$INFLIGHT_DIR/review-wait/668" ] && had=1
COUNT=4
one 668
if [ "$had" = 1 ] && [ ! -e "$INFLIGHT_DIR/review-wait/668" ]; then ok "J: a new comment (progress) clears the review-wait ledger"
else fail "J: ledger kept (had=$had)"; fi

# K: đường log lấy từ WORKER_LOG của lock không dựng lại theo WORKER_LOG_DIR
reset_case; set_card 669
mkdir -p "$TMP/other"
okwlog "$TMP/other/custom-669.log"
LAST_COMMENT="$WAITING"
two 669 review Review "$TMP/other/custom-669.log"
if ! grep -q "^move " "$TMP/writes"; then ok "K: worker log path comes from the lock (WORKER_LOG)"
else fail "K: log path not taken from the lock (writes: $(tr '\n' ';' < "$TMP/writes"))"; fi

# M: kill -> chờ -> kill: lượt chờ không xoá sổ no-op, nên hai lượt kill (cách nhau bởi một lượt chờ) vẫn tới SB_NOOP_MAX=2 -> Blocked, và sổ review-wait bị xoá theo
reset_case; set_card 670
printf '=== dispatch x\nworker_exit: exit=143 signal=TERM elapsed=99s\n' > "$WORKER_LOG_DIR/worker-review-670.log"
LAST_COMMENT="$WAITING"
one 670
okwlog "$WORKER_LOG_DIR/worker-review-670.log"
one 670
mid=0; grep -q "^move " "$TMP/writes" && mid=1
printf '=== dispatch x\nworker_exit: exit=143 signal=TERM elapsed=99s\n' > "$WORKER_LOG_DIR/worker-review-670.log"
one 670
if [ "$mid" = 0 ] && grep -qx "move PVTI_670 Blocked" "$TMP/writes" && [ ! -e "$INFLIGHT_DIR/review-wait/670" ]; then ok "M: kill, wait, kill -> Blocked (waiting turn keeps the no-op ledger), review-wait ledger cleared"
else fail "M: mid=$mid writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-200)"; fi

# N: SB_REVIEW_WAIT_MAX lớn hơn sức chứa của sổ (20 dòng) bị kẹp về 19: lượt chờ thứ 20 vẫn bị Blocked
reset_case; set_card 671
okwlog "$WORKER_LOG_DIR/worker-review-671.log"
LAST_COMMENT="$WAITING"
SB_REVIEW_WAIT_MAX=100; export SB_REVIEW_WAIT_MAX
i=0; early=0
while [ "$i" -lt 19 ]; do one 671; i=$((i + 1)); done
grep -q "^move " "$TMP/writes" && early=1
one 671
unset SB_REVIEW_WAIT_MAX
if [ "$early" = 0 ] && grep -qx "move PVTI_671 Blocked" "$TMP/writes"; then ok "N: SB_REVIEW_WAIT_MAX=100 is clamped to the ledger capacity -> the 20th waiting turn is Blocked"
else fail "N: early=$early writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-200)"; fi

# O: set_card_status thất bại -> thẻ vẫn ở Review và sổ review-wait giữ nguyên (không mất bằng chứng trước khi chuyển được)
reset_case; set_card 672
okwlog "$WORKER_LOG_DIR/worker-review-672.log"
LAST_COMMENT="$WAITING"
SB_REVIEW_WAIT_MAX=1; export SB_REVIEW_WAIT_MAX
one 672
set_card_status() { echo "move-failed $1 $2" >> "$TMP/writes"; return 1; }
one 672
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
unset SB_REVIEW_WAIT_MAX
if grep -qx "move-failed PVTI_672 Blocked" "$TMP/writes" && [ -s "$INFLIGHT_DIR/review-wait/672" ]; then ok "O: failed move to Blocked keeps the review-wait ledger"
else fail "O: writes: $(tr '\n' ';' < "$TMP/writes" | cut -c1-200)"; fi

# L: gọi issue_last_comment bản thật: với 0 comment trả rỗng và SB_GITHUB_READ nhận 0 lần gọi; với 2 comment đọc trang 2
cat > "$TMP/fakegh.py" <<'EOF_FAKE'
import sys
with open(sys.argv[0] + ".calls", "a", encoding="utf-8") as fh:
    fh.write(" ".join(sys.argv[1:]) + "\n")
print("body")
EOF_FAKE
out0="$( SB_LIB_ONLY=1 . "$RUNNER"; SB_GITHUB_READ="$TMP/fakegh.py"; issue_last_comment 5 0 )"
out2="$( SB_LIB_ONLY=1 . "$RUNNER"; SB_GITHUB_READ="$TMP/fakegh.py"; issue_last_comment 5 2 )"
if [ -z "$out0" ] && [ "$out2" = body ] && [ "$(wc -l < "$TMP/fakegh.py.calls" | tr -d ' ')" = 1 ] && grep -q "page=2" "$TMP/fakegh.py.calls"; then ok "L: issue_last_comment with 0 comments asks nothing; with 2 it reads page 2"
else fail "L: out0='$out0' out2='$out2' calls: $(tr '\n' ';' < "$TMP/fakegh.py.calls" 2>/dev/null)"; fi

[ "$FAILS" = 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
