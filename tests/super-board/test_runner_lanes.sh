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
adopt_live_locks >/dev/null 2>&1
[ "$BUILD_PID" = "$live" ] && [ "$BUILD_ISSUE" = 21 ] && ok "live build lock adopted into the build lane" \
  || fail "live build lock not adopted (BUILD_PID='$BUILD_PID' BUILD_ISSUE='$BUILD_ISSUE')"
[ -z "$QA_PID" ] && ok "dead qa lock not adopted" || fail "dead qa lock adopted (QA_PID='$QA_PID')"
[ -z "$REVIEW_PID" ] && ok "live PID that is no super-board worker not adopted" \
  || fail "recycled PID $recycled adopted into the review lane (the watchdog could later kill -9 it)"
# Dừng khẩn chỉ kill worker do CHÍNH lần chạy này tạo (hợp đồng của halt_cleanup); worker nhận lại giữ được việc dở.
worker; QA_PID=$W; QA_ISSUE=23
own="$(own_lane_pids 2>/dev/null)"
case " $own " in *" $live "*) fail "halt would kill the adopted worker $live (own_lane_pids: '$own')" ;; *) ok "halt spares the adopted worker" ;; esac
case " $own " in *" $QA_PID "*) ok "halt still stops a worker this run launched" ;; *) fail "halt would not stop this run's worker $QA_PID (own_lane_pids: '$own')" ;; esac

[ "$FAILS" -eq 0 ] && echo "✅ test_runner_lanes: all passed" || { echo "❌ test_runner_lanes: $FAILS failed"; exit 1; }
