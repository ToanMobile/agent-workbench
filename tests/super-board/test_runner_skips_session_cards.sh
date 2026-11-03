#!/usr/bin/env bash
# 03/11: hooks/session_card.sh files a card (label `session`) for every chat task and parks it in Building. The runner's
# startup_reconcile sends every Building card with no live lock and no non-bot assignee back to Ready (reclaim_stranded_building);
# bot_identity is the owner's own login, so an assignee cannot exempt it, and a session card in Ready would be built by a worker
# that duplicates the work of the chat session.
# Law: reclaim_stranded_building leaves a Building card labelled `session` alone; an unlabelled one still goes back to Ready.
# Bash 3.2 compatible.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-session-card.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

unset SB_GITHUB_READ_STRICT
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"
BOT_LOGIN="sb-bot"
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; }
log() { echo "$*" >> "$TMP/log"; }
fetch_project_items() { :; }
issue_is_open() { return 0; }
cd "$TMP" || exit 1

PROJECT_ITEMS_JSON='{"items":[
 {"id":"PVTI_1","status":"Building","labels":["session"],"content":{"type":"Issue","number":1,"title":"s","assignees":["sb-bot"]}},
 {"id":"PVTI_2","status":"Building","labels":["bug"],"content":{"type":"Issue","number":2,"title":"b","assignees":["sb-bot"]}}]}'
: > "$TMP/writes"; : > "$TMP/log"
reclaim_stranded_building
grep -qx "move PVTI_1 Ready" "$TMP/writes" && fail "session card #1 was sent back to Ready" || ok "Building card labelled session stays in Building"
grep -qx "move PVTI_2 Ready" "$TMP/writes" && ok "control: unlabelled stranded card #2 still goes back to Ready" || fail "control #2 not reclaimed: $(cat "$TMP/writes")"

# labels may also come nested under content (the shape sync_waiting_labels accepts)
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_3","status":"Building","content":{"type":"Issue","number":3,"title":"s","assignees":[],"labels":[{"name":"session"}]}}]}'
: > "$TMP/writes"
reclaim_stranded_building
grep -q "move PVTI_3" "$TMP/writes" && fail "nested-label session card #3 was moved" || ok "nested content.labels shape is honoured too"

[ "$FAILS" -eq 0 ] && echo "ALL PASS" || echo "$FAILS FAILED"
exit "$FAILS"
