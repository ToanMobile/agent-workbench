#!/usr/bin/env bash
# Test (#209): lane QA và Review chạy NHIỀU worker như lane build.
#  - config `qa_workers` / `review_workers` = trần mỗi lane (mặc định capacity lane_workers — T0052, 12 lõi: 3 —; capacity vắng thì 1 =
#    hành vi cũ);
#  - mỗi tick một lane chỉ khởi THÊM tối đa một worker, và worker thêm chỉ khi tải 1 phút < build_load_max (cùng cổng với build);
#  - thẻ bị kéo khỏi cột thì worker thêm bị giết như zombie; worker chết thì slot trả lại; dừng khẩn / nhận lại lúc khởi động nhận ra cả N worker;
#  - lane đã có worker thì worker thêm không bị trần max_workers (số lane) chặn.
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

# #252: số gate thật trên máy không được chi phối test; 0 = không có gate nào đang chạy
printf "0\n" > "$TMP/gates0"; export SB_GATE_COUNT_FILE="$TMP/gates0"
unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL SB_BUILD_LOAD_MAX DEVKIT_SLOT_LOAD_MAX DEVKIT_CAPACITY SB_CAPACITY
# T0052: máy giả 12 lõi rảnh cho nguồn sức chứa chung (bin/capacity.py): lane_workers 3, không lệ thuộc máy chạy test
export DEVKIT_CAPACITY_CORES=12 DEVKIT_CAPACITY_LOAD=0
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
MAX_WORKERS=3; ACTIVE_WORKERS=0; BUILD_LOAD_MAX=8
reset() {
  for p in $QA_PID $REVIEW_PID ${QA_EXTRA:-} ${REVIEW_EXTRA:-}; do kill "${p%%:*}" 2>/dev/null; wait "${p%%:*}" 2>/dev/null; done
  QA_PID=""; QA_ISSUE=""; QA_EXTRA=""; REVIEW_PID=""; REVIEW_ISSUE=""; REVIEW_EXTRA=""
  rm -f "$INFLIGHT_DIR"/[0-9]*; : > "$TMP/log"; : > "$TMP/writes"; ACTIVE_WORKERS=0; MAX_WORKERS=3
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

# ── 4. không có khoá config → capacity lane_workers (T0052, 12 lõi: 3); capacity vắng → mỗi lane đúng một worker như cũ
cfg_with() { printf '%s\n' "$1" > "$TMP/c.json"; }
cfg_with '{}'; q=$(resolve_lane_workers "$TMP/c.json" qa_workers); r=$(resolve_lane_workers "$TMP/c.json" review_workers)
[ "$q $r" = "3 3" ] && ok "no qa_workers / review_workers key: both default to capacity lane_workers (3 on 12 cores)" || fail "defaults: $q $r (want 3 3)"
q=$(SB_CAPACITY=/nonexistent resolve_lane_workers "$TMP/c.json" qa_workers); r=$(SB_CAPACITY=/nonexistent resolve_lane_workers "$TMP/c.json" review_workers)
[ "$q $r" = "1 1" ] && ok "  … capacity vắng (SB_CAPACITY=/nonexistent): cả hai về 1 như cũ" || fail "capacity vắng: $q $r (muốn 1 1)"
cfg_with '{"qa_workers": 3, "review_workers": 2}'; q=$(resolve_lane_workers "$TMP/c.json" qa_workers); r=$(resolve_lane_workers "$TMP/c.json" review_workers)
[ "$q $r" = "3 2" ] && ok "  … the keys are honoured" || fail "keys: $q $r"
for bad in '"x"' 0 -3 2.5 '"000"' 99999999999999999999; do cfg_with "{\"qa_workers\": $bad}"; q=$(resolve_lane_workers "$TMP/c.json" qa_workers)
  q1=$(SB_CAPACITY=/nonexistent resolve_lane_workers "$TMP/c.json" qa_workers)
  [ "$q $q1" = "3 1" ] && ok "  … an invalid qa_workers ($bad) falls back to capacity (3), or 1 without capacity" || fail "qa_workers=$bad gave '$q' / '$q1' (want 3 / 1)"; done
reset; QA_WORKERS=1; REVIEW_WORKERS=1; load 0.1; cards QA 1 2 3; tick_qa; tick_qa; tick_qa; q=$(qa_count)
[ "$q" = 1 ] && [ -z "${QA_EXTRA:-}" ] && ok "qa_workers=1: one tester, no extra slot — as before" || fail "qa_workers=1: $q workers, QA_EXTRA='${QA_EXTRA:-}'"
reset; cards Review 5 6 7; tick_review; tick_review; r=$(review_count)
[ "$r" = 1 ] && ok "review_workers=1: one reviewer — as before" || fail "review_workers=1: $r workers"

# ── 5. cổng tải: tải cao giữ ở worker đầu (worker đầu không bị tải chặn), không giết worker đang chạy; tải không đọc được = fail closed
reset; QA_WORKERS=3; load 2; cards QA 1 2 3; tick_qa; first=$QA_PID
load 11.4; tick_qa; tick_qa; q=$(qa_count)
[ "$q" = 1 ] && kill -0 "$first" 2>/dev/null && ok "high load: no tester added, the running one is not killed" || fail "high load: $q workers"
grep -q "qa workers 1/3: load 11.4 >= 8: holding" "$TMP/log" && ok "  … and the log says holding" || fail "no holding line: $(tr '\n' '|' < "$TMP/log")"
reset; QA_WORKERS=3; load 50; cards QA 1 2; tick_qa; q=$(qa_count)
[ "$q" = 1 ] && ok "  … the FIRST tester starts even under high load" || fail "first tester blocked by load: $q"
for bad in "" abc; do reset; REVIEW_WORKERS=3; load "$bad"; cards Review 5 6 7; tick_review; tick_review; tick_review; r=$(review_count)
  [ "$r" = 1 ] && ok "unreadable load ('${bad:-empty}'): stays at one reviewer" || fail "unreadable load ('${bad:-empty}'): $r reviewers"; done

# ── 6. lane đã có worker: worker thêm không bị trần max_workers chặn (lane = 1 slot); lane rảnh thì vẫn bị chặn khi đủ lane
reset; QA_WORKERS=3; load 2; cards QA 1 2 3; tick_qa      # worker đầu
ACTIVE_WORKERS=3; MAX_WORKERS=3                              # build + qa + review đều bận
tick_qa; q=$(qa_count)
[ "$q" = 2 ] && ok "all 3 lanes busy (ACTIVE=MAX): the QA lane still adds its 2nd tester" || fail "extra tester blocked by max_workers: $q"
[ "$ACTIVE_WORKERS" = 3 ] && ok "  … and an extra worker does not take another max_workers slot" || fail "ACTIVE_WORKERS=$ACTIVE_WORKERS (want 3)"
reset; QA_WORKERS=3; load 2; cards QA 1; ACTIVE_WORKERS=3; MAX_WORKERS=3; tick_qa; q=$(qa_count)
[ "$q" = 0 ] && ok "  … an IDLE lane is still gated by max_workers (cap unchanged)" || fail "idle lane started at ACTIVE=MAX: $q"
reset; QA_WORKERS=3; load 2; cards QA 1; ACTIVE_WORKERS=0; tick_qa
[ "$ACTIVE_WORKERS" = 1 ] && ok "  … the first worker of a lane takes one slot" || fail "ACTIVE_WORKERS=$ACTIVE_WORKERS (want 1)"

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

# ── 9. cái dây vòng chính
grep -q '^QA_WORKERS=$(resolve_lane_workers "$CONFIG_PATH" qa_workers)' "$RUNNER" && grep -q '^REVIEW_WORKERS=$(resolve_lane_workers "$CONFIG_PATH" review_workers)' "$RUNNER" \
  && ok "runner reads qa_workers / review_workers through resolve_lane_workers at startup" || fail "startup config read does not use the resolver"
grep -q 'lane_dispatch_tick review Review' "$RUNNER" && grep -q 'lane_dispatch_tick qa QA' "$RUNNER" \
  && ok "the main loop dispatches QA and Review through lane_dispatch_tick" || fail "main loop does not call lane_dispatch_tick"
grep -n 'QA_IDLE=\|REVIEW_IDLE=' "$RUNNER" | grep -q 'lane_idle "\$QA_PID"\|lane_idle "\$REVIEW_PID"' \
  && fail "the main loop still derives QA/Review idleness from the first PID only" || ok "  … QA/Review idleness comes from the worker count, not the first PID"
# T0052: config agent-workbench bỏ qa_workers / review_workers; kết quả đọc qua resolve_lane_workers vẫn là 3/3 trên 12 lõi (capacity)
AW_CFG="$ROOT/.claude/super-board/configs/agent-workbench.json"
cfg="$(resolve_lane_workers "$AW_CFG" qa_workers) $(resolve_lane_workers "$AW_CFG" review_workers)"
[ "$cfg" = "1 1" ] && ok "agent-workbench config pins qa_workers=1, review_workers=1 (23/10: machine overloaded, user lowered the load)" || fail "agent-workbench config resolves to '$cfg' (want 1 1)"

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
