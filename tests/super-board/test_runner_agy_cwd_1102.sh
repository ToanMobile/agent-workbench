#!/usr/bin/env bash
# Test (#1102, gộp #1151): worker Antigravity (agy) không chạy hook nào, nên cwd của nó quyết định ghi tương đối chạm vào đâu. Trước đây runner
# phóng agy từ checkout chính. Nay, khi worktree của thẻ cho lane (.claude/worktrees/issue-<N>-<lane>) đã có lúc giao, agy khởi động ở đó;
# `$!` vẫn là PID của super-board-worker-wrap.sh (subshell `exec`), log vẫn ghi được (đường dẫn tuyệt đối).
# Chạy offline: runner source ở lib mode, gh là stub, agy là script giả ghi $PWD. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="${SB_TEST_RUNNER:-$ROOT/.claude/bin/super-board-run.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-agy-cwd.XXXXXX")"
TMP="$(cd -P "$TMP" && pwd -P)"
cleanup() { for p in $(pgrep -f "$TMP/home/.local/bin/agy" 2>/dev/null); do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/home/.local/bin" "$TMP/repo/docs/super-board" "$TMP/repo/wl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
printf '#!/usr/bin/env bash\nsleep 300\n' > "$TMP/path/claude"
# agy giả: ghi cwd thật và dòng ra stdout (= log của worker), rồi ngủ
cat > "$TMP/home/.local/bin/agy" <<'EOF'
#!/usr/bin/env bash
pwd -P > "$AGY_OUT/cwd.$$"
echo "agy-ran issue-marker"
sleep 300
EOF
chmod +x "$TMP/bin/super-board-github-read.py" "$TMP/path/claude" "$TMP/home/.local/bin/agy"
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0 AGY_OUT="$TMP"

unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL SB_BUILD_LOAD_MAX DEVKIT_SLOT_LOAD_MAX
export SB_ZOMBIE_GRACE=0
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
export HOME="$TMP/home"
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
CONFIG_PATH="$TMP/cfg.json"; echo '{}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="wl"; REPO_ROOT="$TMP/repo"; BOT_LOGIN="bot"
gh_checkpoint() { :; }
gh_write_once() { :; }
log() { echo "$*" >> "$TMP/log"; }
issue_is_open() { return 0; }
resolve_worker_account() { POOL_ENGINE="antigravity"; POOL_ACCT=""; POOL_CFG=""; return 0; }
note_worker_limit() { :; }
cd "$TMP/repo" || exit 1
git init -q . 2>/dev/null
cards() {
  local st="$1" out="" n; shift
  for n in "$@"; do out="${out:+$out,}{\"id\":\"PVTI_$n\",\"status\":\"$st\",\"labels\":[],\"content\":{\"type\":\"Issue\",\"number\":$n,\"assignees\":[]}}"; done
  PROJECT_ITEMS_JSON="{\"items\":[$out]}"
}
export SB_BUILD_LOAD_FILE="$TMP/load"; echo 0.1 > "$TMP/load"
BUILD_PID=""; BUILD_ISSUE=""; BUILD_EXTRA=""
QA_PID=""; QA_ISSUE=""; QA_EXTRA=""; REVIEW_PID=""; REVIEW_ISSUE=""; REVIEW_EXTRA=""
MAX_WORKERS=10; ACTIVE_WORKERS=0
: > "$TMP/log"

wait_cwd() {   # wait_cwd <số tệp cwd.* mong đợi>: chờ tới 5 s
  local i
  for i in $(seq 1 50); do
    [ "$(ls "$TMP"/cwd.* 2>/dev/null | wc -l | tr -d ' ')" -ge "$1" ] && return 0
    sleep 0.1
  done
  return 1
}

# 1. worktree của thẻ đã có: agy chạy ở đó
mkdir -p "$REPO_ROOT/.claude/worktrees/issue-1-qa"
cards QA 1
reap_finished_locks; lane_dispatch_tick qa QA
wait_cwd 1 || fail "agy did not start (log: $(tr '\n' '|' < "$TMP/log"))"
got=$(cat "$TMP"/cwd.* 2>/dev/null | head -1)
[ "$got" = "$TMP/repo/.claude/worktrees/issue-1-qa" ] && ok "agy starts in the card's lane worktree (cwd = $got)" || fail "agy cwd '$got', want $TMP/repo/.claude/worktrees/issue-1-qa"

# 2. `$!` là PID của wrapper (adopt_live_locks / startup_orphan_workers dựa vào đó), log ghi được
pid=$(sed -n 's/^dispatch lane=qa issue=#1 pid=\([0-9]*\).*/\1/p' "$TMP/log")
cmd=$(ps -p "$pid" -o command= 2>/dev/null)
case "$cmd" in *super-board-worker-wrap.sh*) ok "the locked PID ($pid) is the worker wrapper, not a bash stub" ;; *) fail "pid '$pid' runs: $cmd" ;; esac
grep -q "agy-ran" "$TMP"/repo/wl/worker-qa-1.log 2>/dev/null && ok "the worker log (absolute path) receives agy output" || fail "no agy output in $TMP/repo/wl/worker-qa-1.log"

# 3. không có worktree của thẻ: hành vi cũ (cwd = nơi runner chạy), agy vẫn khởi động
cards QA 2
rm -f "$TMP"/cwd.*
reap_finished_locks; QA_PID=""; lane_dispatch_tick qa QA
wait_cwd 1 || fail "agy did not start for a card without a lane worktree"
got=$(cat "$TMP"/cwd.* 2>/dev/null | head -1)
[ "$got" = "$TMP/repo" ] && ok "no lane worktree yet: agy still starts (cwd = runner dir)" || fail "agy cwd '$got' without a worktree, want $TMP/repo"

[ "$FAILS" = 0 ] && { echo "OK"; exit 0; } || { echo "$FAILS fail"; exit 1; }
