#!/usr/bin/env bash
# Regression test: profiles/android/scripts/qa/dump-view-hierarchy.sh, against a fake `adb` on PATH.
# Before the fix it (1) exited 0 with no device online — a silent pass — and (2) ran `adb shell …` with no -s,
# so a serial in the device denylist was dumped anyway; (3) it gave no screen density, so bounds (px) could
# not be turned into dp for the ≥ 48 dp touch-target rule.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DUMP="$DEVKIT_DIR/profiles/android/scripts/qa/dump-view-hierarchy.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP/proj"
mkdir -p "$TMP/bin" "$TMP/proj"
unset ANDROID_SERIAL HARDWARE_OVERRIDE HARDWARE_SAFETY_GATE ADB_DENY_SERIALS ADB_ALLOW_SERIALS
export XDG_CONFIG_HOME="$TMP/xdg"   # the developer's own device policy must not leak in

# Fake adb: FAKE_DEVICES online devices (emu-1 …). Every call is appended to $TMP/calls.
cat > "$TMP/bin/adb" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/calls"
[ "\${1:-}" = "-s" ] && shift 2
case "\${1:-}" in
  devices) echo "List of devices attached"
           i=1; while [ "\$i" -le "\${FAKE_DEVICES:-1}" ]; do printf 'emu-%s\tdevice\n' "\$i"; i=\$((i+1)); done ;;
  get-state) [ "\${FAKE_DEVICES:-1}" -ge 1 ] && echo device || { echo "error: no devices" >&2; exit 1; } ;;
  shell) case "\${2:-}" in
           date) echo "09-23 10:00:00.000" ;;
           uiautomator) echo "UI hierchary dumped to: /sdcard/view_dump.xml" ;;
           wm) echo "Physical density: 420" ;;
         esac ;;
  pull) printf '<hierarchy rotation="0"/>\n' > "\$3"; echo "1 file pulled" ;;
  logcat) cat "$TMP/logcat" 2>/dev/null ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMP/bin/adb"
export PATH="$TMP/bin:$PATH"

FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
reset() { : > "$TMP/calls"; : > "$TMP/logcat"; rm -f "$TMP/out.xml"; export FAKE_DEVICES=1; unset ADB_DENY_SERIALS; }

reset; export FAKE_DEVICES=0
bash "$DUMP" "$TMP/out.xml" >"$TMP/log" 2>&1; rc=$?
[ "$rc" -eq 3 ] && ok "no device -> exit 3 (UNVERIFIED, never a silent pass)" || bad "no device -> exit $rc, expected 3"

reset; export ADB_DENY_SERIALS=emu-1
bash "$DUMP" "$TMP/out.xml" >"$TMP/log" 2>&1; rc=$?
if [ "$rc" -ne 0 ] && ! grep -q uiautomator "$TMP/calls"; then ok "denied serial -> refused (exit $rc), nothing dumped"
else bad "denied serial -> exit $rc, uiautomator calls: $(grep -c uiautomator "$TMP/calls")"; fi

reset; export FAKE_DEVICES=2
bash "$DUMP" "$TMP/out.xml" >"$TMP/log" 2>&1; rc=$?
[ "$rc" -eq 3 ] && ok "two devices, no ANDROID_SERIAL -> exit 3" || bad "two devices -> exit $rc, expected 3"

reset
bash "$DUMP" "$TMP/out.xml" >"$TMP/log" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ -s "$TMP/out.xml" ]; then ok "one device -> exit 0 and XML written"; else bad "one device -> exit $rc, xml=$(ls "$TMP/out.xml" 2>&1)"; fi
grep -q '^density=420' "$TMP/log" && ok "prints density=420 for px -> dp" || bad "no density line: $(cat "$TMP/log")"
unscoped=$(grep -v -e '^devices' -e '^-s emu-1 ' "$TMP/calls" || true)
[ -z "$unscoped" ] && ok "every device call carries -s emu-1" || bad "adb calls without -s: $unscoped"

reset; export FAKE_DEVICES=2
bash "$DUMP" -s emu-2 "$TMP/out.xml" >"$TMP/log" 2>&1; rc=$?
other=$(grep -v -e '^devices' -e '^-s emu-2 ' "$TMP/calls" || true)
if [ "$rc" -eq 0 ] && [ -s "$TMP/out.xml" ] && [ -z "$other" ]; then ok "-s emu-2 with two devices -> dumps emu-2 into the positional path"
else bad "-s emu-2 -> exit $rc, other calls: $other"; fi

# OCR review 2026-11-19: adb-safe-exec without -p treats ANY crash in logcat as a failure, so a good dump failed whenever some
# other app crashed meanwhile (or the app under test had just crashed — a normal reason to dump its screen).
reset
printf '09-23 10:00:01.000 E AndroidRuntime: FATAL EXCEPTION: main\n09-23 10:00:01.000 E AndroidRuntime: Process: com.other.app, PID: 7\n' > "$TMP/logcat"
bash "$DUMP" "$TMP/out.xml" >"$TMP/log" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ -s "$TMP/out.xml" ] && ok "a crash of another app in logcat does not fail the dump" || bad "crash in logcat -> exit $rc: $(tail -3 "$TMP/log")"

reset; export ADB_DENY_SERIALS=emu-1
bash "$DUMP" -s emu-1 "$TMP/out.xml" >"$TMP/log" 2>&1; rc=$?
if [ "$rc" -ne 0 ] && ! grep -q uiautomator "$TMP/calls"; then ok "-s on a denied serial -> refused (exit $rc)"; else bad "-s denied serial -> exit $rc"; fi

exit $((FAILS > 0))
