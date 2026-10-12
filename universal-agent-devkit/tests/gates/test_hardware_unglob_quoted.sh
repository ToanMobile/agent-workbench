#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh, a destructive rm on the device that quotes its command or its target, or aims at a root glob
# (2026-10-11 audit, reproduced on the real hook; plan review of T0033 found the second and third class, the fresh-context review
# the fourth and fifth):
#  1. `adb shell rm -rf /system/*` was refused but `adb shell "rm -rf /system/*"`, 'rm -rf /data/*', su -c "...", ssh car "..."
#     passed: unglob() meant to resolve a GLOBBED PROGRAM NAME (a?b, /opt/*/fastboot -> adb, fastboot) but it rewrote every
#     token whose last path component holds a glob, so the quoted command string (or a bare `/system/*` target) became `adb`
#     and the rm vanished from the normalised command. The unquoted original is useless to rm_hits once a quote clings to it.
#  2. `adb shell rm -rf "/system/*"` (only the target quoted) passed for the same reason.
#  3. `adb shell rm -rf /*` passed: SYS_PARTS read `/` + optional partition name + one of / whitespace end ; & |, never a `*`.
#  4. An unbalanced quote (a lone apostrophe in a trailing comment) made shlex raise, the hook fell back to the raw text, and the
#     quoted rm was out of sight again; nested quotes (sh -c with quotes inside quotes) and `\rm` were unwrapped one level only.
#  5. A glob in the first path component (/sys*, /s*, /dat?, /syste[m]) reached a system partition under any spelling.
# Fix: a variant of the command with every quote and backslash removed (no tokenising), and a SYS_PARTS alternative for a glob in the
# first path component. Only the hook runs here — never the command.
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

P="$TMP/work/proj"          # the project, under mktemp (/tmp on Linux, $TMPDIR on macOS)
mkdir -p "$P/src" "$P/build"
git -C "$P" init -q . && git -C "$P" config user.email t@t && git -C "$P" config user.name t && git -C "$P" config commit.gpgsign false
printf 'x\n' > "$P/src/a.kt" && git -C "$P" add -A && git -C "$P" commit -qm init

# check <want rc> <command>
check() {
  local want="$1" c="$2"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  if [ "$rc" = "$want" ]; then ok "rc $rc: $c"; else fail "rc $rc (want $want): $c — $(head -c 200 "$TMP/err" | tr '\n' ' ')"; fi
}

# Refused: the whole destructive command sits in ONE quoted argument
check 2 'adb shell rm -rf /system/*'                            # control: unquoted, already refused
check 2 'adb shell "rm -rf /system/*"'
check 2 "adb shell 'rm -rf /system/*'"
check 2 "adb shell 'rm -rf /data/*'"
check 2 'adb shell "rm -rf /system/*" ; true'
check 2 'adb shell "cd / && rm -rf /system/*"'                  # the command string does not start with rm
check 2 'adb shell "sync; rm -rf /data/*"'
check 2 'su -c "rm -rf /system/*"'
check 2 'ssh car "rm -rf /system/*"'
check 2 'adb -s emu shell "rm -rf /vendor/*"'

# Refused: only the TARGET is quoted (its own token has no whitespace, so a whitespace test on the token would miss it)
check 2 'adb shell rm -rf "/system/*"'
check 2 "adb shell rm -rf '/data/*'"
check 2 'adb shell rm -rf "/vendor/*"'

# Refused: a root glob as the target, quoted or not
check 2 'adb shell rm -rf /*'
check 2 'adb shell "rm -rf /*"'
check 2 'adb shell rm -rf "/*"'
check 2 "su -c 'rm -rf /*'"

# Refused: an unbalanced quote makes shlex give up, yet the shell still runs the first line (2026-10-12 review of Dot 20:
# a lone apostrophe in a trailing comment was enough to bring the unquoted-looking rm back out of sight)
check 2 "adb shell \"rm -rf /system/*\" # don't ask"
check 2 "adb shell \"rm -rf /system/*\" # it's fine"
check 2 "echo it's; adb shell \"rm -rf /system/*\""
# Refused: quotes inside quotes (shlex unwraps one level), a backslash before rm
check 2 "adb shell \"rm -rf '/system/*'\""
check 2 "adb shell \"sh -c 'rm -rf /*'\""
check 2 "adb shell 'rm -rf \"/*\"'"
check 2 "adb shell \"rm -rf '/system'/*\""
check 2 'adb shell "\rm -rf /system/*"'

# Refused: ANSI-C / locale quoting ($'...', $"...") leaves a `$` glued to the first word once the quotes are removed (`$rm` is no rm)
check 2 "adb shell \$'rm -rf /system/*'"
check 2 "adb shell rm -rf \$'/system/*'"
check 2 "su -c \$'rm -rf /data/*'"
check 2 'adb shell $"rm -rf /system/*"'
check 2 "adb shell \$'sync; rm -rf /vendor/*'"

# Refused: a glob in the FIRST path component reaches a system partition whichever letters it names
check 2 'adb shell rm -rf /sys*'
check 2 'adb shell rm -rf /s*'
check 2 'adb shell rm -rf /dat?'
check 2 'adb shell rm -rf /syste[m]'
check 2 'adb shell rm -rf /?ystem'
check 2 'adb shell rm -rf /vendor*'
check 2 'adb shell rm -rf /boot*'
check 2 'adb shell "rm -rf /d*"'
check 2 'su -c "rm -rf /pers*"'

# Refused: the other core partitions of Android 11+ (the first alternative named only system/vendor/boot/product/odm/data/persist/efs;
# audit of Dot 20, round 2: `/system_ext` fell through because the char after `/system` is `_`)
check 2 'adb shell rm -rf /system_ext/*'
check 2 'adb shell rm -rf /system_ext'
check 2 'adb shell "rm -rf /vendor_dlkm/lib"'
check 2 'adb shell rm -rf /apex/com.android.runtime'
check 2 'adb shell rm -rf /metadata'

# Allowed: a glob that harms nothing, or a target outside the system partitions
check 0 'adb shell rm -rf /sdcard/system_ext'                    # first component is sdcard
check 0 "echo it's fine"                                        # an unbalanced quote alone is not a reason to refuse
check 0 'adb shell rm -rf /sdcard/Download/*'
check 0 'adb shell "rm -rf /sdcard/*"'
check 0 'adb shell "ls /sys*"'
check 0 'adb shell "ls /system/*"'
check 0 'adb shell "cat /proc/*/status"'
check 0 'adb shell rm -rf "/sdcard/*"'
check 0 'echo "a b/*"'
check 0 "adb shell \$'ls /system/*'"                             # $'..' alone is no reason to refuse
check 0 "echo \$'a b' \$HOME"                                    # a `\$` not glued to a quote is untouched
check 0 'ls /opt/*/fastboot'                                    # a glob in an ARGUMENT, not the program

# Still refused: the globbed PROGRAM NAME that unglob() exists for (no rm in these, so only the resolved name can refuse them)
check 2 'a?b remount'
check 2 '/opt/*/fastboot flash boot x.img'
check 2 '/usr/local/bin/f*boot erase userdata'
check 2 '/usr/bin/fastbo?t erase userdata'

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
