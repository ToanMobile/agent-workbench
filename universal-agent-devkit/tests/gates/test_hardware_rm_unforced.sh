#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh, recursive rm WITHOUT -f (2026-10-09): `rm -r <project>`, `rm -r ..` (from the project),
# `rm -r ~` and `rm -r /` exited 0 while the same with -rf exited 2 — rm_segment_problem returned early unless the command
# was both recursive and forced. A non-interactive rm -r does not ask: it deletes all the same. Now a recursive rm without
# -f is refused when a target is or holds the project root, the home folder, / or a system partition; any other target
# (a top-level project folder like the pinned `rm -r src`, a sibling folder, a build output) stays allowed.
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

H="$TMP/home"               # the hook's home folder: outside the project, so only the home rule can refuse `rm -r ~`
P="$TMP/work/proj"          # the project, under mktemp (/tmp on Linux, $TMPDIR on macOS)
mkdir -p "$H/cache" "$P/src" "$P/build" "$TMP/work/other"
git -C "$P" init -q . && git -C "$P" config user.email t@t && git -C "$P" config user.name t && git -C "$P" config commit.gpgsign false
printf 'x\n' > "$P/src/a.kt" && git -C "$P" add -A && git -C "$P" commit -qm init

# check <want rc> <command>
check() {
  local want="$1" c="$2"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$P" > "$TMP/in.json"
  ( cd "$P" && HOME="$H" CLAUDE_PROJECT_DIR="$P" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  if [ "$rc" = "$want" ]; then ok "rc $rc: $c"; else fail "rc $rc (want $want): $c — $(head -c 200 "$TMP/err" | tr '\n' ' ')"; fi
}

# Refused: the target is or holds the project root, the home folder, / or a system partition
check 2 "rm -r $P"
check 2 'rm -r ..'
check 2 'rm -R ../'
check 2 'rm -r .'
check 2 'rm -r *'
check 2 "rm --recursive $TMP/work"
check 2 'cd .. && rm -r proj'
check 2 'rm -r ~'
check 2 'rm -r $HOME'
check 2 "rm -r $TMP"
check 2 'rm -r /'
check 2 'sudo rm -r -- /'
check 2 'rm -r /system'
check 2 'rm -R /vendor'
check 2 'find . -exec rm -r {} +'
check 2 'rm -rf ..'                       # control: with -f it was already refused

# Allowed: any other target, as before (hooks/tests/hook_contract_test.sh pins `rm -r src`)
check 0 'rm -r src'
check 0 'rm -r build'
check 0 'rm -r ../other'
check 0 "rm -r $TMP/work/other"
check 0 'rm -r ~/cache'
check 0 'rm -r /tmp/devkit-unforced-x'
check 0 'find . -name __pycache__ -exec rm -r {} +'
check 0 'rm -f notes.txt'

[ "$FAILS" -eq 0 ] && echo "✅ test_hardware_rm_unforced: all passed" || { echo "❌ test_hardware_rm_unforced: $FAILS failed"; exit 1; }
