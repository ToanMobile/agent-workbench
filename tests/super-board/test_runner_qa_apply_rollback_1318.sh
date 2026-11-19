#!/usr/bin/env bash
# #1318 R8 (19/11): `qa_apply_report` added `loop:rebuild-N+1` before `set_card_status`. When the move failed the card kept the new label
# and the next pass counted the same failed QA twice, reaching rebuild_cap early.
#  - ❌ report, label added, move fails -> the label change is undone (N+1 removed, N restored) and the function returns 1.
#  - ❌ report, move succeeds           -> the label stays N+1, no rollback.
# bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-qa-rollback-1318.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
unset SB_GITHUB_READ_STRICT
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
REBUILD_CAP=3
BOT_LOGIN=""
log() { :; }
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
issue_last_comment() { printf '[qa] [report] ❌ not ok\n'; }
issue_pr_head() { printf ''; }
MOVE_RC=0
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; return "$MOVE_RC"; }
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_7","status":"QA","labels":["bug","loop:rebuild-1"],"content":{"type":"Issue","number":7,"title":"c"}}]}'

: > "$TMP/writes"; MOVE_RC=1
qa_apply_report 7 4; rc=$?
[ "$rc" -eq 1 ] && ok "failed move -> returns 1" || fail "failed move returned $rc"
grep -q -- "--remove-label loop:rebuild-2" "$TMP/writes" && grep -q -- "--add-label loop:rebuild-1" "$TMP/writes" \
  && ok "failed move -> loop:rebuild-2 removed and loop:rebuild-1 restored" || fail "label not rolled back: $(tr '\n' ';' < "$TMP/writes")"

: > "$TMP/writes"; MOVE_RC=0
qa_apply_report 7 4; rc=$?
[ "$rc" -eq 0 ] && ok "successful move -> returns 0" || fail "successful move returned $rc"
grep -q -- "--remove-label loop:rebuild-2" "$TMP/writes" && fail "rollback ran after a successful move" || ok "successful move -> no rollback"

echo
[ "$FAILS" -eq 0 ] && { echo "test_runner_qa_apply_rollback_1318: PASS"; exit 0; } || { echo "test_runner_qa_apply_rollback_1318: FAIL ($FAILS)"; exit 1; }
