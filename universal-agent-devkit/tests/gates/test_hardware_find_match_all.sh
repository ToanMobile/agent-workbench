#!/usr/bin/env bash
# hooks/hardware_safety_gate.sh, find with a filter that matches everything (2026-10-09): `find . -delete` was refused but
# `find . -name '*' -delete` (and -iname / -path / -ipath / -wholename '*', '*/*', -regex '.*') passed — any -name/-path/-regex
# filter counted as narrowing what find deletes, so its start points were never judged. A filter that matches every entry
# under the start points now counts as no filter, in find -delete, find -exec rm and find | xargs rm alike. A real filter
# (the pinned `find . -name __pycache__ -exec rm -rf {} +`, `-name '*.pyc'`) keeps today's verdict.
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

# Refused: the filter matches everything, so find deletes the whole start point
check 2 'find . -delete'                          # control: no filter, already refused
check 2 "find . -name '*' -delete"
check 2 'find . -name "*" -delete'
check 2 'find . -name \* -delete'
check 2 "find . -iname '*' -delete"
check 2 "find . -path '*' -delete"
check 2 "find . -path '*/*' -delete"
check 2 "find . -ipath '*/*' -delete"
check 2 "find . -wholename './*' -delete"
check 2 "find . -regex '.*' -delete"
check 2 "find . -type f -name '*' -delete"
check 2 "find src -name '*' -delete"
check 2 "find . -name '*' -exec rm -rf {} +"
check 2 "find . -path '*/*' -print0 | xargs -0 rm -rf"

# Allowed: a filter that narrows what find deletes, or a start point that may be deleted anyway
check 0 "find . -name '*.pyc' -delete"
check 0 'find . -name __pycache__ -exec rm -rf {} +'
check 0 "find . -iname '*.ORIG' -delete"
check 0 "find . -path '*/build/*' -delete"
check 0 "find . -regex '.*\\.pyc' -delete"
check 0 "find build -name '*' -delete"
check 0 "find . -name '*.pyc' -print0 | xargs -0 rm -rf"

[ "$FAILS" -eq 0 ] && echo "✅ test_hardware_find_match_all: all passed" || { echo "❌ test_hardware_find_match_all: $FAILS failed"; exit 1; }
