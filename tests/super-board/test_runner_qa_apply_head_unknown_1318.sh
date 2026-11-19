#!/usr/bin/env bash
# #1318 audit finding (19/11): `qa_apply_report` was fail-open when the PR head could not be read. A report that names `@ <sha>` with an
# empty `issue_pr_head` was routed anyway, so a stale verdict could move the card. Unknown head -> return 1, no write, the old path decides.
# bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-qa-head-1318.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
unset SB_GITHUB_READ_STRICT
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
REBUILD_CAP=3
BOT_LOGIN=""
log() { :; }
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; return 0; }
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_7","status":"QA","labels":["bug"],"content":{"type":"Issue","number":7,"title":"c"}}]}'
issue_last_comment() { printf '[qa] [report] ✅ ok @ abc1234\n'; }

: > "$TMP/writes"; issue_pr_head() { printf ''; }
qa_apply_report 7 4; rc=$?
[ "$rc" -eq 1 ] && ok "unknown PR head -> returns 1" || fail "unknown PR head returned $rc"
[ ! -s "$TMP/writes" ] && ok "unknown PR head -> no write" || fail "wrote: $(tr '\n' ';' < "$TMP/writes")"

: > "$TMP/writes"; issue_pr_head() { printf 'abc1234deadbeef'; }
qa_apply_report 7 4; rc=$?
[ "$rc" -eq 0 ] && ok "matching head -> routed" || fail "matching head returned $rc"

echo
[ "$FAILS" -eq 0 ] && { echo "test_runner_qa_apply_head_unknown_1318: PASS"; exit 0; } || { echo "test_runner_qa_apply_head_unknown_1318: FAIL ($FAILS)"; exit 1; }
