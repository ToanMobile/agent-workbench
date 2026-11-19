#!/usr/bin/env bash
# #1295 follow-up (19/11): `reclaim_stranded_building` skipped EVERY `session` card (hooks/session_card.sh tracking card: a session working in Building with no lock is
# normal). But when a real PR runs on branch issue-<N>-* the card is real work: card #1295 sat in Building for a day after its builder finished (PR #1297), and that
# orphan PR held #1350 through the file-overlap preflight. New rule:
#  - session card WITH an open PR on issue-<N>-*   -> recovered like any stranded card (Building -> Ready);
#  - session card WITHOUT an open PR (or unreadable) -> untouched, as before;
#  - a normal card                                  -> recovered, as before.
# Offline: stubs for the GitHub reads and writes. bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-stranded-session-1295.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
unset SB_GITHUB_READ_STRICT
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
BOT_LOGIN="sb-bot"
log() { echo "$*" >> "$TMP/log"; }
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; return 0; }
issue_locked() { return 1; }
issue_is_open() { return 0; }
# open PR head by issue: 300 has one, 301 has none, 302 is a normal card
issue_pr_head() { case "$1" in 300) printf 'abc1234def' ;; *) printf '' ;; esac; }
PROJECT_ITEMS_JSON='{"items":[
 {"id":"PVTI_300","status":"Building","labels":["session"],"content":{"type":"Issue","number":300,"title":"s","assignees":["sb-bot"]}},
 {"id":"PVTI_301","status":"Building","labels":["session"],"content":{"type":"Issue","number":301,"title":"s","assignees":["sb-bot"]}},
 {"id":"PVTI_302","status":"Building","labels":["bug"],"content":{"type":"Issue","number":302,"title":"n","assignees":["sb-bot"]}}]}'
cd "$TMP" || exit 1
: > "$TMP/writes"; : > "$TMP/log"
reclaim_stranded_building

grep -qx "move PVTI_300 Ready" "$TMP/writes" && ok "session card WITH an open PR (#300) -> Building -> Ready" || fail "session card with a PR not recovered: $(tr '\n' ';' < "$TMP/writes")"
grep -q "move PVTI_301" "$TMP/writes" && fail "session card WITHOUT a PR (#301) was moved" || ok "session card without a PR (#301) is left alone"
grep -qx "move PVTI_302 Ready" "$TMP/writes" && ok "normal card (#302) -> Ready as before" || fail "normal card not recovered: $(tr '\n' ';' < "$TMP/writes")"

echo
[ "$FAILS" -eq 0 ] && { echo "test_runner_stranded_session_card_pr_1295: PASS"; exit 0; } || { echo "test_runner_stranded_session_card_pr_1295: FAIL ($FAILS)"; exit 1; }
