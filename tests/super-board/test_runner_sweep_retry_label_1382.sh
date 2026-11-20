#!/usr/bin/env bash
# #1382: two runner sweep defects.
#  A) sweep_cap_progress must create loop:rebuild-(cap-1) before editing the card onto it (a repo without the label made the edit fail,
#     the card stayed Blocked and re-matched forever).
#  B) sweep_dead_sessions: a failed helper run says "retrying next tick", so SESSION_SWEEP_NEXT must not advance; a successful run still does.
# Offline; gh writes and the helper are stubs. bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-sweep-1382.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
unset SB_GITHUB_READ_STRICT SB_CAP_PROGRESS_MAX
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
INFLIGHT_DIR="$TMP/inflight"; mkdir -p "$INFLIGHT_DIR"; : > "$INFLIGHT_DIR/swept-cards"
REBUILD_CAP=2; SWEPT_CARDS=""
log() { echo "$*" >> "$TMP/log"; }
gh_checkpoint() { :; }
gh_write_once() { echo "gh $*" >> "$TMP/writes"; }
set_card_status() { echo "move $1 $2" >> "$TMP/writes"; return 0; }

# A) cap-progress creates the target label before the edit
B1=$'[merge-queue] [blocker] 🛑 blocked\nEvidence: tests/foo.sh:12 AssertionError boom'
B2=$'[reviewer] [blocker] 🛑 blocked\nEvidence: .claude/bin/x.sh:5 sai\nother.sh:9 different'
python3 -c 'import json,sys; print(json.dumps([{"body": b} for b in sys.argv[1:]]))' "$B1" "$B2" > "$TMP/c-7.json"
cap_progress_comments() { cat "$TMP/c-$1.json" 2>/dev/null; }
PROJECT_ITEMS_JSON='{"items":[{"id":"PVTI_7","status":"Blocked","labels":["bug","loop:rebuild-2"],"content":{"type":"Issue","number":7,"title":"c"}}]}'
: > "$TMP/writes"
sweep_cap_progress; rc=$?
[ "$rc" -eq 0 ] && ok "A: card moved (rc 0)" || fail "A: rc=$rc"
ln_create=$(grep -n "label create loop:rebuild-1" "$TMP/writes" | head -1 | cut -d: -f1)
ln_edit=$(grep -n "issue edit 7 --add-label loop:rebuild-1" "$TMP/writes" | head -1 | cut -d: -f1)
[ -n "$ln_create" ] && [ -n "$ln_edit" ] && [ "$ln_create" -lt "$ln_edit" ] \
  && ok "A: label create precedes the edit" || fail "A: create=$ln_create edit=$ln_edit writes: $(tr '\n' ';' < "$TMP/writes")"

# B) dead-session sweep: failure keeps the retry due next tick
printf '#!/bin/sh\nexit 3\n' > "$TMP/fail.sh"; printf '#!/bin/sh\necho "{\\"closed\\":[]}"\n' > "$TMP/pass.sh"
session_sweep_helper() { echo "$HELPER_SCRIPT"; }
CONFIG_PATH="$TMP/cfg.json"; RUN_MANIFEST="$TMP/manifest"; : > "$RUN_MANIFEST"
PROJECT_ITEMS_JSON='{"items":[{"id":"s","status":"Building","labels":["session"],"content":{"type":"Issue","number":1}}]}'
# the runner runs `python3 <helper>`: make the helper a python file exiting 3 / 0
printf 'import sys\nsys.exit(3)\n' > "$TMP/fail.py"; printf 'print("{\\"closed\\": []}")\n' > "$TMP/pass.py"
HELPER_SCRIPT="$TMP/fail.py"; SESSION_SWEEP_NEXT=0
sweep_dead_sessions; rc=$?
[ "${SESSION_SWEEP_NEXT:-0}" = "0" ] && ok "B: failed helper leaves SESSION_SWEEP_NEXT untouched (retry next tick)" || fail "B: SESSION_SWEEP_NEXT advanced to $SESSION_SWEEP_NEXT after failure"
HELPER_SCRIPT="$TMP/pass.py"; SESSION_SWEEP_NEXT=0
sweep_dead_sessions; rc=$?
[ "${SESSION_SWEEP_NEXT:-0}" -gt 0 ] && ok "B: successful helper still advances the cadence" || fail "B: success did not advance SESSION_SWEEP_NEXT"

[ "$FAILS" -eq 0 ] && echo "ALL PASS" || echo "$FAILS FAILED"
exit "$FAILS"
