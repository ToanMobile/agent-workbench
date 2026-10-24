#!/usr/bin/env bash
# Test (#209): lane QA và Review chạy NHIỀU worker như lane build.
#  - config `qa_workers` / `review_workers` = trần mỗi lane (mặc định 1 = hành vi cũ);
#  - mỗi tick một lane chỉ khởi THÊM tối đa một worker, tới trần lane (= max_workers, chung với build; xem test_runner_total_cap.sh);
#  - thẻ bị kéo khỏi cột thì worker thêm bị giết như zombie; worker chết thì slot trả lại; dừng khẩn / nhận lại lúc khởi động nhận ra cả N worker;
# Chạy offline: runner source ở lib mode, gh/claude là stub, tải đọc từ file. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-lane-workers.XXXXXX")"
WORKERS=""
cleanup() { for w in $WORKERS; do kill "$w" 2>/dev/null; done; for p in $(pgrep -f "$TMP/path/claude" 2>/dev/null); do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/repo/docs/super-board" "$TMP/repo/wl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
printf '#!/usr/bin/env bash\nsleep 300\n' > "$TMP/path/claude"
chmod +x "$TMP/bin/super-board-github-read.py" "$TMP/path/claude"
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0

unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL SB_BUILD_LOAD_MAX DEVKIT_SLOT_LOAD_MAX
export SB_ZOMBIE_GRACE=0  # test kill trực tiếp, không chờ ân hạn (#237)
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
CONFIG_PATH="$TMP/cfg.json"; echo '{}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="wl"; REPO_ROOT="$TMP/repo"; BOT_LOGIN="bot"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
issue_is_open() { return 0; }
resolve_worker_account() { POOL_ENGINE=""; POOL_ACCT=""; POOL_CFG=""; return 0; }
note_worker_limit() { :; }
cd "$TMP/repo" || exit 1
git init -q . 2>/dev/null
cards() {   # cards <status> <n>...: bảng chỉ có các thẻ đó ở cột <status>
  local st="$1" out="" n; shift
  for n in "$@"; do out="${out:+$out,}{\"id\":\"PVTI_$n\",\"status\":\"$st\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$n,\"assignees\":[]}}"; done
  PROJECT_ITEMS_JSON="{\"items\":[$out]}"
}
load() { printf '%s\n' "$1" > "$TMP/load"; export SB_BUILD_LOAD_FILE="$TMP/load"; }
BUILD_PID=""; BUILD_ISSUE=""; BUILD_EXTRA=""
QA_PID=""; QA_ISSUE=""; QA_EXTRA=""; REVIEW_PID=""; REVIEW_ISSUE=""; REVIEW_EXTRA=""
MAX_WORKERS=10; ACTIVE_WORKERS=0
reset() {
  for p in $QA_PID $REVIEW_PID ${QA_EXTRA:-} ${REVIEW_EXTRA:-}; do kill "${p%%:*}" 2>/dev/null; wait "${p%%:*}" 2>/dev/null; done
  QA_PID=""; QA_ISSUE=""; QA_EXTRA=""; REVIEW_PID=""; REVIEW_ISSUE=""; REVIEW_EXTRA=""
  rm -f "$INFLIGHT_DIR"/[0-9]*; : > "$TMP/log"; : > "$TMP/writes"; ACTIVE_WORKERS=0; MAX_WORKERS=10
}
tick_qa() { reap_finished_locks; lane_dispatch_tick qa QA; }          # đúng nhịp của vòng chính cho lane qa
tick_review() { reap_finished_locks; lane_dispatch_tick review Review; }
qa_count() { lane_workers_count qa; echo "$LANE_COUNT"; }
review_count() { lane_workers_count review; echo "$LANE_COUNT"; }

# ── 1. qa_workers=3, 4 thẻ QA: 3 tester, thẻ thứ 4 chờ (mỗi tick một worker)
reset; QA_WORKERS=3; load 2; cards QA 1 2 3 4
tick_qa; a=$(qa_count); tick_qa; b=$(qa_count); tick_qa; c=$(qa_count); tick_qa; d=$(qa_count)
[ "$a $b $c $d" = "1 2 3 3" ] && ok "qa_workers=3, 4 QA cards: 1, 2, 3 testers over 3 ticks, the 4th card waits" || fail "qa workers over 4 ticks: $a $b $c $d (want 1 2 3 3)"
left=0; for n in 1 2 3 4; do [ -f "$INFLIGHT_DIR/$n" ] || left=$((left + 1)); done
[ "$left" = 1 ] && ok "  … exactly one card holds no lock (the waiting one)" || fail "$left cards without a lock (want 1)"
grep -c "dispatch lane=qa" "$TMP/log" | grep -q '^3$' && ok "  … three dispatch lines, all lane=qa" || fail "dispatch log: $(tr '\n' '|' < "$TMP/log")"

# ── 2. review_workers=2, 3 thẻ Review: 2 reviewer; merge gate vẫn tuần tự qua khoá hiện có
reset; REVIEW_WORKERS=2; load 2; cards Review 5 6 7
tick_review; tick_review; tick_review; r=$(review_count)
[ "$r" = 2 ] && ok "review_workers=2, 3 Review cards: 2 reviewers, the 3rd card waits" || fail "review workers: $r (want 2)"
grep -q 'LOCK_DIR="${REPO_PATH}/.claude/super-board/inflight/merge.lock"' "$ROOT/.claude/bin/super-board-merge-gate.sh" \
  && ok "  … the merge gate still serialises behind its merge.lock (reviewers may overlap, merges do not)" || fail "merge gate lost its merge.lock"

# ── 3. thẻ bị kéo khỏi cột → worker thêm bị giết như zombie, worker còn thẻ ở cột thì sống
reset; QA_WORKERS=3; load 2; cards QA 1 2 3; tick_qa; tick_qa; tick_qa
pid2=$(sed -n 's/^dispatch lane=qa issue=#2 pid=\([0-9]*\).*/\1/p' "$TMP/log")
cards QA 1 3; PROJECT_ITEMS_JSON=$(echo "$PROJECT_ITEMS_JSON" | jq -c '.items += [{"id":"PVTI_2","status":"Review","labels":[],"content":{"type":"Issue","number":2,"assignees":[]}}]')
QA_SEEN_IN_QA=""; sweep_lane_zombies; sleep 0.3; c=$(qa_count)
[ "$c" = 2 ] && ! kill -0 "$pid2" 2>/dev/null && ok "qa zombie sweep kills only the tester whose card left QA (#2); the other two live" || fail "qa zombie: $c workers, #2 pid $pid2 alive=$(kill -0 "$pid2" 2>/dev/null && echo y || echo n)"
reset; REVIEW_WORKERS=2; load 2; cards Review 5 6; tick_review; tick_review
pid6=$(sed -n 's/^dispatch lane=review issue=#6 pid=\([0-9]*\).*/\1/p' "$TMP/log")
cards Review 5; PROJECT_ITEMS_JSON=$(echo "$PROJECT_ITEMS_JSON" | jq -c '.items += [{"id":"PVTI_6","status":"Done","labels":[],"content":{"type":"Issue","number":6,"assignees":[]}}]')
sweep_lane_zombies; sleep 0.3; r=$(review_count)
[ "$r" = 1 ] && ! kill -0 "$pid6" 2>/dev/null && ok "review zombie sweep kills only the reviewer whose card left Review (#6)" || fail "review zombie: $r workers, #6 alive=$(kill -0 "$pid6" 2>/dev/null && echo y || echo n)"

# ── 4. không có khoá config → mỗi lane đúng một worker như cũ
reset; QA_WORKERS=1; REVIEW_WORKERS=1; load 0.1; cards QA 1 2 3; tick_qa; tick_qa; tick_qa; q=$(qa_count)
[ "$q" = 1 ] && [ -z "${QA_EXTRA:-}" ] && ok "qa_workers=1: one tester, no extra slot — as before" || fail "qa_workers=1: $q workers, QA_EXTRA='${QA_EXTRA:-}'"
reset; cards Review 5 6 7; tick_review; tick_review; r=$(review_count)
[ "$r" = 1 ] && ok "review_workers=1: one reviewer — as before" || fail "review_workers=1: $r workers"

# ── 7. worker chết → số đếm giảm, lock bị gỡ, tick sau khởi lại thẻ khác
reset; QA_WORKERS=2; load 1; cards QA 1 2 3; tick_qa; tick_qa
kill "$QA_PID" 2>/dev/null; wait "$QA_PID" 2>/dev/null; q=$(qa_count)
[ "$q" = 1 ] && ok "a dead tester is dropped from the count" || fail "after a tester died: $q workers"
cards QA 3; tick_qa; q=$(qa_count)
[ "$q" = 2 ] && ok "  … and the freed slot is filled on the next tick" || fail "freed slot not refilled: $q"
reset; QA_WORKERS=2; load 1; cards QA 1 2; tick_qa; tick_qa
extra_pid="${QA_EXTRA%%:*}"; extra_issue="${QA_EXTRA#*:}"; kill "$extra_pid" 2>/dev/null; wait "$extra_pid" 2>/dev/null
reap_finished_locks
[ ! -f "$INFLIGHT_DIR/$extra_issue" ] && grep -q "gh issue edit $extra_issue --remove-assignee bot" "$TMP/writes" && ok "reap_finished_locks reaps a dead extra tester's lock and sweeps its assignee" || fail "extra tester lock not reaped (lock=$([ -f "$INFLIGHT_DIR/$extra_issue" ] && echo present || echo gone))"

# ── 8. dừng khẩn / nhận lại lúc khởi động nhận ra cả N worker mỗi lane
reset; QA_WORKERS=3; REVIEW_WORKERS=2; load 1; cards QA 1 2 3; tick_qa; tick_qa; tick_qa
cards Review 5 6; PROJECT_ITEMS_JSON=$(echo "$PROJECT_ITEMS_JSON" | jq -c '.items += [{"id":"PVTI_1","status":"QA","labels":[],"content":{"type":"Issue","number":1,"assignees":[]}}]')
tick_review; tick_review
own="$(own_lane_pids)"; n=$(printf '%s\n' "$own" | grep -c .)
[ "$n" = 5 ] && ok "own_lane_pids lists all 3 testers + 2 reviewers (halt stops every one)" || fail "own_lane_pids: '$(echo $own)' ($n)"
reset
sleep 300 & a=$!; sleep 300 & b=$!; sleep 300 & c=$!; sleep 300 & d=$!; WORKERS="$WORKERS $a $b $c $d"
for pair in "$a:41:qa" "$b:42:qa" "$c:51:review" "$d:52:review"; do
  printf 'PID=%s\nLANE=%s\nSTARTED=%s\n' "${pair%%:*}" "${pair##*:}" "$(date -u +%FT%TZ)" > "$INFLIGHT_DIR/$(echo "$pair" | cut -d: -f2)"; done
real_ps=$(command -v ps)
ps() { case "$*" in *"-p $a"*) echo "claude -p Run super-qa on issue #41 for super-board run" ;; *"-p $b"*) echo "claude -p Run super-qa on issue #42 for super-board run" ;;
  *"-p $c"*) echo "claude -p Run super-review on issue #51 for super-board run" ;; *"-p $d"*) echo "claude -p Run super-review on issue #52 for super-board run" ;; *) "$real_ps" "$@" ;; esac; }
adopt_live_locks; q=$(qa_count); r=$(review_count)
[ "$q $r" = "2 2" ] && ok "adopt_live_locks puts every live tester and reviewer back into its lane (no duplicate start after a restart)" || fail "adopt: qa=$q review=$r (QA_PID='$QA_PID' QA_EXTRA='${QA_EXTRA:-}' REVIEW_PID='$REVIEW_PID' REVIEW_EXTRA='${REVIEW_EXTRA:-}')"
unset -f ps
QA_PID=""; QA_EXTRA=""; REVIEW_PID=""; REVIEW_EXTRA=""

# ── 8b. #288: PID của Tester đã chết phải rời QA_SEEN_IN_QA, không thì Tester mới tái dùng PID đó thừa hưởng "đã thấy ở QA".
reset; QA_WORKERS=2; load 1; cards QA 1 2; tick_qa; tick_qa
dead_pid="${QA_EXTRA%%:*}"; live_pid="$QA_PID"; QA_SEEN_IN_QA="$dead_pid $live_pid"
kill "$dead_pid" 2>/dev/null; wait "$dead_pid" 2>/dev/null; reap_finished_locks
case " $QA_SEEN_IN_QA " in *" $dead_pid "*) fail "reap kept the dead tester's PID in QA_SEEN_IN_QA ('$QA_SEEN_IN_QA')" ;;
  *) case " $QA_SEEN_IN_QA " in *" $live_pid "*) ok "reap drops a dead tester's PID from QA_SEEN_IN_QA and keeps the live one" ;; *) fail "reap dropped the live tester too ('$QA_SEEN_IN_QA')" ;; esac ;; esac

# ── 8c. #288: tick rẻ (bỏ qua GraphQL) khi repo đã đủ max_workers worker.
tick_is_cheap_with() { ACTIVE_WORKERS=$1; MAX_WORKERS=$2; tick_is_cheap && echo cheap || echo full; }
r=$(tick_is_cheap_with 3 3); [ "$r" = cheap ] && ok "ACTIVE=MAX: cheap tick" || fail "at the cap: $r (want cheap)"
r=$(tick_is_cheap_with 1 3); [ "$r" = full ] && ok "  … below the cap: full tick" || fail "below the cap: $r (want full)"
MAX_WORKERS=10

# ── 8d. #288: Ready không có thẻ nào thì không hỏi lane_slot_free qa (mỗi tick một lần hỏi + một dòng log vô ích).
reset; QA_WORKERS=2; load 1; cards QA 1; tick_qa; : > "$TMP/log"
r=$(ready_qa_lane_free 0 && echo free || echo no); n=$(grep -c "qa workers" "$TMP/log")
[ "$r" = no ] && [ "$n" = 0 ] && ok "READY=0: the Ready→qa slot check is skipped (no lane_slot_free call, no log line)" || fail "READY=0: '$r', $n log lines"
r=$(ready_qa_lane_free 1 && echo free || echo no)
[ "$r" = free ] && ok "  … READY=1 with a free QA lane: free" || fail "READY=1: '$r' (want free)"

# ── 9. cái dây vòng chính
grep -q '^QA_WORKERS=\$MAX_WORKERS' "$RUNNER" && grep -q '^REVIEW_WORKERS=\$MAX_WORKERS' "$RUNNER" \
  && ok "runner ties qa / review lane caps to max_workers at startup" || fail "startup lane caps are not tied to max_workers"
grep -q 'lane_dispatch_tick review Review' "$RUNNER" && grep -q 'lane_dispatch_tick qa QA' "$RUNNER" \
  && ok "the main loop dispatches QA and Review through lane_dispatch_tick" || fail "main loop does not call lane_dispatch_tick"
grep -q '^  if tick_is_cheap; then' "$RUNNER" && grep -q 'ready_qa_lane_free "\$READY"' "$RUNNER" \
  && ok "the main loop uses tick_is_cheap and ready_qa_lane_free (#288)" || fail "main loop is not wired to tick_is_cheap / ready_qa_lane_free"

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
