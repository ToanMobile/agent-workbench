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
grep -q "#7.*ended" "$TMP/log" && grep -q "session limit" "$TMP/log" && ok "  … and the log says the worker died early, with its last log line" \
  || fail "no early-death line naming the worker's last log line: $(grep -m1 '#7' "$TMP/log")"
# the window passes: the card may be tried again
for f in "$INFLIGHT_DIR"/early-deaths/*; do [ -f "$f" ] && awk '{$1 -= 3600; print}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"; done
: > "$TMP/writes"; PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_7","status":"Ready","labels":[],"content":{"type":"Issue","number":7,"assignees":[]}}]}'
cycle
[ "$(claims_of 7)" = 1 ] && ok "  … and once the window has passed, the card is claimed again" || fail "after the window #7 was not claimed again (claims $(claims_of 7))"
# 3rd early death recorded on reap; even after another window passes, circuit breaker (SB_EARLY_MAX_TOTAL=3) holds the card
reap_finished_locks
for f in "$INFLIGHT_DIR"/early-deaths/*; do [ -f "$f" ] && awk '{$1 -= 3600; print}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"; done
: > "$TMP/writes"
cycle
[ "$(claims_of 7)" = 0 ] && ok "  … but after 3 total early deaths across windows (SB_EARLY_MAX_TOTAL), the circuit breaker holds the card" \
  || fail "circuit breaker failed: #7 was claimed a 4th time after 3 early deaths across windows"

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

# ── 4b (review 19/10): reap runs once per tick (default tick_seconds 120), so it sees a worker that died 3 s after dispatch only
#    ~125 s later: measured at reap time that is never "early". The death time is the worker log's last write; with no log the
#    window grows by one tick.
rm -rf "$INFLIGHT_DIR/early-deaths"; mkdir -p "$TMP/repo/wl"
st=$(( $(date +%s) - 125 ))
iso() { python3 -c 'import sys, time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(int(sys.argv[1]))))' "$1"; }
printf 'PID=%s\nLANE=build\nSTARTED=%s\n' "$DEAD" "$(iso "$st")" > "$INFLIGHT_DIR/60"
echo "You've hit your session limit" > "$TMP/repo/wl/worker-build-60.log"
python3 -c 'import os, sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))' "$TMP/repo/wl/worker-build-60.log" $((st + 3))
printf 'PID=%s\nLANE=build\nSTARTED=%s\n' "$DEAD" "$(iso "$st")" > "$INFLIGHT_DIR/61"   # no worker log at all
( TICK_SECONDS=120; reap_finished_locks )
[ -s "$INFLIGHT_DIR/early-deaths/60" ] && ok "a worker that died 3 s in, reaped a 120 s tick later, is an early death (log mtime)" \
  || fail "tick-late reap missed an early death (log mtime 3 s after dispatch)"
[ -s "$INFLIGHT_DIR/early-deaths/61" ] && ok "  … and with no worker log, one tick of slack still catches it" \
  || fail "tick-late reap with no log missed an early death"
printf 'PID=%s\nLANE=build\nSTARTED=%s\n' "$DEAD" "$(iso $(( $(date +%s) - 600 )))" > "$INFLIGHT_DIR/62"
echo "worked a while" > "$TMP/repo/wl/worker-build-62.log"
python3 -c 'import os, sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))' "$TMP/repo/wl/worker-build-62.log" $(( $(date +%s) - 30 ))
( TICK_SECONDS=120; reap_finished_locks )
[ ! -s "$INFLIGHT_DIR/early-deaths/62" ] && ok "  … but a worker whose log ran 9 minutes is not" || fail "a long-running worker counted as an early death"
# claude -p (text mode) writes nothing until it ends: a long silent run that was killed leaves only the dispatch header, written
# just BEFORE STARTED — its log mtime says nothing about when it died (OCR 19/10)
st63=$(( $(date +%s) - 1800 ))
printf 'PID=%s\nLANE=build\nSTARTED=%s\n' "$DEAD" "$(iso "$st63")" > "$INFLIGHT_DIR/63"
echo "=== dispatch lane=build issue=#63 ===" > "$TMP/repo/wl/worker-build-63.log"
python3 -c 'import os, sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))' "$TMP/repo/wl/worker-build-63.log" $((st63 - 1))
( TICK_SECONDS=120; reap_finished_locks )
[ ! -s "$INFLIGHT_DIR/early-deaths/63" ] && ok "  … nor a 30-minute silent run whose log holds only the dispatch header" \
  || fail "a long silent run (log mtime before STARTED) was counted as an early death"

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

# ── 6b. #393: a worker that ended quickly because it moved the card to Blocked (hold / sequence / too big) exited on purpose:
#    no early-death record and no "early end" line (the incident rule `early-death` files a kit card from that line). A card the
#    board still shows in a working column stays an early death.
rm -f "$INFLIGHT_DIR"/early-deaths/*; : > "$TMP/log"
printf '#!/usr/bin/env bash\ncase "$*" in *"status 70") echo Blocked ;; *"status 71") echo Building ;; *) exit 1 ;; esac\n' > "$TMP/bin/super-board-card.sh"
chmod +x "$TMP/bin/super-board-card.sh"
for n in 70 71; do printf 'PID=%s\nLANE=build\nSTARTED=%s\n' "$DEAD" "$(date -u +%FT%TZ)" > "$INFLIGHT_DIR/$n"; done
( reap_finished_locks )
[ ! -s "$INFLIGHT_DIR/early-deaths/70" ] && ! grep -q "#70.*early end" "$TMP/log" \
  && ok "a quick exit after moving the card to Blocked is not an early death (#393)" \
  || fail "#393: a worker that blocked its card on purpose was counted as an early death: $(grep '#70' "$TMP/log" | tail -1)"
[ -s "$INFLIGHT_DIR/early-deaths/71" ] && ok "  … but a card still in Building stays an early death" || fail "#393: a card still in Building was not counted"
# ── 6c. #465: a QA worker that passed its card on (QA → Review) or closed it (Done) in under 120 s finished its job, it did not crash.
rm -f "$INFLIGHT_DIR"/early-deaths/*; : > "$TMP/log"
printf '#!/usr/bin/env bash\ncase "$*" in *"status 72") echo Review ;; *"status 73") echo Done ;; *"status 74") echo QA ;; *) exit 1 ;; esac\n' > "$TMP/bin/super-board-card.sh"
chmod +x "$TMP/bin/super-board-card.sh"
for n in 72 73 74; do printf 'PID=%s\nLANE=qa\nSTARTED=%s\n' "$DEAD" "$(date -u +%FT%TZ)" > "$INFLIGHT_DIR/$n"; done
( reap_finished_locks )
[ ! -s "$INFLIGHT_DIR/early-deaths/72" ] && ! grep -q "#72.*early end" "$TMP/log" \
  && ok "a quick QA exit after moving the card to Review is not an early death (#465)" \
  || fail "#465: a QA worker that passed its card to Review was counted as an early death: $(grep '#72' "$TMP/log" | tail -1)"
[ ! -s "$INFLIGHT_DIR/early-deaths/73" ] && ok "  … nor one that closed it (Done)" || fail "#465: a card moved to Done was counted as an early death"
[ -s "$INFLIGHT_DIR/early-deaths/74" ] && ok "  … but a card still in QA stays an early death" || fail "#465: a card still in QA was not counted"
rm -f "$TMP/bin/super-board-card.sh"

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

# ── 8. dispatch_lane sets CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS so claude -p does not kill red_proof.py after 10m
cat > "$TMP/path/claude" <<'SH'
#!/usr/bin/env bash
echo "BG_WAIT=${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS:-unset}"
SH
chmod +x "$TMP/path/claude"
rm -rf "$INFLIGHT_DIR/early-deaths"
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_70","status":"Ready","labels":[],"content":{"type":"Issue","number":70,"assignees":[]}}]}'
( dispatch_lane build 70 ) >/dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q "^BG_WAIT=" "$TMP/repo/wl/worker-build-70.log" 2>/dev/null && break; sleep 0.2; done
grep -qx "BG_WAIT=0" "$TMP/repo/wl/worker-build-70.log" 2>/dev/null \
  && ok "dispatch_lane exports CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 for long background proofs" \
  || fail "CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS not set in worker env: $(cat "$TMP/repo/wl/worker-build-70.log" 2>/dev/null)"

# ── 8b. #249: the worker's Bash tool is cut at 10 min while the gate still waits for a heavy_slot (up to 600 s) → raise the Bash timeout
cat > "$TMP/path/claude" <<'SH'
#!/usr/bin/env bash
echo "BASH_TO=${BASH_DEFAULT_TIMEOUT_MS:-unset}/${BASH_MAX_TIMEOUT_MS:-unset}"
SH
chmod +x "$TMP/path/claude"
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_71","status":"Ready","labels":[],"content":{"type":"Issue","number":71,"assignees":[]}}]}'
( dispatch_lane build 71 ) >/dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q "^BASH_TO=" "$TMP/repo/wl/worker-build-71.log" 2>/dev/null && break; sleep 0.2; done
bto="$(grep '^BASH_TO=' "$TMP/repo/wl/worker-build-71.log" 2>/dev/null | head -1 | sed 's/^BASH_TO=//')"
[ "${bto%/*}" -ge 3600000 ] 2>/dev/null && [ "${bto#*/}" -ge 3600000 ] 2>/dev/null \
  && ok "dispatch_lane exports BASH_DEFAULT_TIMEOUT_MS and BASH_MAX_TIMEOUT_MS >= 3600000 (#249)" \
  || fail "worker Bash timeout env below 3600000 ms: '$bto'"

# ── 9. cleanup_stale_worktrees prunes orphaned red-proof-* worktrees when no red_proof.py is running
git -C "$TMP/repo" init -q
git -C "$TMP/repo" config user.email "t@e.st"
git -C "$TMP/repo" config user.name "t"
git -C "$TMP/repo" commit --allow-empty -q -m "init"
RP_WT="$TMP/red-proof-orphan123"
git -C "$TMP/repo" worktree add --detach -q "$RP_WT" HEAD
ps() { echo "100 /bin/bash"; }
cleanup_stale_worktrees
unset -f ps
! git -C "$TMP/repo" worktree list --porcelain | grep -q "red-proof-orphan123" \
  && ok "cleanup_stale_worktrees removes orphaned red-proof-* worktrees when no red_proof.py is alive" \
  || fail "orphaned red-proof-* worktree still registered after cleanup_stale_worktrees"

[ "$FAILS" -eq 0 ] && echo "✅ test_runner_claim_loop: all passed" || { echo "❌ test_runner_claim_loop: $FAILS failed"; exit 1; }
