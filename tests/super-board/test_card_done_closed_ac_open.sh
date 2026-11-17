#!/usr/bin/env bash
# #1222: `super-board-card.sh move N Done` refuses an OPEN issue with ac-open (old rule kept) but lets a CLOSED one through
# (closing is the owner's decision; the label is a stale trace). Offline, fake gh. SB_CARD=<file> runs another copy (RED check).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CARD="${SB_CARD:-$ROOT/.claude/bin/super-board-card.sh}"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-card-closed.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/cache"
printf '{"projectId":"P","fieldId":"F","options":{"Done":"o-done"},"items":{"7":"I7"}}' > "$TMP/cache/board-o-1.json"
cat > "$TMP/bin/gh" <<SH
#!/bin/sh
echo "\$*" >> "$TMP/calls"
case "\$*" in
  *"issue view"*) printf '{"state":"%s","labels":[{"name":"ac-open"}]}' "\$STATE" ;;
  *mutation*) echo '{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"I7"}}}}' ;;
  *) echo '{"data":{}}' ;;
esac
SH
chmod +x "$TMP/bin/gh"
run() { rm -f "$TMP/calls"; STATE="$1" PATH="$TMP/bin:$PATH" SB_CARD_CACHE_DIR="$TMP/cache" SB_GITHUB_RETRY_DELAY=0 \
  SB_GITHUB_HALT_FILE="$TMP/halt.json" bash "$CARD" --owner o --number 1 --repo o/r move 7 Done >"$TMP/out" 2>"$TMP/err"; }

run CLOSED; rc=$?
[ "$rc" -eq 0 ] && grep -q mutation "$TMP/calls" && ok "A: CLOSED + ac-open: move Done succeeds" || fail "A: rc=$rc $(cat "$TMP/err")"
run OPEN; rc=$?
[ "$rc" -eq 5 ] && ! grep -q mutation "$TMP/calls" && grep -q 'ac-open' "$TMP/err" && ok "B: OPEN + ac-open: still refused (exit 5)" || fail "B: rc=$rc"
[ "$FAILS" -eq 0 ] && { echo "card done closed ac-open: all checks passed"; exit 0; }
echo "card done closed ac-open: $FAILS FAILED"; exit 1
