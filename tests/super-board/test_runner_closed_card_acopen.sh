#!/usr/bin/env bash
# #1222: C) closed-issue sweep removes a leftover ac-open label after the card went to Done; D) dispatch_lane starts no lane for
# an issue that is still CLOSED (ac-open, reopen failed). Real functions (SB_LIB_ONLY=1), stubs for gh/board. SB_RUNNER=<file> for RED.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="${SB_RUNNER:-$ROOT/.claude/bin/super-board-run.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
T=$(mktemp -d "${TMPDIR:-/tmp}/sb-closed-acopen.XXXXXX"); trap 'rm -rf "$T"' EXIT
cat > "$T/read.py" <<'SH'
#!/bin/sh
case "$*" in
  *"--json number,stateReason"*) echo '[{"number":7,"stateReason":"COMPLETED"}]' ;;
  *stateReason*) echo '{"stateReason":"COMPLETED","labels":[{"name":"ac-open"}]}' ;;
  *) echo CLOSED ;;
esac
SH

# C: sweep. issue_is_open stubbed as "closed, goes to Done"; card carries ac-open on the snapshot.
: > "$T/c"
SB_LIB_ONLY=1 bash -c '
  R="$1"; D="$2"; set --
  . "$R" >/dev/null 2>&1
  SB_GITHUB_READ="$D/read.py"; python3() { sh "$@"; }
  PROJECT_ITEMS_JSON="{\"items\":[{\"id\":\"I7\",\"status\":\"Building\",\"labels\":[\"ac-open\"],\"content\":{\"type\":\"Issue\",\"number\":7}}]}"
  log() { echo "log: $*" >> "$D/c"; }
  issue_locked() { return 1; }; issue_is_open() { return 1; }
  set_card_status() { echo "status: $*" >> "$D/c"; }; gh_checkpoint() { :; }
  gh_write_once() { echo "write: $*" >> "$D/c"; }
  SWEEP_CLOSED_NEXT=0; INFLIGHT_DIR="$D/inflight"; BOT_LOGIN=""
  sweep_closed_cards' _ "$RUNNER" "$T" >/dev/null 2>&1
grep -q 'status: I7 Done' "$T/c" && grep -q 'write: issue edit 7 --remove-label ac-open' "$T/c" \
  && ok "C: sweep removes leftover ac-open after Done" || fail "C: $(tr '\n' '|' < "$T/c")"

# D: closed + ac-open + reopen fails: real issue_is_open returns 0, dispatch_lane must still skip (no lane started).
: > "$T/d"
SB_LIB_ONLY=1 bash -c '
  R="$1"; D="$2"; set --
  . "$R" >/dev/null 2>&1
  SB_GITHUB_READ="$D/read.py"; python3() { sh "$@"; }
  PROJECT_ITEMS_JSON="{\"items\":[{\"content\":{\"number\":7},\"labels\":[\"ac-open\"]}]}"
  log() { echo "log: $*" >> "$D/d"; }
  issue_locked() { return 1; }; gh_checkpoint() { :; }
  gh_write_once() { return 1; }
  dispatch_lane build 7; echo "rc=$?" >> "$D/d"' _ "$RUNNER" "$T" >/dev/null 2>&1
grep -q 'skip dispatch lane=build issue=#7 — issue is CLOSED' "$T/d" && ! grep -q 'log: dispatch lane=' "$T/d" && grep -q 'rc=0' "$T/d" \
  && ok "D: dispatch_lane skips an issue that is still CLOSED" || fail "D: $(tr '\n' '|' < "$T/d")"

[ "$FAILS" -eq 0 ] && { echo "runner closed ac-open: all checks passed"; exit 0; }
echo "runner closed ac-open: $FAILS FAILED"; exit 1
