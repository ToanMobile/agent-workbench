#!/usr/bin/env bash
# Test (#252 → 23/10): cổng WIP (build_wip_k) và trần số gate (gate_max) đã BỎ — trần duy nhất là max_workers (test_runner_total_cap.sh).
#  - hàng QA + Review dài không chặn build; nhiều post-fix-gate đang chạy không chặn build hay worker thêm của QA/Review;
#  - runner không còn đọc build_wip_k / gate_max.
# Chạy offline: runner source ở lib mode, gh/claude là stub.
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
load() { printf '%s\n' "$1" > "$TMP/load"; export SB_BUILD_LOAD_FILE="$TMP/load"; }
gates() { printf '%s\n' "$1" > "$TMP/gates"; export SB_GATE_COUNT_FILE="$TMP/gates"; }
cfg_with() { printf '%s\n' "$1" > "$TMP/c.json"; }
BUILD_PID=""; BUILD_ISSUE=""; BUILD_EXTRA=""; QA_PID=""; QA_ISSUE=""; QA_EXTRA=""; REVIEW_PID=""; REVIEW_ISSUE=""; REVIEW_EXTRA=""
BUILD_WORKERS=10; QA_WORKERS=3; REVIEW_WORKERS=3; MAX_WORKERS=10
load 1; gates 0

# ── 1. runner không còn đọc build_wip_k / gate_max, không còn đếm gate
grep -qE 'build_wip_k|gate_max|WIP_K|GATE_MAX|gates_running|gates_at_cap' "$RUNNER" \
  && fail "runner still has the WIP / gate_max gates" || ok "runner has no build_wip_k / gate_max gate"

# ── 2. hàng QA + Review dài (trước đây >= 2 × (qa+review) thì giữ build): nay không chặn
QA=40; REVIEW=40; READY=1; : > "$TMP/log"; BUILD_FREE=0
build_slot_free; rc=$?
[ "$rc" -eq 0 ] && [ "$BUILD_FREE" = 1 ] && ok "80 cards waiting in QA+Review: the build is still given (no WIP gate)" || fail "build held by the old WIP gate (rc=$rc)"
QA=0; REVIEW=0

# ── 3. 50 post-fix-gate đang chạy (trước đây >= gate_max thì giữ): nay không chặn build hay worker QA thêm
gates 50; BUILD_FREE=0; build_slot_free; rc=$?
[ "$rc" -eq 0 ] && [ "$BUILD_FREE" = 1 ] && ok "50 gates running: the build is still given (no gate_max)" || fail "build held by a gate count (rc=$rc)"
sleep 300 >/dev/null 2>&1 & QA_PID=$!; QA_ISSUE=1; : > "$TMP/log"
lane_slot_free qa; rc=$?
[ "$rc" -eq 0 ] && ok "50 gates running: an extra QA worker is still allowed" || fail "extra QA worker held by a gate count; log: $(tr '\n' '|' < "$TMP/log")"
kill "$QA_PID" 2>/dev/null; wait "$QA_PID" 2>/dev/null; QA_PID=""; QA_ISSUE=""

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; } || { echo "$FAILS failed"; exit 1; }
