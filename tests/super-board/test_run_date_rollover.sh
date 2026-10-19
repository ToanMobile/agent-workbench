#!/usr/bin/env bash
# Test hồi quy: cập nhật đường dẫn log qua nửa đêm (RUN_DATE, RUN_MANIFEST, WORKER_LOG_DIR) và giữ đường dẫn WORKER_LOG trong lock inflight.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-rollover-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/state" "$TMP/path" "$TMP/repo"

cat > "$TMP/bin/pool.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"state":"ok","engine":"claude","account":"finos","config_dir":"/x/.claude-finos"}'
exit 0
SH
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
cat > "$TMP/path/claude" <<'SH'
#!/usr/bin/env bash
echo "You've hit your session limit · resets 10:50pm (Asia/Saigon)"
exit 1
SH
chmod +x "$TMP/bin/pool.sh" "$TMP/bin/super-board-github-read.py" "$TMP/path/claude"
export STUB_DIR="$TMP" SB_STATE_DIR="$TMP/state" SB_ACCOUNT_POOL="$TMP/bin/pool.sh" PATH="$TMP/path:$PATH"

unset SB_GITHUB_READ_STRICT
SB_LIB_ONLY=1 CONFIG_SLUG="demo" . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
CONFIG_SLUG="demo"
CONFIG_PATH="$TMP/cfg.json"; echo '{}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
REPO_ROOT="$TMP/repo"
BOT_LOGIN=""
gh_checkpoint() { :; }
gh_write_once() { :; }
issue_is_open() { return 0; }
try_claim_assignee() { return 0; }
log() { echo "$*" >> "$TMP/log"; }
cd "$TMP/repo" || exit 1

# ── 1. Gọi refresh_run_paths hai lần qua SB_DATE_CMD: đổi ngày làm đổi WORKER_LOG_DIR, tạo thư mục và ghi worker_log không lỗi.
fake_date_d1() { echo "2026-10-18"; }
fake_date_d2() { echo "2026-10-19"; }

SB_DATE_CMD="fake_date_d1" refresh_run_paths 2>/dev/null
d1_dir="$WORKER_LOG_DIR"
d1_manifest="$RUN_MANIFEST"

SB_DATE_CMD="fake_date_d2" refresh_run_paths 2>/dev/null
d2_dir="$WORKER_LOG_DIR"
d2_manifest="$RUN_MANIFEST"

if [ "$d1_dir" = "docs/super-board/runs/2026-10-18-demo-workers" ] \
   && [ "$d2_dir" = "docs/super-board/runs/2026-10-19-demo-workers" ] \
   && [ "$d2_manifest" = "docs/super-board/runs/2026-10-19-demo.md" ] \
   && [ -d "$d1_dir" ] && [ -d "$d2_dir" ] \
   && ( set -e; worker_log="${WORKER_LOG_DIR}/worker-build-1.log"; echo "line" >> "$worker_log" ); then
  ok "refresh_run_paths updates RUN_DATE/WORKER_LOG_DIR across midnight and creates directory"
else
  fail "refresh_run_paths failed (d1='$d1_dir' d2='$d2_dir' d2_exists=$([ -d "$d2_dir" ] && echo yes || echo no))"
fi

# ── 2. Dispatch ở ngày D (2026-10-18), sang ngày D+1 (2026-10-19), reap_finished_locks vẫn đọc đúng file log ngày D từ WORKER_LOG trong lock.
rm -rf "$TMP/state/usage-"*.json "$INFLIGHT_DIR"/* "$TMP/repo/docs"
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_42","status":"Ready","labels":["bug"],"content":{"type":"Issue","number":42,"assignees":[]}}]}'

# Ngay cả khi thư mục WORKER_LOG_DIR bị xoá trước dispatch_lane, dispatch_lane tự mkdir -p không chết dưới set -e.
WORKER_LOG_DIR="docs/super-board/runs/2026-10-18-demo-workers"
SB_DATE_CMD="fake_date_d1" refresh_run_paths 2>/dev/null || true
[ "$WORKER_LOG_DIR" != "/dev/null" ] && rm -rf "$WORKER_LOG_DIR"
( set -e; dispatch_lane build 42 ) >/dev/null 2>&1
for i in 1 2 3 4 5; do
  [ -f "docs/super-board/runs/2026-10-18-demo-workers/worker-build-42.log" ] \
    && grep -q "session limit" "docs/super-board/runs/2026-10-18-demo-workers/worker-build-42.log" 2>/dev/null && break
  sleep 1
done
# Đảm bảo PID trong lock đã kết thúc trước khi reap.
sleep 1

# Đổi sang ngày D+1 trước khi reap.
WORKER_LOG_DIR="docs/super-board/runs/2026-10-19-demo-workers"
SB_DATE_CMD="fake_date_d2" refresh_run_paths 2>/dev/null || true
reap_finished_locks

r=$(jq -r '[.rate_limits[]? | select(.used_percentage >= 100) | .resets_at] | first // empty' "$TMP/state/usage-finos.json" 2>/dev/null)
if [ ! -e "$INFLIGHT_DIR/42" ] && [ -n "$r" ]; then
  ok "dispatch on day D, rollover to day D+1: reap_finished_locks reads day D worker log via WORKER_LOG"
else
  fail "rollover reap missed day D worker log (lock=$([ -e "$INFLIGHT_DIR/42" ] && echo kept || echo gone) resets_at='${r:-}')"
fi

# ── 3. issue_locked khi dọn lock chết qua ngày mới cũng đọc đúng WORKER_LOG của ngày D.
rm -f "$TMP/state/usage-finos.json"
mkdir -p "docs/super-board/runs/2026-10-18-demo-workers"
cat > "docs/super-board/runs/2026-10-18-demo-workers/worker-qa-43.log" <<'LOG'
=== dispatch lane=qa issue=#43 at 2026-10-18T23:59:00Z ===
account_pool: engine=claude account=finos config_dir=/x/.claude-finos
You've hit your session limit · resets 10:50pm (Asia/Saigon)
LOG
printf 'PID=999999\nLANE=qa\nSTARTED=2026-10-18T23:59:00Z\nWORKER_LOG=%s\n' "$PWD/docs/super-board/runs/2026-10-18-demo-workers/worker-qa-43.log" > "$INFLIGHT_DIR/43"
WORKER_LOG_DIR="docs/super-board/runs/2026-10-19-demo-workers"
SB_DATE_CMD="fake_date_d2" refresh_run_paths 2>/dev/null || true
issue_locked 43
r2=$(jq -r '[.rate_limits[]? | select(.used_percentage >= 100) | .resets_at] | first // empty' "$TMP/state/usage-finos.json" 2>/dev/null)
if [ ! -e "$INFLIGHT_DIR/43" ] && [ -n "$r2" ]; then
  ok "issue_locked after date rollover reads day D worker log via WORKER_LOG"
else
  fail "issue_locked after date rollover missed day D worker log (resets_at='${r2:-}')"
fi

# ── 4. read_lock xoá WORKER_LOG trước khi source để lock không có WORKER_LOG không kế thừa giá trị cũ.
WORKER_LOG="/stale/path.log"
printf 'PID=999999\nLANE=build\nSTARTED=2026-10-19T00:01:00Z\n' > "$INFLIGHT_DIR/44"
read_lock 44
if [ -z "${WORKER_LOG:-}" ]; then
  ok "read_lock clears WORKER_LOG before sourcing"
else
  fail "read_lock kept stale WORKER_LOG='${WORKER_LOG:-}'"
fi

# ── 5. Worker sống hơn 120s (log ghi lúc giao, mtime bây giờ) nhưng reap vẫn trong cửa sổ limit+tick.
# Thư mục WORKER_LOG_DIR của ngày mới trống không được tính là chết sớm.
STARTED=$(python3 -c 'import time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time()-150)))')
OLD_LOG="$TMP/real-worker.log"
echo "still working on the dispatched log" > "$OLD_LOG"
LANE=build
WORKER_LOG="$OLD_LOG"
WORKER_LOG_DIR="$TMP/empty-today"
mkdir -p "$WORKER_LOG_DIR"
TICK_SECONDS=120
SB_EARLY_DEATH_S=120
rm -f "$TMP/log"
note_early_death 77
if ! grep -q "early end" "$TMP/log" 2>/dev/null && [ ! -e "$INFLIGHT_DIR/early-deaths/77" ]; then
  ok "a worker whose dispatched log outlived 120s is not an early death when today's folder is empty"
else
  fail "false early death (log='$(cat "$TMP/log" 2>/dev/null)' file=$([ -e "$INFLIGHT_DIR/early-deaths/77" ] && echo yes || echo no))"
fi

[ "$FAILS" -eq 0 ] && echo "✅ test_run_date_rollover: all passed" || { echo "❌ test_run_date_rollover: $FAILS failed"; exit 1; }
