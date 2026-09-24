#!/usr/bin/env bash
# proof-capture.py: declared serial only when it is online; otherwise boot the
# phone AVD. Never screencap a dead address or a denylisted phone.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$DEVKIT_DIR/bin/proof-capture.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

plan() {
  python3 "$CMD" --project "$1" --adb "$2" --emulator "$3" --plan-only --connect-timeout 1
}

# Serial that is already device → screencap that serial, do not boot.
P1="$TMP/online"; mkdir -p "$P1"
printf '%s\n' '{"proof":{"defaultProvider":"device","providers":{"device":{"type":"adb","serial":"192.168.1.20:5555","avd":"PhoneConnect"}}}}' > "$P1/.antigravity-pm.json"
ADB1="$P1/adb"; cat > "$ADB1" <<'SH'
#!/bin/sh
echo "List of devices attached"
echo "192.168.1.20:5555 device"
SH
chmod +x "$ADB1" "$P1/adb"
EMU1="$P1/emu"; printf '#!/bin/sh\nexit 0\n' > "$EMU1"; chmod +x "$EMU1"
out="$(plan "$P1" "$ADB1" "$EMU1")"; rc=$?
printf '%s' "$out" | grep -q '"action": "screencap"' && printf '%s' "$out" | grep -q '192.168.1.20:5555' \
  && [ "$rc" = 0 ] && ok "online declared serial is captured" || fail "online serial: rc=$rc $out"

# Declared serial absent, personal phone online and denied, AVD set → boot that AVD.
P2="$TMP/offline"; mkdir -p "$P2"
printf '%s\n' '{"proof":{"defaultProvider":"device","providers":{"device":{"type":"adb","serial":"192.168.1.20:5555","avd":"PhoneConnect"}}}}' > "$P2/.antigravity-pm.json"
printf '%s\n' 'RFCWA1KQT1Y' > "$P2/.adb-denylist"
ADB2="$P2/adb"; cat > "$ADB2" <<'SH'
#!/bin/sh
if [ "$1" = "devices" ]; then
  echo "List of devices attached"
  echo "RFCWA1KQT1Y device"
  exit 0
fi
if [ "$1" = "connect" ]; then exit 0; fi
echo "leak $*" >&2
exit 1
SH
chmod +x "$ADB2"
EMU2="$P2/emu"; printf '#!/bin/sh\necho PhoneConnect\n' > "$EMU2"; chmod +x "$EMU2"
out="$(plan "$P2" "$ADB2" "$EMU2")"; rc=$?
printf '%s' "$out" | grep -q '"action": "boot"' && printf '%s' "$out" | grep -q 'PhoneConnect' \
  && ! printf '%s' "$out" | grep -q 'RFCWA1KQT1Y' \
  && [ "$rc" = 0 ] && ok "offline serial boots the declared AVD, skips the denylisted phone" \
  || fail "boot plan: rc=$rc $out"

# No avd in config: the only non-car AVD is chosen. Car images are not.
P3="$TMP/pick"; mkdir -p "$P3"
printf '%s\n' '{"proof":{"defaultProvider":"device","providers":{"device":{"type":"adb","serial":"192.168.1.20:5555"}}}}' > "$P3/.antigravity-pm.json"
ADB3="$P3/adb"; cat > "$ADB3" <<'SH'
#!/bin/sh
echo "List of devices attached"
exit 0
SH
chmod +x "$ADB3"
EMU3="$P3/emu"; cat > "$EMU3" <<'SH'
#!/bin/sh
echo CarAuto33
echo CarConnect
echo PhoneConnect
SH
chmod +x "$EMU3"
out="$(plan "$P3" "$ADB3" "$EMU3")"; rc=$?
printf '%s' "$out" | grep -q '"avd": "PhoneConnect"' && ! printf '%s' "$out" | grep -q 'CarAuto' \
  && [ "$rc" = 0 ] && ok "no declared avd: boots the phone AVD, not the car images" \
  || fail "pick avd: rc=$rc $out"

# End to end with fakes: emulator is started, screencap is the emulator, not the dead IP.
P4="$TMP/cap"; mkdir -p "$P4/state"
python3 - "$P4/state/shot.png" <<'PY'
import sys, zlib, struct, os
path = sys.argv[1]
sig = b"\x89PNG\r\n\x1a\n"
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
data = sig + chunk(b"IHDR", struct.pack(">IIBBBBB", 8, 8, 8, 2, 0, 0, 0)) + chunk(b"IDAT", os.urandom(9000)) + chunk(b"IEND", b"")
open(path, "wb").write(data)
PY
printf '%s\n' '{"proof":{"defaultProvider":"device","providers":{"device":{"type":"adb","serial":"192.168.1.20:5555","avd":"PhoneConnect"}}}}' > "$P4/.antigravity-pm.json"
ADB4="$P4/adb"; cat > "$ADB4" <<SH
#!/bin/sh
echo "\$*" >> "$P4/adb-calls"
if [ "\$1" = "devices" ]; then
  echo "List of devices attached"
  if [ -f "$P4/state/booted" ]; then echo "emulator-5554 device"; fi
  exit 0
fi
if [ "\$1" = "connect" ]; then exit 0; fi
if [ "\$1" = "-s" ] && [ "\$3" = "shell" ]; then echo 1; exit 0; fi
if [ "\$1" = "-s" ] && [ "\$3" = "exec-out" ]; then cat "$P4/state/shot.png"; exit 0; fi
exit 1
SH
chmod +x "$ADB4"
EMU4="$P4/emu"; cat > "$EMU4" <<SH
#!/bin/sh
echo "\$*" >> "$P4/emu-args"
if [ "\$1" = "-list-avds" ]; then echo PhoneConnect; exit 0; fi
touch "$P4/state/booted"
exit 0
SH
chmod +x "$EMU4"
cap="$(python3 "$CMD" --project "$P4" --adb "$ADB4" --emulator "$EMU4" --connect-timeout 1 --boot-timeout 5 2>"$P4/err")"
rc=$?
printf '%s' "$cap" | grep -q 'serial: emulator-5554' \
  && [ -f "$P4"/reports/proof-*.png ] \
  && grep -q 'PhoneConnect' "$P4/emu-args" \
  && grep -q 'emulator-5554 exec-out screencap' "$P4/adb-calls" \
  && ! grep -q -- '-s 192.168.1.20' "$P4/adb-calls" \
  && [ "$rc" = 0 ] && ok "capture boots PhoneConnect and screencaps emulator-5554" \
  || fail "capture: rc=$rc out=$cap err=$(cat "$P4/err") calls=$(cat "$P4/adb-calls" 2>/dev/null)"

# Automotive profile with no declared avd boots the automotive image, not the phone.
P6="$TMP/auto"; mkdir -p "$P6/.agents"
printf '%s\n' '{"proof":{"defaultProvider":"xe","providers":{"xe":{"type":"adb","serial":"192.168.100.203:5555"}}}}' > "$P6/.antigravity-pm.json"
printf '%s\n' '{"profile":"automotive"}' > "$P6/.agents/active-profile.json"
out="$(plan "$P6" "$ADB3" "$EMU3")"; rc=$?
printf '%s' "$out" | grep -q '"avd": "CarConnect"' && ! printf '%s' "$out" | grep -q 'CarAuto33' \
  && [ "$rc" = 0 ] && ok "automotive profile boots CarConnect, not CarAuto33 or the phone" \
  || fail "automotive pick: rc=$rc $out"

# Unity / shell proof must not boot an Android emulator.
P5="$TMP/shell"; mkdir -p "$P5"
printf '%s\n' '{"proof":{"defaultProvider":"gameview","providers":{"gameview":{"type":"shell","command":"echo hi"}}}}' > "$P5/.antigravity-pm.json"
out="$(plan "$P5" "$ADB3" "$EMU3")"; rc=$?
printf '%s' "$out" | grep -q '"action": "fail"' && printf '%s' "$out" | grep -q 'shell' \
  && [ "$rc" = 1 ] && ok "non-adb provider is not sent to an Android emulator" \
  || fail "shell provider: rc=$rc $out"

[ "$FAILS" = 0 ] && echo "ok" || { echo "$FAILS failed"; exit 1; }
