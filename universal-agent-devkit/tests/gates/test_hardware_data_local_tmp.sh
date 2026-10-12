#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh, /data/local/tmp (user decision 2026-10-12: allow it). adb's scratch folder holds pushed APKs,
# logcat dumps and test files; clearing it cannot brick a device. The rm rule (SYS_PARTS) read every path under /data as a system
# partition, so the everyday cleanup was refused once the Dot 20 quote fix stopped it slipping through. Allowed now: a target that
# IS /data/local/tmp or sits under it. Still refused: a target that leaves it (`..`), one the shell expands at run time ($, `),
# a sibling whose name only starts with tmp, a glob on the folder name itself, and every other path under /data.
# Only the hook runs here — never the command.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${HW_HOOK:-$DEVKIT_DIR/hooks/hardware_safety_gate.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

P="$TMP/work/proj"
mkdir -p "$P/src"
git -C "$P" init -q . && git -C "$P" config user.email t@t && git -C "$P" config user.name t && git -C "$P" config commit.gpgsign false
printf 'x\n' > "$P/src/a.kt" && git -C "$P" add -A && git -C "$P" commit -qm init

check() {
  local want="$1" c="$2"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  if [ "$rc" = "$want" ]; then ok "rc $rc: $c"; else fail "rc $rc (want $want): $c — $(head -c 160 "$TMP/err" | tr '\n' ' ')"; fi
}

# Allowed: adb's scratch folder, quoted or not
check 0 'adb shell rm -rf /data/local/tmp/*'
check 0 'adb shell "rm -rf /data/local/tmp/*"'
check 0 "adb -s emulator-5554 shell 'rm -rf /data/local/tmp/app-debug.apk'"
check 0 'adb shell rm -rf /data/local/tmp'
check 0 'adb shell rm -rf /data/local/tmp/logs/'

# Refused: everything else under /data, and every way out of the scratch folder
check 2 'adb shell rm -rf /data/local/tmp/../../system'
check 2 'adb shell "rm -rf /data/local/tmp/../x"'
check 2 'adb shell "rm -rf /data/local/tmp/$X"'
check 2 'adb shell "rm -rf /data/local/tmp/`cat f`"'
check 2 'adb shell rm -rf /data/local/tmpfoo'
check 2 'adb shell rm -rf /data/local/tmp*'
check 2 'adb shell rm -rf /data/local'
check 2 'adb shell rm -rf /data/data/com.example.app'
check 2 'adb shell "rm -rf /data/local/tmp/x /data/app"'
check 2 'adb shell "rm -rf /data/local/tmp/x; rm -rf /system/*"'
check 2 'adb shell rm -rf /data/*'

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
