#!/usr/bin/env bash
# Test (#252): runner giới hạn WIP và điều tiết theo số gate đang chạy, không chỉ loadavg 1 phút.
#  - lane build KHÔNG giao worker mới khi (QA + Review đang chờ) >= build_wip_k × (qa_workers + review_workers) (k mặc định 2), log lý do;
#  - lane build và worker THÊM của QA/Review KHÔNG giao khi số gate post-fix-gate đang chạy >= gate_max (mặc định 6), log lý do;
#  - worker đầu của QA/Review không bị chặn (hàng chờ phải xả được); worker đang chạy không bị giết.
# Chạy offline: runner source ở lib mode, gh/claude là stub; tải và số gate đọc từ file (SB_BUILD_LOAD_FILE, SB_GATE_COUNT_FILE).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-wip-limit.XXXXXX")"
cleanup() { for p in $(pgrep -f "$TMP/path/claude" 2>/dev/null); do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/repo/docs/super-board" "$TMP/repo/wl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
printf '#!/usr/bin/env bash\nsleep 300\n' > "$TMP/path/claude"
chmod +x "$TMP/bin/super-board-github-read.py" "$TMP/path/claude"
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0

unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL SB_BUILD_LOAD_MAX DEVKIT_SLOT_LOAD_MAX DEVKIT_CAPACITY DEVKIT_CAPACITY_LOAD SB_CAPACITY
# T0052: mặc định của runner (gate_max, lane workers…) đến từ bin/capacity.py: máy giả 12 lõi, không lệ thuộc máy chạy test
export DEVKIT_CAPACITY_CORES=12
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
load() { printf '%s\n' "$1" > "$TMP/load"; export SB_BUILD_LOAD_FILE="$TMP/load"; }
gates() { printf '%s\n' "$1" > "$TMP/gates"; export SB_GATE_COUNT_FILE="$TMP/gates"; }
cfg_with() { printf '%s\n' "$1" > "$TMP/c.json"; }
BUILD_PID=""; BUILD_ISSUE=""; BUILD_EXTRA=""; QA_PID=""; QA_ISSUE=""; QA_EXTRA=""; REVIEW_PID=""; REVIEW_ISSUE=""; REVIEW_EXTRA=""
BUILD_WORKERS=10; BUILD_LOAD_MAX=100; QA_WORKERS=3; REVIEW_WORKERS=3; WIP_K=2; GATE_MAX=3
load 1; gates 0

# ── 1. cấu hình: build_wip_k / gate_max đọc từ config, thiếu hoặc sai thì mặc định (2 / 6)
cfg_with '{}'
[ "$(resolve_wip_k "$TMP/c.json")" = 2 ] && ok "default build_wip_k is 2" || fail "default build_wip_k is '$(resolve_wip_k "$TMP/c.json")'"
[ "$(resolve_gate_max "$TMP/c.json")" = 6 ] && ok "default gate_max is 6" || fail "default gate_max is '$(resolve_gate_max "$TMP/c.json")'"
cfg_with '{"build_wip_k": 5, "gate_max": 7}'
[ "$(resolve_wip_k "$TMP/c.json")" = 5 ] && [ "$(resolve_gate_max "$TMP/c.json")" = 7 ] && ok "config values are honoured" || fail "config values lost"
for bad in '"x"' 0 -1 2.5; do
  cfg_with "{\"build_wip_k\": $bad, \"gate_max\": $bad}"
  [ "$(resolve_wip_k "$TMP/c.json")" = 2 ] && [ "$(resolve_gate_max "$TMP/c.json")" = 6 ] && ok "  … invalid value ($bad) falls back to 2 / 6" || fail "invalid value ($bad) gave '$(resolve_wip_k "$TMP/c.json")' / '$(resolve_gate_max "$TMP/c.json")'"
done
# 12 lõi: capacity gate_max (12/2 = 6) trùng số cũ 6 — hai ca dưới tách được nhánh capacity khỏi nhánh số cũ (OCR 23/10)
cfg_with '{}'
g4="$(DEVKIT_CAPACITY_CORES=4 resolve_gate_max "$TMP/c.json")"; gn="$(SB_CAPACITY=/nonexistent DEVKIT_CAPACITY_CORES=4 resolve_gate_max "$TMP/c.json")"
[ "$g4" = 2 ] && ok "  … default gate_max follows cores (4 cores -> capacity 2)" || fail "4 cores: default gate_max '$g4' (want 2)"
[ "$gn" = 6 ] && ok "  … capacity missing (SB_CAPACITY=/nonexistent): old default 6" || fail "no capacity: default gate_max '$gn' (want 6)"

# ── 2. WIP: ngưỡng = 2 × (3 + 3) = 12. QA + Review = 12 -> không giao build; 11 -> giao
QA=7; REVIEW=5; : > "$TMP/log"; BUILD_FREE=0
build_slot_free; rc=$?
[ "$rc" -ne 0 ] && [ "$BUILD_FREE" = 0 ] && ok "QA+Review waiting (12) >= 2 x (3+3): no new build" || fail "build started at the WIP limit (rc=$rc BUILD_FREE=$BUILD_FREE)"
grep -q "WIP 12 >= 12" "$TMP/log" && ok "  … and the log names the reason (WIP 12 >= 12)" || fail "no WIP reason; log: $(tr '\n' '|' < "$TMP/log")"
QA=6; REVIEW=5; : > "$TMP/log"
build_slot_free; rc=$?
[ "$rc" -eq 0 ] && [ "$BUILD_FREE" = 1 ] && ok "QA+Review waiting (11) < 12: a build is given" || fail "build held below the WIP limit (rc=$rc)"
QA=0; REVIEW=0

# ── 3. WIP theo k trong config: k=1 -> ngưỡng 6
WIP_K=1; QA=3; REVIEW=3; : > "$TMP/log"; BUILD_FREE=0
build_slot_free; rc=$?
[ "$rc" -ne 0 ] && ok "build_wip_k=1: threshold 6, 6 waiting holds the build" || fail "k=1 did not hold (rc=$rc)"
WIP_K=2; QA=0; REVIEW=0

# ── 4. gate: số gate đang chạy >= gate_max -> lane build không giao, log lý do; dưới trần thì giao
gates 3; : > "$TMP/log"; BUILD_FREE=0
build_slot_free; rc=$?
[ "$rc" -ne 0 ] && [ "$BUILD_FREE" = 0 ] && ok "3 gates running >= gate_max 3: no new build" || fail "build started at the gate cap (rc=$rc)"
grep -q "gates 3 >= 3" "$TMP/log" && ok "  … and the log names the reason (gates 3 >= 3)" || fail "no gate reason; log: $(tr '\n' '|' < "$TMP/log")"
gates 2; BUILD_FREE=0; build_slot_free; rc=$?
[ "$rc" -eq 0 ] && [ "$BUILD_FREE" = 1 ] && ok "2 gates running < 3: a build is given" || fail "build held below the gate cap (rc=$rc)"

# ── 5. gate: worker THÊM của QA/Review bị chặn, worker đầu thì không (hàng chờ phải xả được)
gates 4; QA_PID=""; QA_EXTRA=""
lane_slot_free qa; rc=$?
[ "$rc" -eq 0 ] && ok "gates at cap: the FIRST QA worker is still allowed" || fail "first QA worker blocked by the gate cap (rc=$rc)"
sleep 300 & QA_PID=$!; QA_ISSUE=1; : > "$TMP/log"
lane_slot_free qa; rc=$?
[ "$rc" -ne 0 ] && ok "gates at cap: an EXTRA QA worker is not started" || fail "extra QA worker started at the gate cap"
grep -q "gates 4 >= 3" "$TMP/log" && ok "  … and the log names the reason" || fail "no gate reason for the extra worker; log: $(tr '\n' '|' < "$TMP/log")"
gates 1; lane_slot_free qa; rc=$?
[ "$rc" -eq 0 ] && ok "gates below the cap: the extra QA worker is allowed" || fail "extra QA worker held below the gate cap (rc=$rc)"
kill "$QA_PID" 2>/dev/null; QA_PID=""; QA_ISSUE=""

# ── 6. số gate không đọc được -> không chặn (đếm tiến trình là heuristic, không được làm chết lane)
gates ""; BUILD_FREE=0; build_slot_free; rc=$?
[ "$rc" -eq 0 ] && ok "unreadable gate count: does not block" || fail "unreadable gate count blocked the build (rc=$rc)"

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
