#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# adb-safe-exec.sh — run an adb command and judge it by what happened on the
# device, not by adb's exit code (anti false-green).
#
# `adb shell am start -n x/.Missing` prints "Error type 3" and exits 0; a crash or
# ANR a few seconds after launch never reaches the exit code at all. This wrapper:
#   1. needs exactly one online device (else exit 3 — never a silent pass)
#   2. refuses what hooks/hardware_safety_gate.sh blocks (remount, disable-verity,
#      dd of=/dev/…, fastboot flash …) — calling adb through this script must not
#      be a way around that gate
#   3. reads the DEVICE clock, runs the command, keeps its exit code and output
#   4. FAILs on error text adb prints with exit 0 (Error:, Error type N, Failure [,
#      Exception occurred while executing, INSTRUMENTATION_FAILED, FAILURES!!!)
#   5. waits --wait seconds (crashes surface late; ANRs need ≥ 5–10 s), then scans
#      logcat since that clock for FATAL EXCEPTION, ANR in, Fatal signal /
#      SIGSEGV / SIGABRT — only blocks naming PACKAGE when -p is given
# The command output and the logcat slice are saved under
# .claude/audit-gate/adb-safe-exec/ (git-ignored).
#
# Usage: adb-safe-exec.sh [-s SERIAL] [-p PACKAGE] [--wait SECONDS] -- <adb args…>
#   e.g. adb-safe-exec.sh -p com.example.app --wait 5 -- shell am start -W -n com.example.app/.MainActivity
# Exit: 0 PASS · 1 FAIL (exit code, error output, crash/ANR) · 2 usage / refused
#       3 UNVERIFIED (no adb, no or several devices, device clock / logcat unreadable)
# bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SERIAL="${ANDROID_SERIAL:-}"
PACKAGE=""
WAIT=3
usage() { sed -n '/^# Usage:/,/^# bash 3.2/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    -s) [ $# -ge 2 ] || usage; SERIAL="$2"; shift 2 ;;
    -p) [ $# -ge 2 ] || usage; PACKAGE="$2"; shift 2 ;;
    --wait) [ $# -ge 2 ] || usage; WAIT="$2"; shift 2 ;;
    --wait=*) WAIT="${1#*=}"; shift ;;
    --) shift; break ;;
    -h|--help) usage ;;
    *) echo "✖ adb-safe-exec: unknown option '$1' (adb arguments go after --)" >&2; exit 2 ;;
  esac
done
[ $# -gt 0 ] || usage
case "$WAIT" in ''|*[!0-9]*) echo "✖ adb-safe-exec: --wait needs whole seconds" >&2; exit 2 ;; esac

unverified() { echo "⚠️  UNVERIFIED — $1" >&2; exit 3; }
command -v adb >/dev/null 2>&1 || unverified "adb not found on PATH"
command -v python3 >/dev/null 2>&1 || unverified "python3 not found (needed to check the command and parse logcat)"

# 2. Same deny rules as the agent hook, applied to the command this script will run.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$SELF_DIR/../../../../hooks/hardware_safety_gate.sh"
CMDLINE="adb"
for a in "$@"; do CMDLINE="$CMDLINE $(printf '%q' "$a")"; done
if [ -f "$GATE" ]; then
  python3 -c 'import json,sys; print(json.dumps({"tool_input": {"command": sys.argv[1]}}))' "$CMDLINE" \
    | bash "$GATE" || { echo "✖ adb-safe-exec: refused by hardware_safety_gate" >&2; exit 2; }
else
  for a in "$@"; do
    case "$a" in remount|disable-verity|enable-verity|root|unroot|sideload)
      echo "✖ adb-safe-exec: '$a' can brick a device — refused (hardware_safety_gate.sh not found)" >&2; exit 2 ;;
    esac
  done
fi

# 1. Exactly one online device (or the one named by -s / ANDROID_SERIAL).
if [ -n "$SERIAL" ]; then
  STATE="$(adb -s "$SERIAL" get-state 2>/dev/null | tr -d '\r')"
  [ "$STATE" = "device" ] || unverified "device $SERIAL is not online (state: ${STATE:-none})"
  ADB=(adb -s "$SERIAL")
else
  ONLINE="$(adb devices 2>/dev/null | tr -d '\r' | awk 'NR>1 && $2=="device"{print $1}')"
  COUNT="$(printf '%s' "$ONLINE" | grep -c . || true)"
  [ "$COUNT" -ge 1 ] || unverified "no online Android device (adb devices)"
  [ "$COUNT" -eq 1 ] || unverified "$COUNT devices online — pick one with -s SERIAL"
  SERIAL="$ONLINE"
  ADB=(adb -s "$SERIAL")
fi

# 3. Device clock (host clocks drift from the device's; logcat -T needs the device's).
T0="$("${ADB[@]}" shell date "'+%m-%d %H:%M:%S.000'" 2>/dev/null | tr -d '\r')"
case "$T0" in [0-1][0-9]-[0-3][0-9]\ *) ;; *) unverified "cannot read the device clock (got: '${T0}')" ;; esac

OUT="$("${ADB[@]}" "$@" 2>&1)"
RC=$?

# 4. Error text that adb reports with exit code 0.
ERR="$(printf '%s\n' "$OUT" | grep -E -m 5 '^[[:space:]]*(Error:|Error type [0-9]|Failure \[|Exception occurred while executing|INSTRUMENTATION_FAILED|INSTRUMENTATION_STATUS_CODE: -[0-9]|FAILURES!!!|Security exception|adb: error)' || true)"

# 5. Crashes / ANRs logged since the command started.
[ "$WAIT" -gt 0 ] && sleep "$WAIT"
LOG="$("${ADB[@]}" logcat -d -T "$T0" -b main -b system -b crash 2>&1)"
LRC=$?
CRASH=""
if [ "$LRC" -eq 0 ]; then
  CRASH="$(printf '%s\n' "$LOG" | python3 -c '
import re, sys
pkg = sys.argv[1]
lines = sys.stdin.read().splitlines()
marker = re.compile(r"FATAL EXCEPTION|ANR in |Fatal signal \d+|SIGSEGV|SIGABRT")
owner = (re.compile(r"Process: %s\b|ANR in %s\b|\(%s\)|>>> %s <<<" % ((re.escape(pkg),) * 4)) if pkg else None)
out, i = [], 0
while i < len(lines):
    if marker.search(lines[i]):
        block = lines[i:i + 8]
        if owner is None or any(owner.search(l) for l in block):
            out.extend(block + ["--"])
            i += 8
            continue
    i += 1
print("\n".join(out[:60]))
' "$PACKAGE")"
fi

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
EVID_DIR="$ROOT/.claude/audit-gate/adb-safe-exec"
EVID=""
if mkdir -p "$EVID_DIR" 2>/dev/null; then
  [ -f "$ROOT/.claude/audit-gate/.gitignore" ] || printf '*\n' > "$ROOT/.claude/audit-gate/.gitignore" 2>/dev/null || true
  EVID="$EVID_DIR/$(date +%Y%m%d-%H%M%S)-$$.log"
  {
    echo "command : $CMDLINE"
    echo "device  : $SERIAL   package: ${PACKAGE:-<any>}   since: $T0   wait: ${WAIT}s"
    echo "exit    : $RC"
    echo "===== output ====="; printf '%s\n' "$OUT"
    echo "===== logcat since $T0 (exit $LRC) ====="; printf '%s\n' "$LOG"
  } > "$EVID" 2>/dev/null || EVID=""
fi

printf '%s\n' "$OUT"
echo "─────────────────────────────────────────────"
REASONS=""
[ "$RC" -eq 0 ] || REASONS="${REASONS}  • adb exited $RC"$'\n'
[ -z "$ERR" ] || REASONS="${REASONS}  • error in the output despite exit $RC:"$'\n'"$(printf '%s\n' "$ERR" | sed 's/^/      /')"$'\n'
[ -z "$CRASH" ] || REASONS="${REASONS}  • crash / ANR in logcat${PACKAGE:+ for $PACKAGE}:"$'\n'"$(printf '%s\n' "$CRASH" | head -30 | sed 's/^/      /')"$'\n'
if [ -n "$REASONS" ]; then
  echo "❌ FAIL — $CMDLINE"
  printf '%s' "$REASONS"
  [ -n "$EVID" ] && echo "  evidence: $EVID"
  exit 1
fi
if [ "$LRC" -ne 0 ]; then
  [ -n "$EVID" ] && echo "  evidence: $EVID"
  unverified "command exited 0 but logcat could not be read (exit $LRC) — crashes not checked"
fi
echo "✔ PASS — exit 0, no error output, no crash/ANR${PACKAGE:+ for $PACKAGE} in logcat within ${WAIT}s"
[ -n "$EVID" ] && echo "  evidence: $EVID"
exit 0
