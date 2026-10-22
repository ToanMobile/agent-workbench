#!/usr/bin/env bash
# Test hồi quy cho .claude/bin/super-board-run.sh (runner claude-p mà cả 5 board dùng), chạy offline:
# runner được source ở lib mode (SB_LIB_ONLY=1) và mọi lệnh ghi GitHub được thay bằng stub.
#
# 1. Watchdog zombie với thẻ `qa` (2026-10-16, Neighbours-From-Hell #1): thẻ Ready gắn nhãn `qa` được giao cho
#    Tester, Tester tự chuyển Ready -> QA sau khi khởi động. Watchdog chỉ chờ QA, thấy Ready và kill Tester ngay
#    tick sau: 14 lần giao trong 11 phút, không QA được gì. Khi thẻ đã từng ở QA, quay về Ready là đường fail
#    của Tester và vẫn giải phóng lane.
# 2. Sweep Blocked (2026-10-16, Goods #2 park với `blocked-by: 1`): wave planner báo thẻ Blocked có blocker đã
#    đóng, nhưng runner claude-p chưa bao giờ hỏi nó, nên thẻ như vậy nằm Blocked mãi.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-runner-test.XXXXXX")"
WORKERS=""
cleanup() {
  for p in $WORKERS; do kill "$p" 2>/dev/null || true; done   # chỉ các tiến trình sleep do test này tạo
  rm -rf "$TMP"
}
trap cleanup EXIT

# Thư mục script stub: runner tìm các script anh em cạnh SB_GITHUB_READ.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/super-board-wave-plan.sh" <<'SH'
#!/usr/bin/env bash
# Ghi lại argv; in $STUB_PLAN, thoát với $STUB_PLAN_RC.
echo "$*" >> "$STUB_DIR/plan.calls"
[ -n "${STUB_PLAN:-}" ] && printf '%s\n' "$STUB_PLAN"
exit "${STUB_PLAN_RC:-0}"
SH
chmod +x "$TMP/bin/super-board-wave-plan.sh"
export STUB_DIR="$TMP"

unset SB_GITHUB_READ_STRICT   # merge gate export biến này cho verify của nó; test không thừa hưởng
export SB_ZOMBIE_GRACE=0  # test kill trực tiếp, không chờ ân hạn (#237)
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e   # runner đặt -euo pipefail; các kiểm tra bên dưới tự xét lỗi
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
CONFIG_PATH="$TMP/cfg.json"; echo '{}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
BOT_LOGIN=""
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
issue_is_open() { return 0; }   # #254: reclaim_stranded_building đọc state issue; mọi thẻ ở đây là issue mở (bản thật được nạp lại ở ca 79 bên dưới)

items() {   # items <number> <status> [labels-json]: a one-card board snapshot
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"PVTI_$1\",\"status\":\"$2\",\"labels\":${3:-[]},\"content\":{\"type\":\"Issue\",\"number\":$1,\"assignees\":[]}}]}"
}
worker() { sleep 300 >/dev/null 2>&1 & W=$!; WORKERS="$WORKERS $W"; }   # đặt W; không bao giờ gọi trong $(...) (pipe sẽ chờ sleep)
alive() { kill -0 "$1" 2>/dev/null; }
reset_lanes() { BUILD_PID=""; BUILD_ISSUE=""; QA_PID=""; QA_ISSUE=""; REVIEW_PID=""; REVIEW_ISSUE=""; }

# ── 1a. thẻ qa giao từ Ready, Tester chưa kịp chạy: thẻ vẫn ở Ready.
reset_lanes; worker; QA_PID=$W; QA_ISSUE=7
items 7 Ready '["qa"]'
sweep_lane_zombies
alive "$QA_PID" && [ "$QA_ISSUE" = 7 ] && ok "qa card still in Ready: Tester kept" \
  || fail "qa card still in Ready: Tester killed one tick after dispatch (re-dispatch loop)"

# ── 1b. Tester đã chuyển sang QA rồi fail về Ready: lane được giải phóng.
reset_lanes; worker; QA_PID=$W; QA_ISSUE=8
items 8 QA '["qa"]'; sweep_lane_zombies
alive "$QA_PID" || fail "qa card in QA: Tester killed while working"
items 8 Ready '["qa"]'; sweep_lane_zombies
pid8=$W
if ! alive "$pid8" && [ -z "$QA_PID" ]; then ok "seen in QA then back in Ready: zombie Tester reaped"
else fail "seen in QA then back in Ready: Tester kept (fail path never frees the lane)"; fi

# ── 1c. thẻ đến từ Build (cột QA) và đã sang Review: bị thu hồi như cũ.
reset_lanes; worker; QA_PID=$W; QA_ISSUE=9
items 9 Review '["bug"]'; sweep_lane_zombies
[ -z "$QA_PID" ] && ok "qa worker whose card reached Review: reaped" || fail "qa worker whose card reached Review: kept"

# ── 1d. Tester mới trên cùng lane bắt đầu sạch (không mang 'đã thấy ở QA' cũ).
reset_lanes; worker; QA_PID=$W; QA_ISSUE=10
items 10 QA '["qa"]'; sweep_lane_zombies
reset_lanes; worker; QA_PID=$W; QA_ISSUE=10
items 10 Ready '["qa"]'; sweep_lane_zombies
alive "$QA_PID" && ok "re-dispatched Tester on a Ready card: kept" || fail "re-dispatched Tester on a Ready card: killed by the previous Tester's state"

# ── 1e. lane build không đổi: thẻ bị chuyển sang Blocked thì giải phóng lane.
reset_lanes; worker; BUILD_PID=$W; BUILD_ISSUE=11
items 11 Blocked '["bug"]'; sweep_lane_zombies
[ -z "$BUILD_PID" ] && ok "build worker whose card reached Blocked: reaped" || fail "build worker whose card reached Blocked: kept"

# ── 2a. thẻ Blocked có blocker đã đóng về lại Ready, kèm comment.
: > "$TMP/writes"; : > "$TMP/log"; rm -f "$TMP/plan.calls"
items 12 Blocked '["feature"]'
export STUB_PLAN='{"cards":[],"sweep":[{"number":12,"title":"t","clearedBy":[9]}],"flag":[]}' STUB_PLAN_RC=0
sweep_blocked_cards >/dev/null 2>&1; rc=$?
grep -q -- "--config $CONFIG_PATH" "$TMP/plan.calls" 2>/dev/null && grep -q -- "--items " "$TMP/plan.calls" \
  && ok "sweep asks the wave planner with this config and the cached board" \
  || fail "sweep did not ask the wave planner with --config/--items (calls: $(cat "$TMP/plan.calls" 2>/dev/null))"
grep -qx "move PVTI_12 Ready" "$TMP/writes" 2>/dev/null && ok "cleared Blocked #12 moved to Ready" \
  || fail "cleared Blocked #12 not moved to Ready (writes: $(cat "$TMP/writes" 2>/dev/null))"
grep -q "^gh issue comment 12 " "$TMP/writes" 2>/dev/null && ok "unblock comment posted on #12" || fail "no unblock comment on #12"
[ "$rc" -eq 0 ] && ok "sweep that moved a card returns 0 (caller refreshes the board)" || fail "sweep that moved a card returned $rc"

# ── 2b. planner lỗi: không chuyển gì, runner chạy tiếp.
: > "$TMP/writes"
export STUB_PLAN='' STUB_PLAN_RC=69
sweep_blocked_cards >/dev/null 2>&1; rc=$?
[ ! -s "$TMP/writes" ] && ok "planner failure: nothing moved" || fail "planner failure: moved $(cat "$TMP/writes")"
[ "$rc" -eq 2 ] && ok "planner failure: sweep reports the failure (2), not 'nothing to move'" || fail "planner failure: sweep returned $rc (want 2)"

# ── 2c. thẻ chờ người (không có trong sweep) giữ nguyên.
: > "$TMP/writes"
export STUB_PLAN='{"cards":[],"sweep":[],"flag":[]}' STUB_PLAN_RC=0
sweep_blocked_cards >/dev/null 2>&1; rc=$?
[ ! -s "$TMP/writes" ] && [ "$rc" -eq 1 ] && ok "empty sweep: nothing moved" || fail "empty sweep: rc=$rc writes=$(cat "$TMP/writes")"

# ── 2d. chi phí: planner (GraphQL dựng đồ thị phụ thuộc) chỉ chạy khi tập Done đổi.
rm -f "$TMP/plan.calls"; SWEEP_DONE_SIG=""
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_1","status":"Done","content":{"type":"Issue","number":1,"assignees":[]}}]}'
maybe_sweep_blocked >/dev/null 2>&1
maybe_sweep_blocked >/dev/null 2>&1
n1="$(wc -l < "$TMP/plan.calls" 2>/dev/null | tr -d ' ')"
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_1","status":"Done","content":{"type":"Issue","number":1,"assignees":[]}},{"id":"PVTI_2","status":"Done","content":{"type":"Issue","number":2,"assignees":[]}}]}'
maybe_sweep_blocked >/dev/null 2>&1
n2="$(wc -l < "$TMP/plan.calls" 2>/dev/null | tr -d ' ')"
[ "${n1:-0}" = 1 ] && [ "${n2:-0}" = 2 ] && ok "planner runs once per Done-set change (1 then 2)" \
  || fail "planner runs: after two ticks with the same Done set=${n1:-0} (want 1), after a card landed=${n2:-0} (want 2)"

# ── 2e. planner lỗi (rate limit, mạng) được thử lại sau backoff, không chỉ sau lần về Done kế tiếp.
rm -f "$TMP/plan.calls"; SWEEP_DONE_SIG=""; SWEEP_RETRY_AT=0
export STUB_PLAN='' STUB_PLAN_RC=69
maybe_sweep_blocked >/dev/null 2>&1      # lỗi
maybe_sweep_blocked >/dev/null 2>&1      # cùng tập Done, còn trong backoff: không gọi
n1="$(wc -l < "$TMP/plan.calls" 2>/dev/null | tr -d ' ')"
SWEEP_RETRY_AT=1                          # the backoff has passed
export STUB_PLAN='{"cards":[],"sweep":[],"flag":[]}' STUB_PLAN_RC=0
maybe_sweep_blocked >/dev/null 2>&1      # thử lại
maybe_sweep_blocked >/dev/null 2>&1      # đã thành công: không gọi thêm cho tập Done này
n2="$(wc -l < "$TMP/plan.calls" 2>/dev/null | tr -d ' ')"
[ "${n1:-0}" = 1 ] && [ "${n2:-0}" = 2 ] && ok "failed planner retried once after the backoff (1 then 2)" \
  || fail "failed planner: calls inside the backoff=${n1:-0} (want 1), after it=${n2:-0} (want 2)"

# ── 2f. thẻ `needs-you` là quyết định của người kể cả khi planner thả nó (comment Block 🙋 đã trôi khỏi
#        cửa sổ 8 comment cuối của planner); thẻ đã sweep một lần trong lần chạy này không bị sweep lại.
: > "$TMP/writes"; rm -f "$TMP/plan.calls"; SWEPT_CARDS=""
PROJECT_ITEMS_JSON='{"items":[
 {"id":"PVTI_31","status":"Blocked","labels":["bug","needs-you"],"content":{"type":"Issue","number":31,"assignees":[]}},
 {"id":"PVTI_32","status":"Blocked","labels":["qa"],"content":{"type":"Issue","number":32,"assignees":[]}}]}'
export STUB_PLAN='{"cards":[],"sweep":[{"number":31,"title":"a","clearedBy":[5]},{"number":32,"title":"b","clearedBy":[6]}],"flag":[]}' STUB_PLAN_RC=0
sweep_blocked_cards >/dev/null 2>&1
grep -q "PVTI_31" "$TMP/writes" && fail "needs-you card #31 moved to Ready by the sweep" || ok "needs-you card stays Blocked"
grep -qx "move PVTI_32 Ready" "$TMP/writes" && ok "qa card #32 swept" || fail "qa card #32 not swept"
grep -A3 "^gh issue comment 32 " "$TMP/writes" | grep -q "Next: tester" && ok "qa card's comment names the tester" \
  || fail "qa card's comment does not name the tester: $(grep -A3 '^gh issue comment 32 ' "$TMP/writes" | tail -1)"
: > "$TMP/writes"
sweep_blocked_cards >/dev/null 2>&1   # #32 bị park lại và planner lại thả nó
grep -q "PVTI_32" "$TMP/writes" && fail "card #32 swept twice in one run (Blocked<->Ready ping-pong)" || ok "a card is swept at most once per run"
#     Bị chặn lại bởi blocker KHÁC (daemon chạy nhiều ngày): blocker mới đóng thì vẫn phải được sweep.
: > "$TMP/writes"
export STUB_PLAN='{"cards":[],"sweep":[{"number":32,"title":"b","clearedBy":[7]}],"flag":[]}' STUB_PLAN_RC=0
sweep_blocked_cards >/dev/null 2>&1
grep -qx "move PVTI_32 Ready" "$TMP/writes" && ok "re-blocked on a different blocker: swept again once it closes" \
  || fail "card #32 re-blocked on a different blocker stays Blocked for the rest of the daemon's life"
#     Cùng bộ blocker viết khác thứ tự / lặp lại vẫn là cùng một bộ: không sweep lần nữa.
: > "$TMP/writes"; SWEPT_CARDS=""
export STUB_PLAN='{"cards":[],"sweep":[{"number":34,"title":"d","clearedBy":[7,9]}],"flag":[]}' STUB_PLAN_RC=0
items 34 Blocked '["bug"]'; sweep_blocked_cards >/dev/null 2>&1; : > "$TMP/writes"
export STUB_PLAN='{"cards":[],"sweep":[{"number":34,"title":"d","clearedBy":[9,7,7]}],"flag":[]}' STUB_PLAN_RC=0
sweep_blocked_cards >/dev/null 2>&1
grep -q "PVTI_34" "$TMP/writes" && fail "same blockers in another order swept again (ping-pong)" || ok "same blocker set in another order is the same key"

# ── 2h. thẻ bị kéo tay sang Blocked, không có blocker nào (clearedBy rỗng): không có gì vừa đóng, giữ nguyên.
: > "$TMP/writes"; SWEPT_CARDS=""
items 33 Blocked '["feature"]'
export STUB_PLAN='{"cards":[],"sweep":[{"number":33,"title":"c","clearedBy":[]}],"flag":[]}' STUB_PLAN_RC=0
sweep_blocked_cards >/dev/null 2>&1
grep -q "PVTI_33" "$TMP/writes" && fail "card #33 with no blocker moved to Ready" || ok "card with an empty clearedBy stays Blocked"

# ── 2g. runaway ở chế độ daemon: vẫn báo và vẫn có giới hạn (tạm dừng), không bao giờ reset im lặng.
#     Tạm dừng là một hạn chót, không phải sleep: vòng giám sát (thu hồi lock, zombie) vẫn chạy mỗi tick.
: > "$TMP/log"; TICK_SECONDS=30; NO_PROGRESS_CYCLES=3; NO_PROGRESS_CYCLE_COUNT=3; RUNAWAY_PAUSE_UNTIL=0
t0=$(date +%s)
SB_DAEMON=1 runaway_action >/dev/null 2>&1; rc=$?
took=$(( $(date +%s) - t0 ))
[ "$rc" -eq 0 ] && grep -q "RUNAWAY" "$TMP/log" && [ "$NO_PROGRESS_CYCLE_COUNT" -eq 0 ] && [ "$took" -lt 5 ] \
  && ok "daemon runaway: logged, counter reset, returns at once (no blocking sleep)" \
  || fail "daemon runaway: rc=$rc count=$NO_PROGRESS_CYCLE_COUNT took=${took}s log=$(cat "$TMP/log")"
dispatch_paused && ok "daemon runaway: new dispatch paused until the deadline" || fail "daemon runaway: dispatch not paused"
#     Tick trong lúc tạm dừng không được đếm là "không tiến triển", nếu không hạn chót bị gia hạn mãi.
PREV_DONE_SIG="x"; NO_PROGRESS_CYCLES=6; NO_PROGRESS_CYCLE_COUNT=0
for _ in 1 2 3 4 5 6 7; do record_cycle_progress "x" || break; done
[ "$NO_PROGRESS_CYCLE_COUNT" -eq 0 ] && ok "paused ticks do not count toward the next runaway" \
  || fail "paused ticks counted: NO_PROGRESS_CYCLE_COUNT=$NO_PROGRESS_CYCLE_COUNT (the pause would extend forever)"
RUNAWAY_PAUSE_UNTIL=1
dispatch_paused && fail "dispatch still paused after the deadline" || ok "dispatch resumes after the deadline"
TICK_SECONDS=0
: > "$TMP/log"
SB_DAEMON=0 runaway_action >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q "RUNAWAY" "$TMP/log" && ok "non-daemon runaway: halts" || fail "non-daemon runaway: rc=$rc (want 1)"

# ── 3. khởi động lại: worker do runner trước tạo được nhận lại vào lane, để lane không bị giao trùng
#    (2026-10-16: runner khởi động lại thấy mọi lane rảnh trong khi Builder cũ vẫn chạy).
reset_lanes; rm -f "$INFLIGHT_DIR"/*
# Dòng lệnh của worker thật mang prompt ("… for super-board run …"); `; :` để bash không exec thẳng sleep.
bash -c 'sleep 300; :' 'Run super-build on issue #21 for super-board run.' >/dev/null 2>&1 & live=$!; WORKERS="$WORKERS $live"
worker; recycled=$W   # PID còn sống nhưng không phải worker (PID trong lock bị dùng lại sau khi khởi động lại máy)
printf 'PID=%s\nLANE=build\nSTARTED=2026-10-16T00:00:00Z\n' "$live" > "$INFLIGHT_DIR/21"
printf 'PID=999999\nLANE=qa\nSTARTED=2026-10-16T00:00:00Z\n' > "$INFLIGHT_DIR/22"
printf 'PID=%s\nLANE=review\nSTARTED=2026-10-16T00:00:00Z\n' "$recycled" > "$INFLIGHT_DIR/24"
sleep 0.2 2>/dev/null || sleep 1
: > "$TMP/writes"; BOT_LOGIN="sb-bot"
adopt_live_locks >/dev/null 2>&1
BOT_LOGIN=""
[ "$BUILD_PID" = "$live" ] && [ "$BUILD_ISSUE" = 21 ] && ok "live build lock adopted into the build lane" \
  || fail "live build lock not adopted (BUILD_PID='$BUILD_PID' BUILD_ISSUE='$BUILD_ISSUE')"
[ -z "$QA_PID" ] && ok "dead qa lock not adopted" || fail "dead qa lock adopted (QA_PID='$QA_PID')"
[ -z "$REVIEW_PID" ] && ok "live PID that is no super-board worker not adopted" \
  || fail "recycled PID $recycled adopted into the review lane (the watchdog could later kill -9 it)"
#    PID tái dùng còn sống: issue_locked thấy kill -0 thành công và bỏ qua thẻ #24 mãi (tới khi tiến trình lạ đó
#    tự chết). Lock và assignee phải được gỡ để thẻ được giao lại; tiến trình lạ thì không bao giờ bị đụng tới.
[ ! -e "$INFLIGHT_DIR/24" ] && ok "recycled-PID lock removed" || fail "recycled-PID lock kept: card #24 skipped as 'already locked' forever"
grep -qx "gh issue edit 24 --remove-assignee sb-bot" "$TMP/writes" 2>/dev/null && ok "recycled-PID card's bot assignee removed" \
  || fail "recycled-PID card's assignee not removed (writes: $(cat "$TMP/writes" 2>/dev/null))"
issue_locked 24 && fail "issue_locked 24 still true: the card is never dispatched again" || ok "card #24 is dispatchable again"
alive "$recycled" && ok "the unrelated process behind the recycled PID is not signalled" || fail "the unrelated process $recycled was killed"
[ -e "$INFLIGHT_DIR/21" ] && ok "adopted worker's lock kept" || fail "adopted worker's lock removed"
#    `ps` lỗi hoặc không in gì (lỗi thoáng qua, quyền) cho một PID sống: không xác minh được, nên không nhận lại và
#    cũng KHÔNG gỡ lock (gỡ thì thẻ của một worker thật có thể bị giao cho worker thứ hai).
worker; unknown=$W
printf 'PID=%s\nLANE=qa\nSTARTED=2026-10-16T00:00:00Z\n' "$unknown" > "$INFLIGHT_DIR/25"
: > "$TMP/writes"; BOT_LOGIN="sb-bot"
ps() { case "$*" in *command=*) ;; *) command ps "$@" ;; esac; }   # chỉ `-o command=` trả rỗng
adopt_live_locks >/dev/null 2>&1
unset -f ps; BOT_LOGIN=""
[ -e "$INFLIGHT_DIR/25" ] && [ -e "$INFLIGHT_DIR/21" ] && ! grep -q "gh issue edit 2[15] " "$TMP/writes" 2>/dev/null \
  && ok "ps printed nothing for a live PID: lock and assignee kept (cannot verify, do not reap)" \
  || fail "ps printed nothing: lock reaped anyway (25=$([ -e "$INFLIGHT_DIR/25" ] && echo kept || echo gone) 21=$([ -e "$INFLIGHT_DIR/21" ] && echo kept || echo gone) writes: $(cat "$TMP/writes"))"
#    Dòng lệnh không khớp nhưng tiến trình KHÔNG khởi động sau STARTED của lock (worker ghi lock ngay sau khi khởi
#    tạo, nên PID tái dùng luôn khởi động muộn hơn): có thể là worker thật đã đổi tiêu đề tiến trình. Không gỡ.
worker; retitled=$W
future=$(python3 -c 'import time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 3600)))')
printf 'PID=%s\nLANE=build\nSTARTED=%s\n' "$retitled" "$future" > "$INFLIGHT_DIR/26"
: > "$TMP/writes"; BOT_LOGIN="sb-bot"
adopt_live_locks >/dev/null 2>&1
BOT_LOGIN=""
[ -e "$INFLIGHT_DIR/26" ] && ! grep -q "gh issue edit 26 " "$TMP/writes" 2>/dev/null \
  && ok "non-matching command line, process not started after the lock: kept (maybe a retitled live worker)" \
  || fail "lock 26 reaped on the command line alone (a live worker whose title changed gets a second worker)"
#    Parser etime nằm trên đường an toàn (sai tuổi thì lock của worker thật có thể bị gỡ): nhánh hh:mm:ss và
#    dd-hh:mm:ss của tiến trình chạy lâu (ca reboot thật), và STARTED trống/sai dạng phải trả 1 (không gỡ).
iso_in() { python3 -c 'import sys, time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + int(sys.argv[1]))))' "$1"; }
ps() { case "$*" in *etime=*) echo "  $FAKE_ETIME" ;; *) command ps "$@" ;; esac; }
for case_ in "1-02:03:04=93784" "02:03:04=7384"; do
  FAKE_ETIME=${case_%=*}; secs=${case_#*=}
  pid_started_after $$ "$(iso_in $(( -secs - 60 )))"; before=$?   # lock ghi 60 s TRƯỚC khi tiến trình khởi động
  pid_started_after $$ "$(iso_in $(( -secs + 60 )))"; after=$?    # lock ghi 60 s SAU: không phải PID tái dùng
  [ "$before" -eq 0 ] && [ "$after" -eq 1 ] && ok "etime '$FAKE_ETIME' read as ${secs}s (recycled vs not decided right)" \
    || fail "etime '$FAKE_ETIME' (${secs}s): started-after=$before (want 0), started-before=$after (want 1)"
done
unset -f ps
pid_started_after $$ ""; e1=$?; pid_started_after $$ garbage; e2=$?
[ "$e1" -eq 1 ] && [ "$e2" -eq 1 ] && ok "missing or malformed STARTED: never treated as a recycled PID" \
  || fail "STARTED '' -> $e1, 'garbage' -> $e2 (want 1 and 1: unknown must not reap)"
# Dừng khẩn chỉ kill worker do CHÍNH lần chạy này tạo (hợp đồng của halt_cleanup); worker nhận lại giữ được việc dở.
worker; QA_PID=$W; QA_ISSUE=23
own="$(own_lane_pids 2>/dev/null)"
case " $own " in *" $live "*) fail "halt would kill the adopted worker $live (own_lane_pids: '$own')" ;; *) ok "halt spares the adopted worker" ;; esac
case " $own " in *" $QA_PID "*) ok "halt still stops a worker this run launched" ;; *) fail "halt would not stop this run's worker $QA_PID (own_lane_pids: '$own')" ;; esac

# ── 3b. lệnh đọc cố định của chính runner (quota) gõ sai, vd gh nâng cấp đổi tên flag: vẫn halt board (79 + file
#    halt) như trước. github-read trả 64 cho lỗi cú pháp của worker ở mọi kind; runner không export
#    SB_GITHUB_READ_STRICT (worker sẽ thừa hưởng), nên đặt nó cho từng lệnh đọc của mình.
mkdir -p "$TMP/ghbin"
printf '#!/usr/bin/env bash\necho "unknown flag: --renamed" >&2\nexit 1\n' > "$TMP/ghbin/gh"; chmod +x "$TMP/ghbin/gh"
( SB_GITHUB_READ="$ROOT/.claude/bin/super-board-github-read.py"
  export PATH="$TMP/ghbin:$PATH" SB_GITHUB_HALT_FILE="$TMP/runner-halt.json" SB_GITHUB_RETRY_DELAY=0
  unset SB_GITHUB_READ_STRICT
  gh_rate_guard ) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 79 ] && [ -e "$TMP/runner-halt.json" ] && ok "runner's own quota read with a broken flag: board halted (79), as before" \
  || fail "runner's own quota read with a broken flag: rc=$rc halt=$([ -e "$TMP/runner-halt.json" ] && echo yes || echo no) (want 79 + halt)"
( SB_GITHUB_READ="$ROOT/.claude/bin/super-board-github-read.py"
  export PATH="$TMP/ghbin:$PATH" SB_GITHUB_HALT_FILE="$TMP/runner-halt2.json" SB_GITHUB_RETRY_DELAY=0
  unset SB_GITHUB_READ_STRICT
  SB_LIB_ONLY=1 . "$RUNNER"; set +e   # nạp lại issue_is_open thật (đầu file đã stub)
  issue_is_open 7 ) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 79 ] && [ -e "$TMP/runner-halt2.json" ] && ok "runner's own issue-state read with a broken flag: halt file written (79)" \
  || fail "runner's own issue-state read with a broken flag: rc=$rc halt=$([ -e "$TMP/runner-halt2.json" ] && echo yes || echo no) (exit 79 without a halt file: a restart fails again without the reason)"
#    Worker thừa hưởng môi trường của runner: STRICT chỉ được đặt theo từng lệnh, không bao giờ export. Lib mode không
#    tới phần chính của script, nên kiểm thêm nguồn: không dòng export/declare -x nào mang biến này.
[ -z "${SB_GITHUB_READ_STRICT:-}" ] && ! export -p | grep -q SB_GITHUB_READ_STRICT \
  && ! grep -qE '^[[:space:]]*(export|declare -x)[[:space:]].*SB_GITHUB_READ_STRICT' "$RUNNER" \
  && ok "runner never exports SB_GITHUB_READ_STRICT (per-call prefix only; workers do not inherit it)" \
  || fail "SB_GITHUB_READ_STRICT exported by the runner: every worker's mistyped read would halt the board again"

# ── 3c. khởi động sau reboot: Builder chết, thẻ ở Building, PID trong lock bị tiến trình khác dùng lại. Lock đó phải
#    được gỡ TRƯỚC bước trả thẻ Building bị bỏ rơi về Ready; nếu không reclaim thấy "lock sống", bỏ qua thẻ, rồi adopt
#    mới gỡ lock: thẻ nằm Building suốt lần chạy (không lane nào lấy từ Building).
reset_lanes; rm -f "$INFLIGHT_DIR"/*
worker; rec30=$W
printf 'PID=%s\nLANE=build\nSTARTED=2026-10-16T00:00:00Z\n' "$rec30" > "$INFLIGHT_DIR/30"
gh_rate_guard() { :; }
fetch_project_items() {
  PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_30","status":"Building","labels":["bug"],"content":{"type":"Issue","number":30,"assignees":["sb-bot"]}}]}'
}
: > "$TMP/writes"
( cd "$TMP" && BOT_LOGIN="sb-bot" && startup_reconcile ) >/dev/null 2>&1   # cd: reclaim gọi git ls-remote origin
grep -qx "move PVTI_30 Ready" "$TMP/writes" && [ ! -e "$INFLIGHT_DIR/30" ] && alive "$rec30" \
  && ok "startup: recycled-PID Building card reclaimed to Ready in the same run" \
  || fail "startup: recycled-PID Building card not moved to Ready (lock=$([ -e "$INFLIGHT_DIR/30" ] && echo kept || echo gone) writes: $(tr '\n' ';' < "$TMP/writes"))"

# ── 3d. runner thật chạy dưới set -euo pipefail: `git ls-remote origin` lỗi (mạng chập chờn, không có remote) lúc trả
#    thẻ Building bị bỏ rơi về Ready không được giết cả runner trước khi kịp chuyển thẻ (audit T0041).
reset_lanes; rm -f "$INFLIGHT_DIR"/*
fetch_project_items() {
  PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_31","status":"Building","labels":["bug"],"content":{"type":"Issue","number":31,"assignees":["sb-bot"]}}]}'
}
: > "$TMP/writes"
( set -euo pipefail; cd "$TMP"; BOT_LOGIN="sb-bot"; fetch_project_items; reclaim_stranded_building ) >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -qx "move PVTI_31 Ready" "$TMP/writes" \
  && ok "set -e: a failing git ls-remote does not kill the runner; stranded card still reclaimed" \
  || fail "set -e: reclaim died (rc=$rc) on a failing git ls-remote; writes: $(tr '\n' ';' < "$TMP/writes")"

# ── 4. đang hoãn sau RUNAWAY: tick thường không đọc GraphQL, nhưng cứ 3 tick đọc board một lần và quét zombie
#    trên dữ liệu MỚI. Trước đây cả khoảng hoãn chỉ quét trên cache cũ: worker có thẻ đã sang Done trong lúc hoãn
#    giữ lane tới hết hạn chót.
FETCHES=0
fetch_project_items() { FETCHES=$((FETCHES + 1)); items 41 Done '["bug"]'; }   # board thật: thẻ đã về Done
gh_rate_guard() { :; }
reset_lanes; worker; BUILD_PID=$W; BUILD_ISSUE=41; z41=$W
items 41 Building '["bug"]'      # cache cũ: thẻ còn ở Building nên chưa phải zombie
RUNAWAY_PAUSE_UNTIL=$(( $(date +%s) + 600 )); PAUSED_TICKS=0
paused_tick >/dev/null 2>&1; paused_tick >/dev/null 2>&1
[ "$FETCHES" -eq 0 ] && alive "$z41" && ok "paused ticks 1-2: no board read" || fail "paused ticks 1-2: fetches=$FETCHES (want 0)"
paused_tick >/dev/null 2>&1
[ "$FETCHES" -eq 1 ] && [ -z "$BUILD_PID" ] && ! alive "$z41" && ok "paused tick 3: board read, zombie on the fresh board reaped" \
  || fail "paused tick 3: fetches=$FETCHES BUILD_PID='$BUILD_PID' (zombie whose card reached Done keeps its lane through the pause)"
paused_tick >/dev/null 2>&1; paused_tick >/dev/null 2>&1; paused_tick >/dev/null 2>&1
[ "$FETCHES" -eq 2 ] && ok "pause reads the board sparsely: 2 reads in 6 ticks" || fail "6 paused ticks made $FETCHES reads (want 2)"
RUNAWAY_PAUSE_UNTIL=0

# ── 5. chặn worker mồ côi lúc khởi động (2026-10-16): mẫu cũ `pgrep -f 'claude -p .*super-board run'` không khớp
#    dòng lệnh thật (`claude --dangerously-skip-permissions -p …`, agy/grok cũng vậy) và không giới hạn theo repo:
#    21:52 nó khớp một tiến trình khác nên runner OfficeReader và Goods từ chối khởi động. Worker còn sống có lock
#    đã được adopt_live_locks nhận lại, nên chỉ worker CỦA REPO NÀY mà không có lock mới chặn. Bảng tiến trình giả
#    lập theo đúng dạng `ps -ww -A -o pid=,command=` đo ngày 16/10.
R="/Volumes/X/Repo"
wl() {   # wl <pid> <argv0 + cờ> <root> <issue>: một dòng worker đúng dạng prompt của dispatch_lane
  printf "%s %s -p First operation: run .claude/bin/super-board-skills-ready.py --root '%s' --host claude --cards - --lane 'build' --hydrate with [] as stdin. Run super-build on issue #%s for super-board run. Config: x.\n" "$1" "$2" "$3" "$4"
}
{
  wl 4101 "claude --dangerously-skip-permissions" "$R" 5             # repo này, có lock
  wl 4102 "claude --dangerously-skip-permissions" "$R" 6             # repo này, KHÔNG lock
  wl 4103 "claude --dangerously-skip-permissions" "/Volumes/X/Other" 7   # repo khác
  wl 4104 "claude --dangerously-skip-permissions" "$R-2" 8           # repo khác có tên bắt đầu bằng tên repo này
  wl 4105 "/Users/u/.local/bin/agy --model gemini-4-argon-high --effort xhigh --dangerously-skip-permissions" "$R" 9
  wl 4106 "/Users/u/.grok/bin/grok -m grok-4.7" "$R" 10
  echo "4107 /bin/zsh -c grep -c \"claude -p --root '$R' for super-board run\" runner.log"   # shell chẩn đoán, không phải worker
  echo "4108 bash $R/.claude/bin/super-board-run.sh repo"
} > "$TMP/ps.txt"
ps() { case "$*" in *command=*) cat "$TMP/ps.txt" ;; *) command ps "$@" ;; esac; }
pgrep() {   # pgrep -f <mẫu> trên bảng giả
  local pat=""; while [ $# -gt 0 ]; do [ "$1" = "-f" ] && { shift; pat="$1"; }; shift; done
  grep -E -- "$pat" "$TMP/ps.txt" | awk '{print $1}'
}
rm -f "$INFLIGHT_DIR"/*
printf 'PID=4101\nLANE=build\nSTARTED=2026-10-16T00:00:00Z\n' > "$INFLIGHT_DIR/5"
orph=" $(startup_orphan_workers "$R" 2>/dev/null | tr '\n' ' ') "
case "$orph" in *" 4102 "*) ok "unlocked worker of this repo blocks start" ;; *) fail "unlocked worker 4102 of this repo not detected (got:$orph)" ;; esac
case "$orph" in *" 4101 "*) fail "worker with a lock blocks start (got:$orph): adopt_live_locks already takes it back" ;; *) ok "worker with a lock does not block" ;; esac
case "$orph" in *" 4103 "*|*" 4104 "*) fail "another repo's worker blocks start (got:$orph)" ;; *) ok "other repos' workers (incl. a name-prefix repo) do not block" ;; esac
case "$orph" in *" 4105 "*) case "$orph" in *" 4106 "*) ok "unlocked agy and grok workers of this repo block" ;; *) fail "grok worker 4106 not detected (got:$orph)" ;; esac ;; *) fail "agy worker 4105 not detected (got:$orph)" ;; esac
case "$orph" in *" 4107 "*|*" 4108 "*) fail "non-worker process blocks start (got:$orph)" ;; *) ok "a shell or the runner whose args name this repo does not block" ;; esac
#    Không có worker nào: runner chạy với set -euo pipefail, grep không khớp không được làm chết lúc khởi động.
: > "$TMP/ps.txt"
(set -euo pipefail; o=$(startup_orphan_workers "$R"); [ -z "$o" ]) && ok "no workers: empty result, survives set -euo pipefail" \
  || fail "no workers: startup_orphan_workers fails or prints something under set -euo pipefail"
unset -f ps pgrep
rm -f "$INFLIGHT_DIR"/*

[ "$FAILS" -eq 0 ] && echo "✅ test_runner_lanes: all passed" || { echo "❌ test_runner_lanes: $FAILS failed"; exit 1; }
