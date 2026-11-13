#!/usr/bin/env bash
# Hồi quy #1120 (kitbug early-death): 11/11 22:30-22:32 worker lane qa của #828 chết sau 3-6 s, hai lần liền, vì account pool giao
# engine grok đã hết số dư: "API error (status 402 Payment Required): Grok Build usage balance exhausted". note_worker_limit chỉ
# biết mẫu "hit your limit"/RESOURCE_EXHAUSTED nên không ghi account đó là hết; runner giao lại đúng account chết → early-death lặp.
# Mẫu 402/số dư cạn phải ghi account vào usage-<acct>.json như một limit thường. Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/.claude/bin/super-board-run.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-402-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state" "$TMP/repo/wl"
export SB_STATE_DIR="$TMP/state"
unset SB_GITHUB_READ_STRICT
SB_LIB_ONLY=1 . "$RUNNER" || { echo "✖ could not source $RUNNER"; exit 1; }
set +e
log() { echo "$*" >> "$TMP/log"; }
cd "$TMP/repo" || exit 1
paused_until() { jq -r '[.rate_limits[]? | select(.used_percentage >= 100) | .resets_at] | first // empty' "$TMP/state/usage-$1.json" 2>/dev/null; }

cat > wl/worker-qa-828.log <<'LOG'
=== dispatch lane=qa issue=#828 at 2026-11-11T15:30:03Z ===
prompt: Run super-qa on issue #828

account_pool: engine=grok account=grok config_dir=
Internal error: {
  "message": "API error (status 402 Payment Required): Grok Build usage balance exhausted",
  "http_status": 402
}
Error: Internal error: {
  "message": "API error (status 402 Payment Required): Grok Build usage balance exhausted",
  "http_status": 402
}

worker_exit: exit=1 signal=none elapsed=3s
LOG
note_worker_limit "wl/worker-qa-828.log"
r=$(paused_until grok); now=$(date +%s)
[ -n "$r" ] && [ "$r" -gt "$now" ] && ok "402 balance exhausted: the dead account is marked paused" \
  || fail "402 balance exhausted not recorded (resets_at='$r')"
[ "$FAILS" -eq 0 ]
