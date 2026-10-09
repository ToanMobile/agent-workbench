#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh, find expressions that look filtered and are not (2026-10-09 follow-up, plan
# docs/plans/audit-2026-10-09-followup.md step 3 item 2). Any -name/-path/-regex filter counted as narrowing what find deletes,
# so `find . ! -name '*.keep' -delete` (everything BUT .keep files), `find . -name x -o -type f -delete` (the -o alternative with
# no filter deletes every file) and `find . ! \( -name a -o -name b \) -delete` were never judged by their start point. A filter
# under ! / -not narrows nothing, a negated group counts as no filter, and every -o alternative needs a filter of its own.
# A real filter keeps today's verdict, also with -o inside parentheses or a negated filter next to a positive one.
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

# Refused: the filter is negated, or an -o alternative has none, so find deletes (nearly) the whole start point
check 2 'find . -delete'                                        # control: no filter, already refused
check 2 "find . ! -name '*.keep' -delete"
check 2 "find . -not -name '*.keep' -delete"
check 2 "find . ! -path './vendor/*' -delete"
check 2 "find . ! -iname '*.KEEP' -delete"
check 2 "find . ! -regex '.*\\.keep' -delete"
check 2 "find src ! -name '*.kt' -delete"
check 2 "find . -name '*.pyc' -o -type f -delete"
check 2 "find . -name '*.pyc' -o -name '*' -delete"
check 2 "find . -name '*.pyc' -or -type f -delete"
check 2 'find . ! \( -name "*.keep" -o -name "*.md" \) -delete'
check 2 'find . -not \( -name "*.keep" \) -delete'
check 2 "find . ! -name '*.keep' -exec rm -rf {} +"
check 2 "find . ! -name '*.keep' -print0 | xargs -0 rm -rf"

# Allowed: a positive filter on every alternative, or a start point that may be deleted anyway
check 0 "find . -name '*.pyc' -delete"                          # control
check 0 'find . \( -name "*.pyc" -o -name "*.pyo" \) -delete'
check 0 "find . -name '*.pyc' -o -name '*.pyo' -delete"
check 0 "find . -name node_modules -prune -o -name '*.pyc' -delete"
check 0 "find . -type f -name '*.log' ! -name keep.log -delete"
check 0 "find . -name '*.pyc' -not -name keep.pyc -delete"
check 0 "find build ! -name '*.keep' -delete"
check 0 "find build -name '*.pyc' -o -type f -delete"
check 0 "find . -name '*.pyc' -print0 | xargs -0 rm -rf"
# a negated group only restricts what a positive filter already narrows (independent audit T0024): not a reason to refuse
check 0 'find . -name "*.txt" ! \( -name "*.py" \) -delete'
check 0 'find . -name "*.txt" -not \( -name "keep*" -o -name "*.md" \) -delete'

[ "$FAILS" -eq 0 ] && echo "✅ test_hardware_find_not_or: all passed" || { echo "❌ test_hardware_find_not_or: $FAILS failed"; exit 1; }
