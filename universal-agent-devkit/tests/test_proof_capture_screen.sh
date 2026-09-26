#!/usr/bin/env bash
# proof-capture.py refuses a proof the screen cannot show (GeelyEx2 2026-09-26: the car reported
# mWakefulness=Asleep / Display OFF and the "proof" was an all-black PNG, byte-identical to one
# from 09-24): a screen that is not Awake is not captured; a near one-colour image is rejected
# and removed. Unknown wakefulness (no dumpsys output) still captures.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$DEVKIT_DIR/bin/proof-capture.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

python3 - "$TMP" <<'PY'
import os, struct, sys, zlib
def png(path, rows, w, level):
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    raw = b"".join(b"\x00" + r for r in rows)
    ihdr = struct.pack(">IIBBBBB", w, len(rows), 8, 6, 0, 0, 0)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, level)) + chunk(b"IEND", b""))
w, h = 320, 240
png(sys.argv[1] + "/content.png", [os.urandom(w * 4) for _ in range(h)], w, 6)
png(sys.argv[1] + "/black.png", [b"\x00\x00\x00\xff" * w] * h, w, 0)   # stored: > 8 KB yet one colour
# A real screen an encoder filters with "Up": a vertical gradient background (every filtered row
# the same) and one small label (~1.7% of rows). Its pixel rows all differ; it must be accepted.
def up_png(path, pixel_rows, w):
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    prev, raw = bytes(w * 4), b""
    for r in pixel_rows:
        raw += b"\x02" + bytes((a - b) & 0xff for a, b in zip(r, prev)); prev = r
    ihdr = struct.pack(">IIBBBBB", w, len(pixel_rows), 8, 6, 0, 0, 0)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 0)) + chunk(b"IEND", b""))
H = 480
rows = [bytes([y % 256, y % 256, 64, 255]) * w for y in range(H)]
for y in range(200, 208):
    rows[y] = os.urandom(w * 4)
up_png(sys.argv[1] + "/gradient.png", rows, w)
PY

P="$TMP/p"; mkdir -p "$P"
printf '%s\n' '{"proof":{"defaultProvider":"device","providers":{"device":{"type":"adb","serial":"192.168.9.9:5555"}}}}' > "$P/.antigravity-pm.json"
cat > "$TMP/adb" <<SH
#!/bin/sh
case "\$*" in
  *devices*) echo "List of devices attached"; echo "192.168.9.9:5555 device" ;;
  *"dumpsys power"*) [ -n "\${FAKE_BYTES:-}" ] && printf '\\377\\376 junk\\n'; [ -n "\${FAKE_WAKE:-}" ] && echo "  mWakefulness=\${FAKE_WAKE}" ;;
  *screencap*) cat "\${FAKE_PNG}" ;;
esac
exit 0
SH
printf '#!/bin/sh\nexit 0\n' > "$TMP/emu"; chmod +x "$TMP/adb" "$TMP/emu"
cap() { rm -rf "$P/reports"; FAKE_WAKE="$1" FAKE_PNG="$TMP/$2" python3 "$CMD" --project "$P" --adb "$TMP/adb" --emulator "$TMP/emu" > "$TMP/out" 2>&1; }
pngs() { ls "$P"/reports/proof-*.png 2>/dev/null | wc -l | tr -d ' '; }

cap Awake content.png; rc=$?
[ "$rc" = 0 ] && [ "$(pngs)" = 1 ] && ok "awake screen with content: captured" || fail "awake: rc=$rc $(cat "$TMP/out")"
cap Asleep content.png; rc=$?
[ "$rc" != 0 ] && [ "$(pngs)" = 0 ] && grep -q "Asleep" "$TMP/out" && ok "screen Asleep: refused before capture, no PNG" \
  || fail "asleep: rc=$rc pngs=$(pngs) $(cat "$TMP/out")"
cap Dozing content.png; rc=$?
[ "$rc" != 0 ] && [ "$(pngs)" = 0 ] && ok "screen Dozing: refused" || fail "dozing: rc=$rc $(cat "$TMP/out")"
cap Awake black.png; rc=$?
[ "$rc" != 0 ] && [ "$(pngs)" = 0 ] && grep -qi "một màu\|mot mau" "$TMP/out" && ok "one-colour image: rejected and removed" \
  || fail "black: rc=$rc pngs=$(pngs) $(cat "$TMP/out")"
cap Awake gradient.png; rc=$?
[ "$rc" = 0 ] && [ "$(pngs)" = 1 ] && ok "gradient screen with one small label (Up-filtered rows): accepted" \
  || fail "gradient: rc=$rc $(cat "$TMP/out")"
FAKE_BYTES=1 cap Awake content.png; rc=$?
[ "$rc" = 0 ] && [ "$(pngs)" = 1 ] && ok "non-UTF-8 dumpsys output: no crash, captured" || fail "bytes: rc=$rc $(cat "$TMP/out")"
cap "" content.png; rc=$?
[ "$rc" = 0 ] && [ "$(pngs)" = 1 ] && ok "wakefulness unknown: still captured" || fail "unknown: rc=$rc $(cat "$TMP/out")"

[ "$FAILS" -eq 0 ] && echo "✅ test_proof_capture_screen: all passed" || { echo "❌ test_proof_capture_screen: $FAILS failed"; exit 1; }
