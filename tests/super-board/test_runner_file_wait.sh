#!/usr/bin/env bash
# #556: verdict sequence vì PR mở đụng cùng file (conflictWith) giữ thẻ ở Ready + nhãn
# "⏳ chờ thẻ khác", không sang Blocked. Tick sau hỏi lại preflight; PR đã merge hoặc đóng
# thì gỡ nhãn và giao, không cần issue chặn đóng. Thẻ ⏳ không tính vào RUNAWAY. Hai thẻ
# đụng cùng file không cùng có lock Building.
# Chạy offline. Không sửa ca 1c của test_runner_preflight_swept.sh (sequence không conflictWith vẫn giao).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
LBL="⏳ chờ thẻ khác"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-file-wait.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/path" "$TMP/repo/docs/super-board" "$TMP/repo/wl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/super-board-github-read.py"
printf 'print("ok")\n' > "$TMP/bin/super-board-skills-ready.py"
printf 'import sys\nsys.exit(0)\n' > "$TMP/bin/super-board-needs-you.py"
printf 'import os, sys\nwith open(os.environ["STUB_DIR"] + "/writes", "a") as f:\n    f.write("waiting-on " + " ".join(sys.argv[1:]) + "\\n")\nprint("{}")\n' > "$TMP/bin/super-board-waiting-on.py"
cat > "$TMP/bin/super-board-preflight.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$STUB_DIR/preflight-calls"
printf '%s\n' "${STUB_PREFLIGHT_JSON:-}"
exit "${STUB_PREFLIGHT_RC:-0}"
SH
cat > "$TMP/path/claude" <<'SH'
#!/usr/bin/env bash
echo spawned >> "$STUB_DIR/spawned"
SH
cat > "$TMP/path/gh" <<'SH'
#!/bin/sh
echo "OPEN https://github.com/acme/widgets/issues/${3:-0}"
SH
chmod +x "$TMP/bin/"* "$TMP/path/claude" "$TMP/path/gh"
export STUB_DIR="$TMP" PATH="$TMP/path:$PATH" WORKTREE_DISK_MIN_GIB=0 WORKTREE_DISK_WARN_GIB=0
unset SB_GITHUB_READ_STRICT SB_ACCOUNT_POOL
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
SB_GITHUB_READ="$TMP/bin/super-board-github-read.py"
CONFIG_PATH="$TMP/cfg.json"
echo '{"repo":{"remote":"https://github.com/acme/widgets"}}' > "$CONFIG_PATH"
INFLIGHT_DIR="$TMP/repo/.claude/super-board/inflight"
mkdir -p "$INFLIGHT_DIR"
WORKER_LOG_DIR="$TMP/repo/wl"
REPO_ROOT="$TMP/repo"
BOT_LOGIN="bot"
RUN_MANIFEST="$TMP/manifest"
NO_PROGRESS_CYCLES=2
NO_PROGRESS_CYCLE_COUNT=0
PREV_DONE_SIG="1"
LANDED_COUNT=0
RUNAWAY_PAUSE_UNTIL=0
MQ_WAITING=0
REVIEW=0
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; return 0; }
log() { echo "$*" >> "$TMP/log"; }
issue_is_open() { return 0; }
ready_card_held() { return 1; }
resolve_worker_account() { POOL_ENGINE=""; POOL_ACCT=""; POOL_CFG=""; return 0; }
note_worker_limit() { :; }
cd "$TMP/repo" || exit 1
PF="$TMP/bin/super-board-preflight.sh"

BOARD='{"items":[
 {"id":"PVTI_7","status":"Ready","labels":[],"content":{"type":"Issue","number":7,"title":"card seven","assignees":[]}},
 {"id":"PVTI_8","status":"Ready","labels":[],"content":{"type":"Issue","number":8,"title":"card eight","assignees":[]}},
 {"id":"PVTI_12","status":"Ready","labels":[],"content":{"type":"Issue","number":12,"title":"card twelve","assignees":[]}}]}'
reset() {
  : > "$TMP/writes"; : > "$TMP/log"; rm -f "$TMP/spawned" "$TMP/preflight-calls"
  rm -f "$INFLIGHT_DIR"/*
  PROJECT_ITEMS_JSON="$BOARD"
  WAITING_LABEL_READY=0
}
has_label() {
  printf '%s' "$PROJECT_ITEMS_JSON" | jq -e --argjson n "$1" --arg l "$LBL" '
    [.items[] | select(.content.number == $n) | ((.labels // []) + (.content.labels // []))[] | if type == "object" then .name else . end] | index($l)' >/dev/null
}

# ── 1. sequence + conflictWith: Ready + ⏳, không Blocked, không waiting-on (issue 9 vẫn mở)
reset
export STUB_PREFLIGHT_RC=0
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"sequence","tag":"overlap","reason":"open PRs touch the same files","blockedBy":[9],"conflictWith":[52]}}'
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
[ ! -e "$INFLIGHT_DIR/7" ] && ! grep -q "move PVTI_7 Blocked" "$TMP/writes" \
  && grep -F "issue edit 7 --add-label ${LBL}" "$TMP/writes" >/dev/null \
  && ! grep -q "^waiting-on " "$TMP/writes" \
  && has_label 7 \
  && ok "AC1 sequence conflictWith [52]: Ready + ${LBL}, not Blocked, not waiting-on" \
  || fail "AC1 hold wrong: inflight=$(ls "$INFLIGHT_DIR/7" 2>/dev/null) label=$(has_label 7; echo $?) writes=$(cat "$TMP/writes")"

# ── 2. PR còn mở: sweep hỏi lại preflight và giữ nhãn
: > "$TMP/writes"; : > "$TMP/preflight-calls"
sweep_file_wait; rc=$?
[ "$rc" = 1 ] && has_label 7 && ! grep -F -- "--remove-label ${LBL}" "$TMP/writes" \
  && grep -q -- "--issues 7" "$TMP/preflight-calls" \
  && ok "AC2 PR still open: sweep re-runs preflight and keeps ${LBL}" \
  || fail "AC2 still-open sweep wrong (rc=$rc writes=$(cat "$TMP/writes") calls=$(cat "$TMP/preflight-calls" 2>/dev/null))"

# ── 2b. PR đã merge (preflight proceed) dù issue 9 chưa đóng: gỡ ⏳ rồi giao
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"proceed","tag":"clean","reason":"no duplicate, no overlap","blockedBy":[],"conflictWith":[]}}'
: > "$TMP/writes"; : > "$TMP/preflight-calls"
sweep_file_wait; rc=$?
[ "$rc" = 0 ] && ! has_label 7 && grep -F "issue edit 7 --remove-label ${LBL}" "$TMP/writes" >/dev/null \
  && ok "AC2 PR merged: sweep drops ${LBL} without waiting for issue 9 to close" \
  || fail "AC2 release wrong (rc=$rc writes=$(cat "$TMP/writes"))"
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
sleep 0.4
[ -e "$INFLIGHT_DIR/7" ] && ! grep -q "^waiting-on " "$TMP/writes" \
  && ok "AC2 next dispatch builds #7 while issue 9 is still open" \
  || fail "AC2 did not dispatch after the PR merged: $(ls "$INFLIGHT_DIR" 2>/dev/null) writes=$(cat "$TMP/writes")"

# ── 1b. thẻ Ready đã mang ⏳ không bị chọn (không nhờ lock inflight); thẻ thường vẫn được chọn
reset
rm -f "$INFLIGHT_DIR"/*
PROJECT_ITEMS_JSON=$(printf '%s' "$BOARD" | jq -c --arg l "$LBL" '.items |= map(if .content.number == 7 then .labels = [$l] else . end)')
top_card_in_column Ready
[ "$TOP_ISSUE" = 8 ] && ok "AC1 top card skips ${LBL} and picks #8" || fail "AC1 top card picked '#${TOP_ISSUE}'"
[ "$(person_count Ready)" = 1 ] && ok "AC1 person_count counts the ${LBL} card" || fail "AC1 person_count Ready = $(person_count Ready)"

# ── 3. chỉ thẻ ⏳: không tính RUNAWAY. Có việc khác đang kẹt thì vẫn tính.
reset
NO_PROGRESS_CYCLE_COUNT=0
PREV_DONE_SIG="1"
PROJECT_ITEMS_JSON=$(printf '%s' "$BOARD" | jq -c --arg l "$LBL" 'del(.items[] | select(.content.number != 7)) | .items[0].labels = [$l]')
rc=0
for i in 1 2 3 4; do record_cycle_progress "1" || rc=1; done
[ "$rc" = 0 ] && [ "$NO_PROGRESS_CYCLE_COUNT" = 0 ] \
  && ok "AC3 only a ${LBL} card: four ticks do not count toward RUNAWAY" \
  || fail "AC3 counted a waiting card: rc=$rc count=$NO_PROGRESS_CYCLE_COUNT"
NO_PROGRESS_CYCLE_COUNT=0
PROJECT_ITEMS_JSON=$(printf '%s' "$BOARD" | jq -c 'del(.items[] | select(.content.number != 12))')
rc=0
for i in 1 2; do record_cycle_progress "1" || rc=1; done
[ "$rc" = 1 ] && ok "AC3 a plain Ready card still trips RUNAWAY" || fail "AC3 plain Ready did not trip: rc=$rc count=$NO_PROGRESS_CYCLE_COUNT"
NO_PROGRESS_CYCLE_COUNT=0
PROJECT_ITEMS_JSON=$(printf '%s' "$BOARD" | jq -c --arg l "$LBL" '
  .items = [ .items[] | select(.content.number == 7 or .content.number == 8)
    | if .content.number == 7 then .labels = [$l] else .status = "Building" end ]')
rc=0
for i in 1 2; do record_cycle_progress "1" || rc=1; done
[ "$rc" = 1 ] && ok "AC3 Building plus ${LBL} still trips RUNAWAY" || fail "AC3 stuck Building was exempt: rc=$rc count=$NO_PROGRESS_CYCLE_COUNT"

# ── 4. hai thẻ cùng file: thẻ proceed được giao, thẻ conflictWith không có lock
reset
export STUB_PREFLIGHT_JSON='{"8":{"number":8,"verdict":"proceed","tag":"clean","reason":"","blockedBy":[],"conflictWith":[]}}'
SB_PREFLIGHT="$PF" dispatch_lane build 8 >/dev/null 2>&1
sleep 0.4
export STUB_PREFLIGHT_JSON='{"7":{"number":7,"verdict":"sequence","tag":"overlap","reason":"open PRs touch the same files","blockedBy":[8],"conflictWith":[52]}}'
SB_PREFLIGHT="$PF" dispatch_lane build 7 >/dev/null 2>&1
sleep 0.2
[ -e "$INFLIGHT_DIR/8" ] && [ ! -e "$INFLIGHT_DIR/7" ] && ! grep -q "move PVTI_7 Blocked" "$TMP/writes" \
  && ! grep -q "move PVTI_7 Building" "$TMP/writes" && ! grep -q "move PVTI_7 QA" "$TMP/writes" && ! grep -q "move PVTI_7 Review" "$TMP/writes" \
  && ok "AC4 #8 dispatched, #7 stays Ready — not both in Building/QA/Review" \
  || fail "AC4 both cards active: inflight=$(ls "$INFLIGHT_DIR" 2>/dev/null | tr '\n' ' ') writes=$(cat "$TMP/writes")"

[ "$FAILS" -eq 0 ] && { echo "test_runner_file_wait: PASS"; exit 0; }
echo "test_runner_file_wait: $FAILS FAILED"
exit 1
