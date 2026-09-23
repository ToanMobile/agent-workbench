#!/usr/bin/env bash
# Regression test: profiles/android/scripts/qa/adb-safe-exec.sh judges an adb command
# by the device (error output, logcat crashes/ANRs), not by adb's exit code — against
# a fake `adb` on PATH, so no device is needed.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SAFE="$DEVKIT_DIR/profiles/android/scripts/qa/adb-safe-exec.sh"
TRIAGE="$DEVKIT_DIR/profiles/android/scripts/qa/anr-logcat-triage.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP/proj"
mkdir -p "$TMP/bin" "$TMP/proj"
unset ANDROID_SERIAL HARDWARE_OVERRIDE HARDWARE_SAFETY_GATE

# Fake adb: FAKE_DEVICES online devices; `shell am …` prints $TMP/out and exits
# $FAKE_RC; `logcat` prints $TMP/logcat. Every call is appended to $TMP/calls.
cat > "$TMP/bin/adb" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/calls"
[ "\${1:-}" = "-s" ] && shift 2
case "\${1:-}" in
  devices) echo "List of devices attached"
           i=1; while [ "\$i" -le "\${FAKE_DEVICES:-1}" ]; do printf 'emu-%s\tdevice\n' "\$i"; i=\$((i+1)); done ;;
  get-state) [ "\${FAKE_DEVICES:-1}" -ge 1 ] && echo device || { echo "error: no devices" >&2; exit 1; } ;;
  shell) if [ "\${2:-}" = "date" ]; then echo "09-23 10:00:00.000"; else cat "$TMP/out" 2>/dev/null; exit "\${FAKE_RC:-0}"; fi ;;
  logcat) cat "$TMP/logcat" 2>/dev/null ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMP/bin/adb"
export PATH="$TMP/bin:$PATH"

FAILS=0
check() { # name expected actual
  if [ "$3" = "$2" ]; then echo "✔ $1"; else echo "✖ $1: exit $3, expected $2"; FAILS=$((FAILS + 1)); fi
}
reset() { : > "$TMP/out"; : > "$TMP/logcat"; : > "$TMP/calls"; export FAKE_RC=0 FAKE_DEVICES=1; }
run() { bash "$SAFE" -p com.example.app --wait 0 -- shell am start -W -n com.example.app/.Main >/dev/null 2>&1; echo $?; }

reset
printf 'Starting: Intent { cmp=com.example.app/.Main }\nStatus: ok\n' > "$TMP/out"
check "clean launch -> PASS" 0 "$(run)"
ls "$TMP/proj/.claude/audit-gate/adb-safe-exec/"*.log >/dev/null 2>&1 && echo "✔ evidence log written" \
  || { echo "✖ no evidence log"; FAILS=$((FAILS + 1)); }

reset
printf 'Starting: Intent { cmp=com.example.app/.Missing }\nError type 3\nError: Activity class {com.example.app/.Missing} does not exist.\n' > "$TMP/out"
check "'Error type 3' with adb exit 0 -> FAIL" 1 "$(run)"

reset
printf 'Status: ok\n' > "$TMP/out"
printf '09-23 10:00:01.000 E AndroidRuntime: FATAL EXCEPTION: main\n09-23 10:00:01.000 E AndroidRuntime: Process: com.example.app, PID: 4242\n09-23 10:00:01.000 E AndroidRuntime: java.lang.NullPointerException\n' > "$TMP/logcat"
check "crash of the package in logcat -> FAIL" 1 "$(run)"

reset
printf 'Status: ok\n' > "$TMP/out"
printf '09-23 10:00:01.000 E AndroidRuntime: FATAL EXCEPTION: main\n09-23 10:00:01.000 E AndroidRuntime: Process: com.other.app, PID: 7\n' > "$TMP/logcat"
check "another app's crash with -p -> PASS" 0 "$(run)"

reset
printf '09-23 10:00:05.000 E ActivityManager: ANR in com.example.app (com.example.app/.Main)\n' > "$TMP/logcat"
check "ANR of the package -> FAIL" 1 "$(run)"

reset
FAKE_RC=1; export FAKE_RC
check "adb exit 1 -> FAIL" 1 "$(run)"

reset
FAKE_DEVICES=0; export FAKE_DEVICES
check "no device -> UNVERIFIED, never PASS" 3 "$(run)"

reset
FAKE_DEVICES=2; export FAKE_DEVICES
check "two devices without -s -> UNVERIFIED" 3 "$(run)"
out="$(bash "$SAFE" -s emu-2 --wait 0 -- shell am start -n x/.Y 2>&1)"; check "two devices with -s -> PASS" 0 $?

reset
bash "$SAFE" --wait 0 -- remount >/dev/null 2>&1; rc=$?
check "remount through the wrapper is refused" 2 "$rc"
grep -q remount "$TMP/calls" && { echo "✖ adb remount was executed"; FAILS=$((FAILS + 1)); } || echo "✔ adb remount never ran"

reset
bash "$SAFE" --wait 0 >/dev/null 2>&1; check "no adb command -> usage error" 2 $?

reset
FAKE_DEVICES=0; export FAKE_DEVICES
bash "$TRIAGE" com.example.app >/dev/null 2>&1; check "anr-logcat-triage without a device -> UNVERIFIED (was exit 0)" 3 $?

if [ "$FAILS" -ne 0 ]; then
  echo "adb-safe-exec: $FAILS FAILED"; exit 1
fi
echo "adb-safe-exec: all checks passed"
