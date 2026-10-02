#!/usr/bin/env bash
# proof-capture.py: declared serial only when it is online; otherwise boot the
# phone AVD. Never screencap a dead address or a denylisted phone.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
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

# ---------- iOS Simulator (xcrun simctl) ----------
# mkpng <path> real|black|small: level-0 zlib keeps real/black > 8 KB; black repeats one row; small < 8 KB.
mkpng() {
  python3 - "$1" "$2" <<'PY'
import os, struct, sys, zlib
path, kind = sys.argv[1], sys.argv[2]
w = h = 8 if kind == "small" else 120
row = lambda: b"\0" + (bytes(w * 3) if kind == "black" else os.urandom(w * 3))
raw = b"".join(row() for _ in range(h))
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                        + chunk(b"IDAT", zlib.compress(raw, 0)) + chunk(b"IEND", b""))
PY
}
# sim_project <dir> <profile|-> <booted udids…>: fake xcrun + an adb that only logs.
sim_project() {
  local d="$1" prof="$2"; shift 2
  mkdir -p "$d/state" "$d/.agents"
  [ "$prof" != "-" ] && printf '{"profile":"%s"}\n' "$prof" > "$d/.agents/active-profile.json"
  python3 - "$d/state/sims.json" "$@" <<'PY'
import json, sys
booted = sys.argv[2:]
devs = [{"udid": u, "name": "iPhone %d" % i, "state": "Booted", "isAvailable": True} for i, u in enumerate(booted)]
devs.append({"udid": "OFF-0000", "name": "iPhone Off", "state": "Shutdown", "isAvailable": True})
json.dump({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": devs}}, open(sys.argv[1], "w"))
PY
  mkpng "$d/state/shot.png" real
  cat > "$d/xcrun" <<SH
#!/bin/sh
echo "\$*" >> "$d/xcrun-calls"
if [ "\$1 \$2 \$3" = "simctl list devices" ]; then cat "$d/state/sims.json"; exit 0; fi
if [ "\$1 \$2" = "simctl io" ] && [ "\$4" = "screenshot" ]; then cp "$d/state/shot.png" "\$5"; exit 0; fi
exit 1
SH
  cat > "$d/adb" <<SH
#!/bin/sh
echo "\$*" >> "$d/adb-calls"
if [ "\$1" = "devices" ]; then echo "List of devices attached"; [ -f "$d/state/adb-online" ] && echo "R58M device"; exit 0; fi
if [ "\$1" = "-s" ] && [ "\$3" = "exec-out" ]; then cat "$d/state/shot.png"; exit 0; fi
exit 0
SH
  chmod +x "$d/xcrun" "$d/adb"
}
simcap() { python3 "$CMD" --project "$1" --adb "$1/adb" --emulator "$EMU1" --xcrun "$1/xcrun" --connect-timeout 1 "${@:2}"; }

S1="$TMP/ios"; sim_project "$S1" ios SIM-AAAA
out="$(simcap "$S1" 2>"$S1/err")"; rc=$?
printf '%s' "$out" | grep -q 'serial: SIM-AAAA' && ls "$S1"/reports/proof-*.png >/dev/null 2>&1 \
  && grep -q 'simctl io SIM-AAAA screenshot' "$S1/xcrun-calls" && [ ! -f "$S1/adb-calls" ] \
  && [ "$rc" = 0 ] && ok "ios profile: screenshots the booted simulator by UDID, never adb" \
  || fail "ios capture: rc=$rc out=$out err=$(cat "$S1/err")"

S2="$TMP/ios-none"; sim_project "$S2" ios
out="$(simcap "$S2" 2>&1)"; rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -qi 'simulator' && [ ! -f "$S2/adb-calls" ] \
  && ! ls "$S2"/reports/proof-*.png >/dev/null 2>&1 \
  && ok "ios profile with no booted simulator fails, no Android fallback" \
  || fail "ios none: rc=$rc out=$out adb=$(cat "$S2/adb-calls" 2>/dev/null)"

S3="$TMP/ios-two"; sim_project "$S3" ios SIM-AAAA SIM-BBBB
out="$(simcap "$S3" --plan-only 2>&1)"; rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'SIM-AAAA' && printf '%s' "$out" | grep -q 'SIM-BBBB' \
  && ok "two booted simulators: refuses to guess" || fail "ios two: rc=$rc out=$out"

S4="$TMP/android-sim"; sim_project "$S4" android SIM-AAAA; touch "$S4/state/adb-online"
out="$(simcap "$S4" --plan-only 2>&1)"; rc=$?
printf '%s' "$out" | grep -q '"action": "screencap"' && printf '%s' "$out" | grep -q 'R58M' \
  && [ "$rc" = 0 ] && ok "android profile keeps adb even while a simulator is booted" \
  || fail "android+sim: rc=$rc out=$out"

S5="$TMP/any-sim"; sim_project "$S5" - SIM-CCCC
out="$(simcap "$S5" --plan-only 2>&1)"; rc=$?
printf '%s' "$out" | grep -q '"action": "simctl"' && printf '%s' "$out" | grep -q 'SIM-CCCC' \
  && [ "$rc" = 0 ] && ok "no profile, no provider: the one booted simulator is used" \
  || fail "any sim: rc=$rc out=$out"

S6="$TMP/ios-black"; sim_project "$S6" ios SIM-AAAA; mkpng "$S6/state/shot.png" black
out="$(simcap "$S6" 2>&1)"; rc=$?
[ "$rc" = 1 ] && ! ls "$S6"/reports/proof-*.png >/dev/null 2>&1 && printf '%s' "$out" | grep -q 'mot mau' \
  && ok "simulator one-colour screenshot is refused and deleted" \
  || fail "ios black: rc=$rc out=$out"

# Review 7de08da: a declared AVD is an adb provider — a Booted simulator does not take it over.
S7="$TMP/avd-sim"; sim_project "$S7" game SIM-AAAA; touch "$S7/state/adb-online"
printf '%s\n' '{"proof":{"defaultProvider":"d","providers":{"d":{"avd":"Pixel"}}}}' > "$S7/.antigravity-pm.json"
out="$(simcap "$S7" --plan-only 2>&1)"; rc=$?
printf '%s' "$out" | grep -q '"action": "screencap"' && printf '%s' "$out" | grep -q 'R58M' \
  && [ "$rc" = 0 ] && ok "declared AVD keeps adb while a simulator is booted" || fail "avd+sim: rc=$rc out=$out"

# No provider, not ios: two Booted simulators are ambiguous → the adb path as before, not a failure.
S8="$TMP/two-any"; sim_project "$S8" - SIM-AAAA SIM-BBBB; touch "$S8/state/adb-online"
out="$(simcap "$S8" --plan-only 2>&1)"; rc=$?
printf '%s' "$out" | grep -q '"action": "screencap"' && [ "$rc" = 0 ] \
  && ok "no profile, two simulators: falls back to adb" || fail "two any: rc=$rc out=$out"

# A failed simulator capture leaves no proof-<stamp>.png behind.
S9="$TMP/ios-small"; sim_project "$S9" ios SIM-AAAA; printf 'not a png' > "$S9/state/shot.png"
out="$(simcap "$S9" 2>&1)"; rc=$?
[ "$rc" = 1 ] && ! ls "$S9"/reports/proof-*.png >/dev/null 2>&1 \
  && ok "failed simulator capture deletes the partial file" || fail "partial: rc=$rc out=$out $(ls "$S9/reports" 2>&1)"

# simctl JSON whose "devices" is not a map: no traceback, just "no simulator".
S10="$TMP/ios-badjson"; sim_project "$S10" ios; printf '{"devices": [{"state": "Booted"}]}' > "$S10/state/sims.json"
out="$(simcap "$S10" 2>&1)"; rc=$?
[ "$rc" = 1 ] && ! printf '%s' "$out" | grep -q Traceback \
  && ok "malformed simctl JSON is 'no simulator', not a traceback" || fail "badjson: rc=$rc out=$out"

# A valid PNG under 8 KB (screen not drawn yet): refused with the size message, no traceback, no file.
S11="$TMP/ios-tiny"; sim_project "$S11" ios SIM-AAAA; mkpng "$S11/state/shot.png" small
out="$(simcap "$S11" 2>&1)"; rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'byte' && ! printf '%s' "$out" | grep -q Traceback \
  && ! ls "$S11"/reports/proof-*.png >/dev/null 2>&1 \
  && ok "PNG under 8 KB is refused and deleted" || fail "tiny: rc=$rc out=$out"

# A provider that names a udid (no type, no serial/avd) is a simulator provider on any profile.
S12="$TMP/udid-only"; sim_project "$S12" game SIM-AAAA SIM-BBBB; touch "$S12/state/adb-online"
printf '%s\n' '{"proof":{"defaultProvider":"s","providers":{"s":{"udid":"SIM-BBBB"}}}}' > "$S12/.antigravity-pm.json"
out="$(simcap "$S12" --plan-only 2>&1)"; rc=$?
printf '%s' "$out" | grep -q '"action": "simctl"' && printf '%s' "$out" | grep -q 'SIM-BBBB' && [ "$rc" = 0 ] \
  && ok "declared udid picks that simulator" || fail "udid only: rc=$rc out=$out"

[ "$FAILS" = 0 ] && echo "ok" || { echo "$FAILS failed"; exit 1; }
