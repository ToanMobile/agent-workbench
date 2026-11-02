#!/usr/bin/env bash
# Test hồi quy #529: sweep kẹt và needs-you lỏng.
#  1. `## Blocked by` chỉ có số issue không bullet (`#32`) vẫn đọc được số (không "unreadable").
#  2. Resume (Blocked → Review sau khi người duyệt) gỡ needs-you (unmark) TRƯỚC khi chuyển cột.
#  3. Denylist của super-board-needs-you.py áp cả vào --next, không chỉ --action.
#  4. Một từ khoá việc người không tắt cả câu --action: mệnh đề agent làm được vẫn bị chặn.
#  5. Reclaim và no-op ❓ không ghi `blocked-by:  -` (đẩy việc agent làm được cho người); no-op 📱 vẫn giữ.
#  6. Build/QA có trần im lặng khi PID còn sống (log worker không ghi quá SB_LANE_QUIET_MAX_S → coi là treo).
#  7. Tick rẻ (đủ worker) vẫn đếm chu kỳ không tiến triển.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
DEPS="$ROOT/.claude/bin/super-board-deps.sh"
NY="$ROOT/.claude/bin/super-board-needs-you.py"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-529.XXXXXX")"
cleanup() { for p in $(cat "$TMP/pids" 2>/dev/null); do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
export SB_GITHUB_HALT_FILE="$TMP/github-halt.json"

# ── 1. deps: section không bullet
printf '[{"number":9,"title":"t","state":"OPEN","body":"## Blocked by\\n#32\\n#33 - giá\\n","labels":{"nodes":[]},"comments":{"nodes":[]}},{"number":32,"title":"b","state":"OPEN","body":"## Blocked by\\n- None.\\n","labels":{"nodes":[]},"comments":{"nodes":[]}}]' > "$TMP/p.json"
R="$("$DEPS" --repo o/r --from "$TMP/p.json" 2>&1 | jq -c '.["9"] | [.parseable, .blockers]' 2>&1 | tail -1)"
[ "$R" = "[true,[32,33]]" ] && ok "1: bare #N lines under ## Blocked by are read as blockers" || fail "1: bare numbers unreadable: $R"

printf '[{"number":9,"title":"t","state":"OPEN","body":"## Blocked by\\n- None.\\n","labels":{"nodes":[]},"comments":{"nodes":[{"body":"x\\nblocked-by:  agent"}]}}]' > "$TMP/p2.json"
R="$("$DEPS" --repo o/r --from "$TMP/p2.json" 2>&1 | jq -c '.["9"] | [.parseable, .humanGated]' 2>&1 | tail -1)"
[ "$R" = "[true,false]" ] && ok "1b: blocked-by: agent is parseable and not human-gated" || fail "1b: agent line: $R"

# ── 3/4. needs-you denylist
R="$(python3 -I - "$NY" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ny", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
def t(what, s):
    try: m.one_line(s, what); return "accepted"
    except ValueError: return "rejected"
print(t("--next", "chạy lại gate --full rồi kéo thẻ về Ready"),
      t("--next", "gỡ nhãn needs-you rồi kéo thẻ về Ready"),
      t("--action", "đăng nhập firebase và chạy lại gate --full"),
      t("--action", "điền api key vào Supabase secrets"),
      t("--action", "xoá thư mục .claude/worktrees/issue-12-build"),
      t("--action", "chạy gen_voice_packs.py để sinh lại giọng đọc"),
      t("--action", "nâng timeout, REG-DK-ALL-01 vẫn quá giờ"),
      t("--action", "nâng timeout và giới hạn của gate REG-DK-ALL-01"))
PY
)"
[ "$R" = "rejected accepted rejected accepted rejected rejected rejected rejected" ] \
  && ok "3/4: --next is screened; a human keyword does not excuse the agent-doable clause; a pure human step passes" \
  || fail "3/4: needs-you denylist: $R (want: rejected accepted rejected accepted + 4 rejected)"

# ── chung cho các ca runner
mkdir -p "$TMP/bin" "$TMP/repo"
unset SB_GITHUB_READ_STRICT SB_NOOP_MAX SB_NOOP_WINDOW_S SB_RECLAIM_MAX
export SB_MERGE_QUEUE=0 WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
cd "$TMP/repo" || exit 1
git init -q . 2>/dev/null
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="$TMP/wl"; mkdir -p "$WORKER_LOG_DIR"
BOT_LOGIN="sb-bot"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
note_worker_limit() { :; }
note_early_death() { :; }
fetch_project_items() { :; }
: > "$TMP/writes"; : > "$TMP/log"

# ── 2. resume: unmark trước khi chuyển Review
cat > "$TMP/bin/super-board-github-read.py" <<'PY'
print("")
PY
cat > "$TMP/bin/super-board-wave-plan.sh" <<'SH'
#!/usr/bin/env bash
echo '{"sweep":[],"resume":[{"number":321,"key":"k1","why":"approved"}],"flag":[],"pending":[]}'
SH
cat > "$TMP/bin/super-board-needs-you.py" <<PY
import sys
open("$TMP/writes", "a").write("needs-you " + " ".join(sys.argv[1:]) + "\n")
PY
chmod +x "$TMP/bin/super-board-wave-plan.sh"
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
CONFIG_PATH="$TMP/cfg.json"; echo '{"repo":{"remote":"https://github.com/o/r.git"}}' > "$CONFIG_PATH"
sync_waiting_labels() { :; }
log_unreadable_blocked_by() { :; }
swept_seen() { return 1; }
swept_add() { :; }
card_lane() { echo build; }
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_321","status":"Blocked","labels":["needs-you"],"content":{"type":"Issue","number":321,"title":"c","assignees":[]}}]}'
: > "$TMP/writes"
sweep_blocked_cards
U=$(grep -n "^needs-you unmark" "$TMP/writes" | head -1 | cut -d: -f1); M=$(grep -n "^move PVTI_321 Review" "$TMP/writes" | head -1 | cut -d: -f1)
if [ -n "$U" ] && [ -n "$M" ] && [ "$U" -lt "$M" ] && grep -q -- "--issue 321" "$TMP/writes"; then ok "2: resume unmarks needs-you before moving to Review"; else fail "2: resume did not unmark first: $(tr '\n' '|' < "$TMP/writes")"; fi

# ── 5a. reclaim
sleep 0 & DEAD=$!; wait "$DEAD"
mkdir -p "$INFLIGHT_DIR/reclaims"; now=$(date +%s); printf '%s\n%s\n' "$now" "$now" > "$INFLIGHT_DIR/reclaims/55"
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_55","status":"Building","labels":[],"content":{"type":"Issue","number":55,"title":"c","assignees":["sb-bot"]}}]}'
: > "$TMP/writes"; RECLAIM_BUILDING=" 55 "; reclaim_dead_builds
if grep -qx "move PVTI_55 Blocked" "$TMP/writes" && ! grep -q "^blocked-by:  -" "$TMP/writes" && grep -q "^blocked-by:  agent" "$TMP/writes"; then ok "5a: reclaim Block comment does not carry blocked-by: -"; else fail "5a: reclaim still writes blocked-by: -"; fi

# ── 5b. no-op ❓ (không nhắc thiết bị) vs 📱
issue_comment_count() { echo 3; }
issue_status() { echo QA; }
lock() { printf 'PID=%s\nLANE=%s\nSTARTED=2026-10-20T13:10:00Z\nWORKER_LOG=%s\nFROM_COL=%s\nCOMMENTS0=%s\n' "$DEAD" "$2" "$WORKER_LOG_DIR/worker-$2-$1.log" "$3" "$4" > "$INFLIGHT_DIR/$1"; }
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_100","status":"QA","labels":["qa"],"content":{"type":"Issue","number":100,"title":"c","assignees":["sb-bot"]}}]}'
printf 'Đang chạy QA\nlint lỗi ở bước 3\nworker_exit: exit=0 signal=- elapsed=3s\n' > "$WORKER_LOG_DIR/worker-qa-100.log"
: > "$TMP/writes"
for i in 1 2; do lock 100 qa QA 3; reap_finished_locks; block_noop_workers; done
if grep -qx "move PVTI_100 Blocked" "$TMP/writes" && ! grep -q "^blocked-by:  -" "$TMP/writes" && grep -q "^blocked-by:  agent" "$TMP/writes"; then ok "5b: no-op (❓, agent-doable) Block comment does not carry blocked-by: -"; else fail "5b: no-op ❓ still writes blocked-by: -"; fi

# ── 6. trần im lặng build/qa
issue_status() { echo Building; }
RECLAIM_BUILDING=""
SB_ZOMBIE_GRACE=0
sleep 301 & WP=$!; echo "$WP" >> "$TMP/pids"
printf 'PID=%s\nLANE=build\nSTARTED=2020-01-01T00:00:00Z\nWORKER_LOG=%s\n' "$WP" "$WORKER_LOG_DIR/worker-build-7.log" > "$INFLIGHT_DIR/7"
: > "$WORKER_LOG_DIR/worker-build-7.log"; touch -t 202001010000 "$WORKER_LOG_DIR/worker-build-7.log"
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_7","status":"Building","labels":[],"content":{"type":"Issue","number":7,"title":"c","assignees":["sb-bot"]}}]}'
BUILD_PID="$WP"; BUILD_ISSUE=7; BUILD_EXTRA=""
SB_LANE_QUIET_MAX_S=3600 check_lane_zombie build "Ready Building QA Review"
if kill -0 "$WP" 2>/dev/null; then fail "6: a build worker silent for years kept its lane (PID alive)"; else ok "6: build worker silent past the cap is treated as hung and killed"; fi
case "${RECLAIM_BUILDING:-}" in *" 7"*) ok "6c: the killed build card is queued for reclaim" ;; *) fail "6c: card #7 not queued for reclaim: '${RECLAIM_BUILDING:-}'" ;; esac
sleep 301 & WP=$!; echo "$WP" >> "$TMP/pids"
printf 'PID=%s\nLANE=build\nSTARTED=2020-01-01T00:00:00Z\nWORKER_LOG=%s\n' "$WP" "$WORKER_LOG_DIR/worker-build-7.log" > "$INFLIGHT_DIR/7"
touch "$WORKER_LOG_DIR/worker-build-7.log"; BUILD_PID="$WP"
SB_LANE_QUIET_MAX_S=3600 check_lane_zombie build "Ready Building QA Review"
kill -0 "$WP" 2>/dev/null && ok "6b: a build worker still writing its log is kept" || fail "6b: a healthy build worker was killed"

# ── 7. tick rẻ vẫn đếm chu kỳ không tiến triển
NO_PROGRESS_CYCLES=3; NO_PROGRESS_CYCLE_COUNT=0; PREV_DONE_SIG="x"; LANDED_COUNT=0; MQ_WAITING=0; WAVE_LOCK=/nonexistent
PROJECT_ITEMS_JSON='{"items":[]}'
declare -F cheap_tick_progress >/dev/null || { fail "7: cheap_tick_progress missing"; }
if declare -F cheap_tick_progress >/dev/null; then
  CHEAP_CYCLE_AT=0; SB_CHEAP_CYCLE_S=0
  rc=0; for i in 1 2 3 4; do cheap_tick_progress "x" || { rc=$?; break; }; done
  [ "$rc" -ne 0 ] && ok "7: repeated cheap ticks with no Done change reach the runaway verdict" || fail "7: cheap ticks never counted"
  NO_PROGRESS_CYCLE_COUNT=0; CHEAP_CYCLE_AT=$(date +%s); SB_CHEAP_CYCLE_S=1800
  for i in 1 2 3 4 5 6; do cheap_tick_progress "x"; done
  [ "$NO_PROGRESS_CYCLE_COUNT" -eq 0 ] && ok "7b: cheap ticks inside one SB_CHEAP_CYCLE_S window count once at most" || fail "7b: every cheap tick counted: $NO_PROGRESS_CYCLE_COUNT"
fi

# ── 8. sweep: thẻ người đã xử lý xong về Ready; thẻ `blocked-by: agent` thì không (R1, hồi quy #112)
WP="$ROOT/.claude/bin/super-board-wave-plan.sh"
DONE_MARK='<!-- super-board:needs-you:done --> ✅ done'
printf '[{"number":9,"title":"a","state":"OPEN","body":"## Blocked by\\n- None.\\n","labels":{"nodes":[]},"comments":{"nodes":[{"body":"x\\nblocked-by:  -"},{"body":"%s"}]}},{"number":10,"title":"b","state":"OPEN","body":"## Blocked by\\n- None.\\n","labels":{"nodes":[]},"comments":{"nodes":[{"body":"x\\nblocked-by:  agent"}]}}]' "$DONE_MARK" > "$TMP/p8.json"
"$DEPS" --repo o/r --from "$TMP/p8.json" > "$TMP/d8.json" 2>/dev/null
echo '{"items":[{"id":"P9","status":"Blocked","labels":[],"content":{"type":"Issue","number":9,"title":"a","assignees":[]}},{"id":"P10","status":"Blocked","labels":[],"content":{"type":"Issue","number":10,"title":"b","assignees":[]}}]}' > "$TMP/i8.json"
echo '{"version":1,"project":{"owner":"o","number":1},"verify_commands":["true"],"columns":["Backlog","Ready","Building","QA","Review","Blocked","Done"]}' > "$TMP/c8.json"
R="$("$WP" --config "$TMP/c8.json" --items "$TMP/i8.json" --deps "$TMP/d8.json" 2>/dev/null | jq -c '[.sweep[].number]' 2>&1 | tail -1)"
[ "$R" = "[9]" ] && ok "8: sweep takes the person-done card (#9) and skips the blocked-by: agent card (#10)" || fail "8: sweep = $R (want [9])"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
