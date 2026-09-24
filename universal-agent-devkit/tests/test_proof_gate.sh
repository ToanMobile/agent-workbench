#!/usr/bin/env bash
# Regression test: hooks/proof_gate.sh (Stop hook) — a reply that opens with XONG needs both
# halves of rules/essentials.md "Every prompt" step 5, from this turn:
#   - a `post-fix-gate --run-tests --full` exit 0 on the CURRENT code (the gate's receipt in
#     .git/postfix-gate/full_pass.json, fingerprint = bin/tree_fp.py), and
#   - a real acceptance PNG: reports/proof-<yyyyMMdd-HHmmss>.png, PNG bytes, > 8 KB, newer
#     than the turn's user message.
# Any other status line is not checked. Never traps the session.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/proof_gate.sh"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

REPO="$TMP/repo"; mkdir -p "$REPO/src" "$REPO/templates" "$REPO/reports"
( cd "$REPO" && git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt && echo 'exit 0' > result.sh
  cat > templates/regression_matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh result.sh"}]}]}
JSON
  git add -A && git commit -qm init && echo "fun ok() = 2" > src/Core.kt )
TR="$TMP/transcript.jsonl"
# The turn started 2 s ago (the user's prompt); gate run and proof must be newer than that.
turn_start() { sleep 1; python3 -c 'import datetime,json
t=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=1)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
print(json.dumps({"type":"user","timestamp":t,"message":{"role":"user","content":"sửa lỗi X"}}))' > "$TR"; }
# `--run-tests --full` on the current code; its exit-0 receipt is what XONG needs.
gate_full() { CLAUDE_PROJECT_DIR="$REPO" python3 "$GATE" --run-tests --full --no-checklist >"$TMP/gate" 2>&1; }
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
[ "$rc" = 2 ] && grep -q "proof-" "$TMP/err" && grep -q -- "--full" "$TMP/err" \
  && ok "XONG with neither full gate nor PNG: blocked, names both" || fail "XONG without proof (rc=$rc)"

# Full gate exit 0 on this code, then the screenshot: the complete handover.
reset; turn_start; gate_full; g=$?
P="reports/proof-20260924-101500.png"; png "$REPO/$P" 20000
stop "**XONG**
Đã sửa lỗi X.
Gate exit 0 · ảnh $P · serial emulator-5554"; rc=$?
[ "$g" = 0 ] && [ "$rc" = 0 ] && ok "full gate exit 0 + fresh real PNG: allowed (the PNG does not invalidate the receipt)" \
  || fail "valid handover blocked (gate=$g rc=$rc err=$(head -3 "$TMP/err"))"

# PNG present, but the code changed after the full run.
reset; turn_start; gate_full
echo "fun ok() = 3" > "$REPO/src/Core.kt"
P2="reports/proof-20260924-101510.png"; png "$REPO/$P2" 20000
stop "XONG
ảnh $P2"; rc=$?
[ "$rc" = 2 ] && grep -q "code đã đổi" "$TMP/err" && ok "code changed after the full gate run: blocked" || fail "stale receipt accepted (rc=$rc err=$(head -3 "$TMP/err"))"

# Full run in an earlier turn only.
reset; gate_full; turn_start
P3="reports/proof-20260924-101520.png"; png "$REPO/$P3" 20000
stop "XONG
ảnh $P3"; rc=$?
[ "$rc" = 2 ] && grep -q "trước lượt" "$TMP/err" && ok "full gate run from an earlier turn: blocked" || fail "old receipt accepted (rc=$rc err=$(head -3 "$TMP/err"))"

# A failing full run leaves no receipt.
reset; echo 'exit 1' > "$REPO/result.sh"; (cd "$REPO" && git commit -qam red && echo "fun ok() = 4" > src/Core.kt)
turn_start; gate_full; g=$?
P4="reports/proof-20260924-101530.png"; png "$REPO/$P4" 20000
stop "XONG
ảnh $P4"; rc=$?
[ "$g" != 0 ] && [ "$rc" = 2 ] && grep -q -- "--full" "$TMP/err" && ok "full gate not exit 0: blocked" || fail "failing gate accepted (gate=$g rc=$rc)"
echo 'exit 0' > "$REPO/result.sh"; (cd "$REPO" && git commit -qam green && echo "fun ok() = 5" > src/Core.kt)

# PNG checks, with a valid full run in the turn.
reset; turn_start; gate_full
S="reports/proof-20260924-101501.png"; png "$REPO/$S" 3000
stop "XONG
ảnh $S"; rc=$?
[ "$rc" = 2 ] && grep -q "8 KB" "$TMP/err" && ok "PNG under 8 KB: blocked" || fail "small PNG not blocked (rc=$rc)"

reset
O="reports/proof-20260101-000000.png"; png "$REPO/$O" 20000; touch -t 202601010000 "$REPO/$O"; turn_start; gate_full
stop "XONG
ảnh $O"; rc=$?
[ "$rc" = 2 ] && grep -q "ảnh cũ" "$TMP/err" && ok "PNG older than the turn: blocked" || fail "old PNG not blocked (rc=$rc err=$(head -2 "$TMP/err"))"

reset; turn_start; gate_full
F="reports/proof-20260924-101502.png"; head -c 20000 /dev/urandom > "$REPO/$F"
stop "XONG
ảnh $F"; rc=$?
[ "$rc" = 2 ] && grep -q "PNG" "$TMP/err" && ok "not PNG bytes: blocked" || fail "fake PNG not blocked (rc=$rc)"

reset; turn_start; gate_full
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
