#!/usr/bin/env bash
# Regression test: hooks/proof_gate.sh (Stop hook) — a reply that opens with XONG must
# point at a real acceptance PNG made in this turn (rules/essentials.md "Every prompt",
# step 4): reports/proof-<yyyyMMdd-HHmmss>.png, PNG bytes, > 8 KB, newer than the turn's
# user message. Any other status line is not checked. Never traps the session.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/proof_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

REPO="$TMP/repo"; mkdir -p "$REPO/reports"
TR="$TMP/transcript.jsonl"
# The turn started 2 s ago (the user's prompt); a proof must be newer than that.
turn_start() { python3 -c 'import datetime,json,sys
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=2)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi X"}}))' > "$TR"; }
png() { python3 - "$1" "$2" <<'PY'
import sys, zlib, struct, os
path, size = sys.argv[1], int(sys.argv[2])
sig = b"\x89PNG\r\n\x1a\n"
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
data = sig + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)) + chunk(b"IDAT", os.urandom(max(size - 60, 1))) + chunk(b"IEND", b"")
open(path, "wb").write(data)
PY
}
stop() { # <reply text> [stop_hook_active]
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s-p","hook_event_name":"Stop","transcript_path":sys.argv[1],
    "last_assistant_message":sys.argv[2],"stop_hook_active":sys.argv[3]=="1"}))' "$TR" "$1" "${2:-0}" \
  | CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
reset() { rm -f "$REPO/.claude/audit-gate/proof_gate.state"; }

turn_start
stop "CHƯA XONG
Không có thiết bị online."; [ $? = 0 ] && ok "CHƯA XONG: not checked" || fail "CHƯA XONG blocked"

stop "XONG
Đã sửa lỗi X.
Gate exit 0"; rc=$?
[ "$rc" = 2 ] && grep -q "proof-" "$TMP/err" && ok "XONG without a proof PNG: blocked, names reports/proof-*.png" || fail "XONG without proof (rc=$rc)"

reset; turn_start
P="reports/proof-20260924-101500.png"; png "$REPO/$P" 20000
stop "**XONG**
Đã sửa lỗi X.
Gate exit 0 · ảnh $P · serial emulator-5554"; rc=$?
[ "$rc" = 0 ] && ok "XONG with a fresh real PNG > 8 KB: allowed" || fail "valid proof blocked (rc=$rc err=$(head -3 "$TMP/err"))"

reset; turn_start
S="reports/proof-20260924-101501.png"; png "$REPO/$S" 3000
stop "XONG
ảnh $S"; rc=$?
[ "$rc" = 2 ] && grep -q "8 KB" "$TMP/err" && ok "PNG under 8 KB: blocked" || fail "small PNG not blocked (rc=$rc)"

reset
O="reports/proof-20260101-000000.png"; png "$REPO/$O" 20000; touch -d '2026-01-01 00:00' "$REPO/$O"; turn_start
stop "XONG
ảnh $O"; rc=$?
[ "$rc" = 2 ] && grep -qi "cũ\|trước lượt" "$TMP/err" && ok "PNG older than the turn: blocked" || fail "old PNG not blocked (rc=$rc err=$(head -2 "$TMP/err"))"

reset; turn_start
F="reports/proof-20260924-101502.png"; head -c 20000 /dev/urandom > "$REPO/$F"
stop "XONG
ảnh $F"; rc=$?
[ "$rc" = 2 ] && grep -q "PNG" "$TMP/err" && ok "not PNG bytes: blocked" || fail "fake PNG not blocked (rc=$rc)"

reset; turn_start
stop "XONG
ảnh reports/proof-20260924-101599.png"; rc=$?
[ "$rc" = 2 ] && ok "cited PNG missing on disk: blocked" || fail "missing PNG not blocked (rc=$rc)"

# Loop guard: 2 blocks for the same session, then the stop goes through with a warning.
reset; turn_start
stop "XONG"; r1=$?; stop "XONG" 1; r2=$?; stop "XONG" 1; r3=$?
[ "$r1" = 2 ] && [ "$r2" = 2 ] && [ "$r3" = 0 ] && grep -q systemMessage "$TMP/out" \
  && ok "loop guard: releases after 2 blocks with a user-visible warning" || fail "loop guard (r1=$r1 r2=$r2 r3=$r3)"

reset; turn_start
PROOF_GATE=0 stop "XONG"; [ $? = 0 ] && grep -q "PROOF_GATE=0" "$REPO/.claude/audit-gate/proof_gate.log" \
  && ok "PROOF_GATE=0 skips, logged" || fail "escape hatch"

if [ "$FAILS" -ne 0 ]; then echo "proof gate: $FAILS FAILED"; exit 1; fi
echo "proof gate: all checks passed"
