#!/usr/bin/env bash
# P5 (04/11): bin/unity-proof.sh xin CÙNG khoá máy với unity-batch.sh và pool `unity` của heavy_slot (<slot dir>/unity-1.lock).
# Trước đây nó giữ khoá cũ ~/.config/universal-agent-devkit/unity-batch.lock: proof mở được Editor thứ hai trong lúc một suite
# Unity của gate đang chạy (review độc lập 04/11).
# (p1) khoá chung bị giữ, không UNITY_BATCH_LOCK: hết UNITY_LOCK_WAIT_S thì exit 2, không mở Editor
# (p2) nhả khoá ⇒ proof chạy, exit 0
# Tương thích bash 3.2.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CMD="$DEVKIT_DIR/bin/unity-proof.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/dk-unity-proof-lock.XXXXXX")"
HOLDER=""
cleanup() {
  touch "$TMP/release" 2>/dev/null || true
  [ -n "$HOLDER" ] && { kill "$HOLDER" 2>/dev/null || true; wait "$HOLDER" 2>/dev/null || true; }
  rm -rf "$TMP"
}
trap cleanup EXIT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

unset UNITY_BATCH_LOCK SB_HEAVY_SLOT_HELD UNITY_LOCK_WAIT_S
export SB_HEAVY_SLOT_DIR="$TMP/slots"
mkdir -p "$TMP/bin" "$SB_HEAVY_SLOT_DIR"
cat > "$TMP/bin/nice" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "-n" ]; then shift 2; fi
exec "$@"
SH
chmod +x "$TMP/bin/nice"
export PATH="$TMP/bin:$PATH"
FAKE="$TMP/FakeUnity"
cat > "$FAKE" <<'SH'
#!/bin/sh
: > "$STARTED"
proj=""
while [ $# -gt 0 ]; do
  case "$1" in -projectPath) proj="$2"; shift;; esac
  shift
done
mkdir -p "$proj/Temp"; head -c 20000 /dev/urandom > "$proj/Temp/shot.png"
exit 0
SH
chmod +x "$FAKE"
P="$TMP/proj"; mkdir -p "$P/Temp"

python3 - "$SB_HEAVY_SLOT_DIR/unity-1.lock" "$TMP/held" "$TMP/release" <<'PY' &
import fcntl, os, sys, time
with open(sys.argv[1], "a") as fh:
    fcntl.flock(fh, fcntl.LOCK_EX)
    open(sys.argv[2], "w").close()
    end = time.monotonic() + 60
    while time.monotonic() < end and not os.path.exists(sys.argv[3]):
        time.sleep(0.03)
PY
HOLDER=$!
i=0
while [ ! -f "$TMP/held" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
[ -f "$TMP/held" ] || { fail "thiết lập: không giữ được unity-1.lock"; exit 1; }

STARTED="$TMP/started1" UNITY="$FAKE" UNITY_LOCK_WAIT_S=1 \
  bash "$CMD" --project "$P" --method Ok.Method --shot Temp/shot.png --out "$TMP/out1.png" >"$TMP/p1.log" 2>&1
rc=$?
if [ "$rc" -eq 2 ] && [ ! -f "$TMP/started1" ]; then
  ok "(p1) khoá unity chung bị giữ: proof không mở Editor, exit 2 sau UNITY_LOCK_WAIT_S"
else
  fail "(p1) rc=$rc started=$([ -f "$TMP/started1" ] && echo yes || echo no): $(tail -3 "$TMP/p1.log" | tr '\n' ' ')"
fi

touch "$TMP/release"; wait "$HOLDER" 2>/dev/null || true; HOLDER=""
STARTED="$TMP/started2" UNITY="$FAKE" UNITY_LOCK_WAIT_S=5 \
  bash "$CMD" --project "$P" --method Ok.Method --shot Temp/shot.png --out "$TMP/out2.png" >"$TMP/p2.log" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$TMP/started2" ] && [ -s "$TMP/out2.png" ]; then
  ok "(p2) khoá trống: proof chạy, chép PNG, exit 0"
else
  fail "(p2) rc=$rc: $(tail -3 "$TMP/p2.log" | tr '\n' ' ')"
fi

[ "$FAILS" -eq 0 ] && echo "test_unity_proof_shared_lock: PASS" || { echo "test_unity_proof_shared_lock: FAIL ($FAILS)"; exit 1; }
