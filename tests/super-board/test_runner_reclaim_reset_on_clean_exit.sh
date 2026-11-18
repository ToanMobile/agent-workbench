#!/usr/bin/env bash
# Regression #1266 (17/11): #1266 died 3 times from a runner bug (#1267), the card went Blocked, the bug was fixed and the
# next build worker finished cleanly (exit=0 + success result), but the reclaim ledger inflight/reclaims/<issue> kept the 3
# old epochs, so the first new crash inside 24h would block the card again at once.
# Rule: note_worker_exit on a lane=build worker that ended clean (worker_ended_clean) clears the card's ledger.
# A crash (exit!=0), a clean exit of another lane, or exit=0 without a success result keeps it.
# bash 3.2 compatible.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-reclaim-reset.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

unset SB_GITHUB_READ_STRICT
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
INFLIGHT_DIR="$TMP/inflight"
gh_checkpoint() { :; }
gh() { :; }
log() { :; }

# mklog <file> <exit> <result-json-or-empty>
mklog() {
  { echo "=== dispatch test ==="
    [ -n "$3" ] && echo "$3"
    echo "worker_exit: exit=$2 signal=none elapsed=10s"; } > "$1"
}
seed() { mkdir -p "$INFLIGHT_DIR/reclaims"; printf '1\n2\n3\n' > "$INFLIGHT_DIR/reclaims/$1"; }
OKRES='{"type":"result","subtype":"success","is_error":false}'

# A: lane build, exit=0 + success -> ledger cleared
rm -rf "$INFLIGHT_DIR"; seed 7; mklog "$TMP/a.log" 0 "$OKRES"
LANE=build WORKER_LOG="$TMP/a.log" note_worker_exit 7
[ ! -e "$INFLIGHT_DIR/reclaims/7" ] && ok "A: clean build exit clears the ledger" || fail "A: ledger survived a clean build exit"

# B: lane build, exit=1 -> ledger kept
rm -rf "$INFLIGHT_DIR"; seed 8; mklog "$TMP/b.log" 1 ""
LANE=build WORKER_LOG="$TMP/b.log" note_worker_exit 8
[ -s "$INFLIGHT_DIR/reclaims/8" ] && ok "B: crashed build keeps the ledger" || fail "B: ledger cleared on a crash"

# C: lane qa, clean -> ledger kept (the ledger counts build deaths only)
rm -rf "$INFLIGHT_DIR"; seed 9; mklog "$TMP/c.log" 0 "$OKRES"
LANE=qa WORKER_LOG="$TMP/c.log" note_worker_exit 9
[ -s "$INFLIGHT_DIR/reclaims/9" ] && ok "C: clean qa exit keeps the build ledger" || fail "C: qa exit cleared the build ledger"

# D: lane build, exit=0 but an error result (session limit) -> ledger kept
rm -rf "$INFLIGHT_DIR"; seed 10; mklog "$TMP/d.log" 0 '{"type":"result","subtype":"error_max_turns","is_error":true}'
LANE=build WORKER_LOG="$TMP/d.log" note_worker_exit 10
[ -s "$INFLIGHT_DIR/reclaims/10" ] && ok "D: exit=0 with an error result keeps the ledger" || fail "D: ledger cleared on exit=0 with an error result"

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL ($FAILS)"; exit 1; }
