#!/usr/bin/env bash
# Test hồi quy #94 (18/10 19:26–19:47Z, agent-workbench): issue #7 và #12 bị assign/unassign mỗi ~40 giây tới khi board halt.
# Cơ chế đo được trong docs/super-board/runs/2026-10-19-agent-workbench.md: dispatch → worker chết sau ~33 s → reap_finished_locks
# gỡ lock + assignee → tick sau top_card_in_column chọn lại đúng thẻ đó → claim lại. Không gì nhớ rằng worker của thẻ vừa chết ngay.
# Luật ở đây:
#  1. một thẻ có worker chết sớm (dưới SB_EARLY_DEATH_S sau khi giao) không được claim quá 2 lần trong SB_EARLY_WINDOW_S (10 phút);
#     lý do vào log, kèm dòng cuối log của worker; thẻ khác vẫn được giao bình thường; hết cửa sổ thì thẻ được giao lại.
#  2. worker sống lâu (chết sau SB_EARLY_DEATH_S) không bị tính.
#  3. lúc khởi động runner, lock mồ côi (PID chết) được dọn; sổ "chết sớm" không bị đọc như lock.
#  4. thư mục log worker bị xoá giữa chừng: dispatch tạo lại, worker vẫn có log.
# Chạy offline: runner source ở lib mode, gh/claude là stub. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-claim-loop.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/repo/docs/super-board" "$TMP/repo/wl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
# a worker that dies at once (the 19/10 shape), leaving one line in its log
cat > "$TMP/path/claude" <<'SH'
#!/usr/bin/env bash
echo "You've hit your session limit"
SH
chmod +x "$TMP/bin/super-board-github-read.py" "$TMP/path/claude"
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0

unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL SB_EARLY_DEATH_S SB_EARLY_WINDOW_S
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
CONFIG_PATH="$TMP/cfg.json"; echo '{}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="wl"; REPO_ROOT="$TMP/repo"
BOT_LOGIN="bot"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
issue_is_open() { return 0; }
resolve_worker_account() { POOL_ENGINE=""; POOL_ACCT=""; POOL_CFG=""; return 0; }
note_worker_limit() { :; }
cd "$TMP/repo" || exit 1
PROJECT_ITEMS_JSON='{"items":[
 {"id":"PVTI_7","status":"Ready","labels":[],"content":{"type":"Issue","number":7,"assignees":[]}},
 {"id":"PVTI_8","status":"Ready","labels":[],"content":{"type":"Issue","number":8,"assignees":[]}}]}'

claims_of() { local n; n=$(grep -c -- "issue edit $1 --add-assignee bot" "$TMP/writes" 2>/dev/null); echo "${n:-0}"; }
sleep 0 & DEAD=$!; wait "$DEAD"   # a PID known to be dead (a fixed big number may belong to a live process on some hosts)
cycle() {   # one runner tick for the build lane: reap, pick the top Ready card, dispatch it, let the worker die
  reap_finished_locks
  BUILD_PID=""; BUILD_ISSUE=""
  if top_card_in_column "Ready"; then
    ( dispatch_lane build "$TOP_ISSUE" ) >/dev/null 2>&1
    PICKED="$TOP_ISSUE"
  else
    PICKED=""
  fi
  for _ in 1 2 3 4 5 6 7 8 9 10; do   # the stub worker exits at once
    p=$(sed -n 's/^PID=//p' "$INFLIGHT_DIR/${PICKED:-none}" 2>/dev/null); [ -z "$p" ] || ! kill -0 "$p" 2>/dev/null && break; sleep 0.2
  done
}

# ── 1. a worker that dies at once, again and again: at most 2 claims of that card in the window, then the next card
: > "$TMP/writes"; : > "$TMP/log"
picks=""
for i in 1 2 3 4 5; do cycle; picks="$picks ${PICKED:-_}"; done
c7=$(claims_of 7)
[ "$c7" -eq 2 ] && case "$picks" in " 7 7"*) true ;; *) false ;; esac && ok "a card whose worker keeps dying at once is claimed at most twice in the window (claims of #7: $c7; picks:$picks)" \
  || fail "claim/release loop: #7 claimed $c7 times in 5 ticks (picks:$picks)"
case "$picks" in *" 8"*) ok "  … and the next card is dispatched meanwhile" ;; *) fail "  the other Ready card was never dispatched (picks:$picks)" ;; esac
grep -q "#7.*died" "$TMP/log" && grep -q "session limit" "$TMP/log" && ok "  … and the log says the worker died early, with its last log line" \
  || fail "no early-death line naming the worker's last log line: $(grep -m1 '#7' "$TMP/log")"
# the window passes: the card may be tried again
for f in "$INFLIGHT_DIR"/early-deaths/*; do [ -f "$f" ] && awk '{print $1 - 3600}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"; done
: > "$TMP/writes"; PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_7","status":"Ready","labels":[],"content":{"type":"Issue","number":7,"assignees":[]}}]}'
cycle
[ "$(claims_of 7)" = 1 ] && ok "  … and once the window has passed, the card is claimed again" || fail "after the window #7 was not claimed again (claims $(claims_of 7))"

# ── 2. a worker that lived longer than SB_EARLY_DEATH_S does not count
rm -rf "$INFLIGHT_DIR/early-deaths"; : > "$TMP/writes"
for i in 1 2 3; do
  printf 'PID=%s\nLANE=build\nSTARTED=%s\n' "$DEAD" "$(date -u -v-10M +%FT%TZ 2>/dev/null || date -u -d '-10 minutes' +%FT%TZ)" > "$INFLIGHT_DIR/9"
  reap_finished_locks
done
[ ! -s "$INFLIGHT_DIR/early-deaths/9" ] && ok "workers that died after a long run are not early deaths" || fail "a long-lived worker was counted as an early death"

# ── 3. startup: an orphan lock (dead PID) is removed and its assignee swept; the early-death ledger is no lock
printf 'PID=%s\nLANE=review\nSTARTED=2026-10-18T19:30:00Z\n' "$DEAD" > "$INFLIGHT_DIR/12"
mkdir -p "$INFLIGHT_DIR/early-deaths"; echo "$(date +%s)" > "$INFLIGHT_DIR/early-deaths/12"
gh_rate_guard() { :; }; fetch_project_items() { :; }; reclaim_stranded_building() { :; }; adopt_live_locks() { :; }
: > "$TMP/writes"
startup_reconcile
[ ! -e "$INFLIGHT_DIR/12" ] && grep -q -- "issue edit 12 --remove-assignee bot" "$TMP/writes" \
  && ok "startup removes an orphan inflight lock and sweeps its assignee" || fail "orphan lock at startup: lock=$([ -e "$INFLIGHT_DIR/12" ] && echo kept || echo gone)"
[ -f "$INFLIGHT_DIR/early-deaths/12" ] && [ -z "$(find "$INFLIGHT_DIR" -maxdepth 1 -type f ! -name '[0-9]*' -print)" ] \
  && ok "  … and the early-death ledger (a folder, as merge.lock) is neither reaped nor read as a lock" \
  || fail "inflight/ after startup: $(ls -R "$INFLIGHT_DIR" | tr '\n' ' ')"

# ── 4. the worker log folder vanished mid-run (19/10: no 2026-10-19-*-workers folder): dispatch makes it again
rm -rf "$TMP/repo/wl" "$INFLIGHT_DIR/early-deaths"; : > "$TMP/writes"
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_20","status":"Ready","labels":[],"content":{"type":"Issue","number":20,"assignees":[]}}]}'
( dispatch_lane build 20 ) >/dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP/repo/wl/worker-build-20.log" ] && grep -q "session limit" "$TMP/repo/wl/worker-build-20.log" && break; sleep 0.2; done
grep -q "session limit" "$TMP/repo/wl/worker-build-20.log" 2>/dev/null && ok "a vanished worker log folder is made again: the worker writes its log" \
  || fail "worker log folder not recreated: $(ls "$TMP/repo" 2>&1 | tr '\n' ' ')"

# ── 5. under the runner's own `set -euo pipefail`, an early death whose worker log is gone must not end the runner (OCR 19/10)
rm -rf "$TMP/repo/wl" "$INFLIGHT_DIR/early-deaths"
printf 'PID=%s\nLANE=build\nSTARTED=%s\n' "$DEAD" "$(date -u +%FT%TZ)" > "$INFLIGHT_DIR/40"
( set -euo pipefail; reap_finished_locks; echo survived ) > "$TMP/strict.out" 2>&1
grep -qx survived "$TMP/strict.out" && [ -s "$INFLIGHT_DIR/early-deaths/40" ] && [ ! -e "$INFLIGHT_DIR/40" ] \
  && ok "set -euo pipefail: an early death with no worker log is recorded and the runner goes on" \
  || fail "strict mode: the reaper ended the runner or recorded nothing: $(tail -2 "$TMP/strict.out" | tr '\n' ' ')"
mkdir -p "$TMP/repo/wl"

# ── 6. the other place a dead lock is cleared (issue_locked, a worker that died after this tick's reap) records it too
rm -rf "$INFLIGHT_DIR/early-deaths"
printf 'PID=%s\nLANE=build\nSTARTED=%s\n' "$DEAD" "$(date -u +%FT%TZ)" > "$INFLIGHT_DIR/41"
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_41","status":"Ready","labels":[],"content":{"type":"Issue","number":41,"assignees":[]}}]}'
top_card_in_column "Ready" >/dev/null 2>&1
[ -s "$INFLIGHT_DIR/early-deaths/41" ] && ok "a dead lock cleared by issue_locked (no reap) is an early death too" || fail "issue_locked dropped a dead lock without recording it"

# ── 7. per lane: two quick build deaths hold the card back from the Builder, not from its Reviewer
now=$(date +%s); mkdir -p "$INFLIGHT_DIR/early-deaths"; printf '%s build\n%s build\n' "$now" "$now" > "$INFLIGHT_DIR/early-deaths/50"
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_50","status":"Review","labels":[],"content":{"type":"Issue","number":50,"assignees":[]}}]}'
top_card_in_column "Review"; r="$TOP_ISSUE"
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_50","status":"Ready","labels":[],"content":{"type":"Issue","number":50,"assignees":[]}}]}'
top_card_in_column "Ready"; b="$TOP_ISSUE"
[ "$r" = 50 ] && [ -z "$b" ] && ok "backoff is per lane: the Reviewer still takes the card, the Builder does not" || fail "per-lane backoff: review='$r' ready='$b'"
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_50","status":"Ready","labels":["qa"],"content":{"type":"Issue","number":50,"assignees":[]}}]}'
top_card_in_column "Ready"; q="$TOP_ISSUE"
printf '%s qa\n%s qa\n' "$now" "$now" > "$INFLIGHT_DIR/early-deaths/51"
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_51","status":"Ready","labels":["bug"],"content":{"type":"Issue","number":51,"assignees":[]}}]}'
top_card_in_column "Ready"; b2="$TOP_ISSUE"
[ "$q" = 50 ] && [ "$b2" = 51 ] && ok "  … and in Ready only the lane the card routes to counts (a qa card is not held by build deaths, nor a built card by qa deaths)" \
  || fail "Ready lane routing in backoff: qa-card='$q' built-card='$b2'"

[ "$FAILS" -eq 0 ] && echo "✅ test_runner_claim_loop: all passed" || { echo "❌ test_runner_claim_loop: $FAILS failed"; exit 1; }
