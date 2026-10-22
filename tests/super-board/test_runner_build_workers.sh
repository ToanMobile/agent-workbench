#!/usr/bin/env bash
# Test: lane build chạy NHIỀU worker, số worker theo tải máy (người dùng 21/10: "chạy theo workload cpu, không cố định số lượng").
#  - config `build_workers` = trần trên (mặc định 10; đặt 1 để về một worker);
#  - mỗi tick lane build chỉ khởi THÊM tối đa một worker, và chỉ khi tải 1 phút < build_load_max (mặc định DEVKIT_SLOT_LOAD_MAX, thiếu thì 100);
#  - tải tăng không giết worker đang chạy, chỉ ngừng khởi thêm; tải không đọc được = không quá worker đầu tiên (fail closed);
#  - mỗi tick log quyết định; dừng khẩn / nhận lại lúc khởi động / quét zombie nhận ra cả N worker.
# Chạy offline: runner source ở lib mode, gh/claude là stub, tải đọc từ file (SB_BUILD_LOAD_FILE). Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-build-workers.XXXXXX")"
WORKERS=""
cleanup() { for w in $WORKERS; do kill "$w" 2>/dev/null; done; for p in $(pgrep -f "$TMP/path/claude" 2>/dev/null); do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/repo/docs/super-board" "$TMP/repo/wl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
# worker sống lâu: giữ lane cho tới khi test kill
printf '#!/usr/bin/env bash\nsleep 300\n' > "$TMP/path/claude"
chmod +x "$TMP/bin/super-board-github-read.py" "$TMP/path/claude"
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0

# #252: số gate thật trên máy không được chi phối test; 0 = không có gate nào đang chạy
printf "0\n" > "$TMP/gates0"; export SB_GATE_COUNT_FILE="$TMP/gates0"
unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL SB_BUILD_LOAD_MAX DEVKIT_SLOT_LOAD_MAX
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
cards() {   # cards <n>...: bảng chỉ có các thẻ Ready đó
  local out="" n
  for n in "$@"; do out="${out:+$out,}{\"id\":\"PVTI_$n\",\"status\":\"Ready\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$n,\"assignees\":[]}}"; done
  PROJECT_ITEMS_JSON="{\"items\":[$out]}"
}
load() { printf '%s\n' "$1" > "$TMP/load"; export SB_BUILD_LOAD_FILE="$TMP/load"; }
BUILD_PID="${BUILD_PID:-}"; BUILD_ISSUE="${BUILD_ISSUE:-}"; BUILD_EXTRA="${BUILD_EXTRA:-}"
QA_PID=""; QA_ISSUE=""; REVIEW_PID=""; REVIEW_ISSUE=""
reset() {
  for p in $BUILD_PID ${BUILD_EXTRA:-}; do kill "${p%%:*}" 2>/dev/null; wait "${p%%:*}" 2>/dev/null; done
  BUILD_PID=""; BUILD_ISSUE=""; BUILD_EXTRA=""; rm -f "$INFLIGHT_DIR"/[0-9]*; : > "$TMP/log"; : > "$TMP/writes"
}
tick() {   # đúng nhịp của vòng chính cho lane build: đếm worker còn sống, quyết định theo tải, giao tối đa một thẻ
  reap_finished_locks
  if build_slot_free && top_card_in_column "Ready"; then dispatch_lane build "$TOP_ISSUE" >/dev/null 2>&1; fi
}
live_builds() { build_workers_count; echo "$BUILD_COUNT"; }
run_ticks() { local i; for i in $(seq 1 "$1"); do tick; done; build_workers_count; }

# ── 1. build_workers=3, tải thấp, 3 thẻ Ready: 3 worker sau 3 tick, mỗi tick một worker
reset; BUILD_WORKERS=3; BUILD_LOAD_MAX=8; load 2.5; cards 1 2 3
tick; build_workers_count; c1=$BUILD_COUNT
tick; build_workers_count; c2=$BUILD_COUNT
tick; build_workers_count; c3=$BUILD_COUNT
[ "$c1" = 1 ] && [ "$c2" = 2 ] && [ "$c3" = 3 ] && ok "build_workers=3, low load: 1, 2, 3 workers over 3 ticks (one per tick)" || fail "workers after ticks 1-3: $c1 $c2 $c3 (want 1 2 3)"
grep -q "build workers 1/3, load 2.5 < 8: starting #2" "$TMP/log" && ok "  … and the log names the decision (count/cap, load vs limit, which worker)" || fail "no decision line; log: $(tr '\n' '|' < "$TMP/log")"
cards 4; tick; build_workers_count
[ "$BUILD_COUNT" = 3 ] && ok "  … and the cap holds: a 4th Ready card is not started" || fail "cap broken: $BUILD_COUNT workers"

# ── 2. tải cao: giữ ở worker đầu (worker đầu không bị tải chặn), log "holding"; worker đang chạy không bị giết
reset; BUILD_WORKERS=3; BUILD_LOAD_MAX=8; load 2; cards 1 2 3
tick; first=$BUILD_PID
load 11.4; tick; tick; build_workers_count
[ "$BUILD_COUNT" = 1 ] && kill -0 "$first" 2>/dev/null && ok "high load: no worker added, the running one is not killed" || fail "high load: $BUILD_COUNT workers, first alive=$(kill -0 "$first" 2>/dev/null && echo y || echo n)"
grep -q "load 11.4 >= 8: holding" "$TMP/log" && ok "  … and the log says holding" || fail "no holding line; log: $(tr '\n' '|' < "$TMP/log")"
reset; load 50; cards 1 2; BUILD_WORKERS=3; tick; build_workers_count
[ "$BUILD_COUNT" = 1 ] && ok "  … the FIRST worker starts even under high load (only extra workers are load-gated)" || fail "first worker blocked by load: $BUILD_COUNT"

# ── 3. tải không đọc được (file trống / chữ / thiếu): không quá worker đầu
for bad in "" "abc"; do
  reset; BUILD_WORKERS=3; BUILD_LOAD_MAX=8; load "$bad"; cards 1 2 3; tick; tick; tick; build_workers_count
  [ "$BUILD_COUNT" = 1 ] && ok "unreadable load ('${bad:-empty}'): stays at one worker" || fail "unreadable load ('${bad:-empty}'): $BUILD_COUNT workers"
done
grep -q "unreadable" "$TMP/log" && ok "  … and the log says the load is unreadable" || fail "no unreadable line"
reset; BUILD_WORKERS=3; BUILD_LOAD_MAX=8; export SB_BUILD_LOAD_FILE="$TMP/does-not-exist"; cards 1 2 3; tick; tick; build_workers_count
[ "$BUILD_COUNT" = 1 ] && ok "missing load file: stays at one worker" || fail "missing load file: $BUILD_COUNT workers"

# ── 4. build_workers=1 (đặt trong config): đúng một worker dù tải thấp
reset; BUILD_WORKERS=1; BUILD_LOAD_MAX=8; load 0.1; cards 1 2 3; tick; tick; tick; build_workers_count
[ "$BUILD_COUNT" = 1 ] && ok "build_workers=1: one worker, as today" || fail "build_workers=1: $BUILD_COUNT workers"
[ -z "${BUILD_EXTRA:-}" ] && ok "  … and no extra slot is used" || fail "BUILD_EXTRA='${BUILD_EXTRA}'"

# ── 5. một worker chết: số đếm giảm và tick sau khởi lại thẻ khác
reset; BUILD_WORKERS=2; BUILD_LOAD_MAX=8; load 1; cards 1 2 3; tick; tick
kill "$BUILD_PID" 2>/dev/null; wait "$BUILD_PID" 2>/dev/null; build_workers_count
[ "$BUILD_COUNT" = 1 ] && ok "a dead worker is dropped from the count" || fail "after a worker died: $BUILD_COUNT workers"
cards 3; tick; build_workers_count
[ "$BUILD_COUNT" = 2 ] && ok "  … and the freed slot is filled on the next tick" || fail "freed slot not refilled: $BUILD_COUNT"

# ── 6. dừng khẩn / mồ côi / zombie nhận ra N worker
reset; BUILD_WORKERS=3; BUILD_LOAD_MAX=8; load 1; cards 1 2 3; tick; tick; tick
own="$(own_lane_pids)"; n=$(printf '%s\n' "$own" | grep -c .)
[ "$n" = 3 ] && ok "own_lane_pids lists all 3 build workers (halt stops every one)" || fail "own_lane_pids: '$(echo $own)' ($n)"
# zombie: thẻ của một worker sang Done, chỉ worker đó bị kill
z_issue=$(sed -n 's/^.*issue=#\([0-9]*\) pid=.*$/\1/p' "$TMP/log" | sed -n 2p)
z_pid=$(sed -n "s/^dispatch lane=build issue=#${z_issue} pid=\([0-9]*\).*/\1/p" "$TMP/log")
items_json=""; for n in 1 2 3; do st=Building; [ "$n" = "$z_issue" ] && st=Done; items_json="${items_json:+$items_json,}{\"id\":\"PVTI_$n\",\"status\":\"$st\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$n,\"assignees\":[]}}"; done
PROJECT_ITEMS_JSON="{\"items\":[$items_json]}"
sweep_lane_zombies; sleep 0.3; build_workers_count
[ "$BUILD_COUNT" = 2 ] && ! kill -0 "$z_pid" 2>/dev/null && ok "zombie sweep kills only the worker whose card left the lane (#${z_issue}), the other two live" || fail "zombie sweep: $BUILD_COUNT workers, zombie #${z_issue} pid ${z_pid} alive=$(kill -0 "$z_pid" 2>/dev/null && echo y || echo n)"
# nhận lại lúc khởi động: 2 lock build sống -> cả 2 vào lane
reset
sleep 300 & a=$!; sleep 300 & b=$!; WORKERS="$WORKERS $a $b"
for pair in "$a:31" "$b:32"; do printf 'PID=%s\nLANE=build\nSTARTED=%s\n' "${pair%%:*}" "$(date -u +%FT%TZ)" > "$INFLIGHT_DIR/${pair##*:}"; done
real_ps=$(command -v ps)
ps() { case "$*" in *"-p $a"*) echo "claude -p Run super-build on issue #31 for super-board run" ;; *"-p $b"*) echo "claude -p Run super-build on issue #32 for super-board run" ;; *) "$real_ps" "$@" ;; esac; }
adopt_live_locks; build_workers_count
[ "$BUILD_COUNT" = 2 ] && ok "adopt_live_locks puts every live build worker back into the lane (no duplicate start after a restart)" || fail "adopt: $BUILD_COUNT build workers (PID='$BUILD_PID' EXTRA='${BUILD_EXTRA:-}')"
unset -f ps

# ── 6b. N worker build chỉ chiếm 1 slot của max_workers (QA/Review không bị bỏ đói)
grep -q 'ACTIVE_WORKERS + BUILD_COUNT' "$RUNNER" && fail "build workers counted one by one against max_workers" || ok "the build lane counts as one slot against max_workers"

# ── 7. cái dây vòng chính: nhánh Ready dùng build_slot_free, config đọc build_workers / build_load_max
grep -q 'build_slot_free' "$RUNNER" && grep -q "build_workers" "$RUNNER" && grep -q "build_load_max" "$RUNNER" \
  && ok "runner reads build_workers / build_load_max and the Ready branch uses build_slot_free" || fail "runner lacks the build_workers wiring"
grep -q '^BUILD_WORKERS=$(resolve_build_workers "$CONFIG_PATH")' "$RUNNER" && grep -q '^BUILD_LOAD_MAX=$(resolve_build_load_max "$CONFIG_PATH")' "$RUNNER" \
  && ok "  … the config read at startup goes through resolve_build_workers / resolve_build_load_max (the defaults apply)" || fail "startup config read does not use the resolvers"
grep -n 'BUILD_FREE' "$RUNNER" | grep -q 'READY' && ok "  … Ready dispatch is gated by BUILD_FREE" || fail "Ready dispatch not gated by BUILD_FREE"

# ── 8. ngưỡng tải mặc định = 100 (người dùng 21/10: "tải máy dưới 100 thì cho chạy"), cùng luật với DEVKIT_SLOT_LOAD_MAX
cfg_with() { printf '%s\n' "$1" > "$TMP/c.json"; }
cfg_with '{}'; d=$(resolve_build_load_max "$TMP/c.json")
[ "$d" = 100 ] && ok "default build_load_max is 100" || fail "default build_load_max is '$d' (want 100)"
d=$(DEVKIT_SLOT_LOAD_MAX=64 resolve_build_load_max "$TMP/c.json")
[ "$d" = 64 ] && ok "  … unset in config and env: reuses DEVKIT_SLOT_LOAD_MAX" || fail "DEVKIT_SLOT_LOAD_MAX not reused: '$d'"
cfg_with '{"build_load_max": 30}'; d=$(DEVKIT_SLOT_LOAD_MAX=64 resolve_build_load_max "$TMP/c.json")
[ "$d" = 30 ] && ok "  … the config key beats DEVKIT_SLOT_LOAD_MAX" || fail "config key lost: '$d'"
d=$(SB_BUILD_LOAD_MAX=12.5 resolve_build_load_max "$TMP/c.json")
[ "$d" = 12.5 ] && ok "  … SB_BUILD_LOAD_MAX beats the config key" || fail "SB_BUILD_LOAD_MAX lost: '$d'"
cfg_with '{"build_load_max": "abc"}'; d=$(resolve_build_load_max "$TMP/c.json")
[ "$d" = 100 ] && ok "  … an invalid value falls back to 100" || fail "invalid value gave '$d'"
# OCR 21/10: mỗi nguồn phải là số DƯƠNG (như heavy_slot.load_max) và nguồn sai thì xét nguồn kế, không nhảy thẳng về 100
cfg_with '{}'; d=$(DEVKIT_SLOT_LOAD_MAX=0 resolve_build_load_max "$TMP/c.json")
[ "$d" = 100 ] && ok "  … DEVKIT_SLOT_LOAD_MAX=0 is not a threshold (100, as heavy_slot)" || fail "DEVKIT_SLOT_LOAD_MAX=0 gave '$d'"
cfg_with '{"build_load_max": 0}'; d=$(DEVKIT_SLOT_LOAD_MAX=64 resolve_build_load_max "$TMP/c.json")
[ "$d" = 64 ] && ok "  … build_load_max=0 is skipped, the next source (64) counts" || fail "build_load_max=0 gave '$d'"
cfg_with '{"build_load_max": 30}'; d=$(SB_BUILD_LOAD_MAX=abc resolve_build_load_max "$TMP/c.json")
[ "$d" = 30 ] && ok "  … an invalid SB_BUILD_LOAD_MAX falls through to the config key (30)" || fail "invalid SB_BUILD_LOAD_MAX gave '$d'"
d=$(SB_BUILD_LOAD_MAX=0.0 DEVKIT_SLOT_LOAD_MAX=7 resolve_build_load_max "$TMP/c.json")
[ "$d" = 30 ] && ok "  … 0.0 is not positive: skipped" || fail "SB_BUILD_LOAD_MAX=0.0 gave '$d'"

# ── 9. build_workers mặc định = 10 (người dùng 21/10); khoá config vẫn đặt lại được, build_workers=1 quay về một worker
cfg_with '{}'; w=$(resolve_build_workers "$TMP/c.json")
[ "$w" = 10 ] && ok "default build_workers is 10" || fail "default build_workers is '$w' (want 10)"
cfg_with '{"build_workers": 1}'; w=$(resolve_build_workers "$TMP/c.json")
[ "$w" = 1 ] && ok "  … build_workers=1 in the config still gives one worker" || fail "build_workers=1 gave '$w'"
cfg_with '{"build_workers": 4}'; w=$(resolve_build_workers "$TMP/c.json")
[ "$w" = 4 ] && ok "  … any other value is honoured" || fail "build_workers=4 gave '$w'"
for bad in '"x"' 0 -3 2.5 '"000"' 99999999999999999999; do cfg_with "{\"build_workers\": $bad}"; w=$(resolve_build_workers "$TMP/c.json")
  [ "$w" = 10 ] && ok "  … an invalid build_workers ($bad) falls back to 10" || fail "build_workers=$bad gave '$w'"; done
# with the defaults, low load climbs past one worker; load at the default limit holds; unreadable load stays at one
cfg_with '{}'; reset; BUILD_WORKERS=$(resolve_build_workers "$TMP/c.json"); BUILD_LOAD_MAX=$(resolve_build_load_max "$TMP/c.json")
load 40; cards 1 2 3; tick; tick; tick; build_workers_count
[ "$BUILD_COUNT" = 3 ] && ok "defaults, load 40: the lane climbs to 3 workers" || fail "defaults, load 40: $BUILD_COUNT workers"
reset; load 100; cards 1 2 3; tick; tick; build_workers_count
[ "$BUILD_COUNT" = 1 ] && ok "defaults, load 100 (>= limit): holds at one" || fail "defaults, load 100: $BUILD_COUNT workers"
reset; load ""; cards 1 2 3; tick; tick; build_workers_count
[ "$BUILD_COUNT" = 1 ] && ok "defaults, unreadable load: still one worker" || fail "defaults, unreadable load: $BUILD_COUNT workers"

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
