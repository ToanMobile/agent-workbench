#!/usr/bin/env bash
# hooks/shell_norm.py ansi_c_to_single (#618): a NUL (\x00 / \0 / \u0000) inside an ANSI-C $'…' word ends the word in bash, so $'git\x00foo' is `git`.
# The guard used to drop the NUL and keep decoding ("gitfoo"), so a forced push behind it read as another program and passed.
# Real block-dangerous-git.sh, fed JSON on stdin only (nothing runs). GG_HOOK points at a scratch copy for a mutation check.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GG="${GG_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
unset HARDWARE_SAFETY_GATE HARDWARE_OVERRIDE DEVKIT_ALLOW_BRANCH CDPATH
P="$TMP/work/proj"
mkdir -p "$P"
git -C "$P" init -q . && git -C "$P" config user.email t@t && git -C "$P" config user.name t && git -C "$P" config commit.gpgsign false
printf 'z\n' > "$P/README.md"
git -C "$P" add -A && git -C "$P" commit -qm init
FAILS=0

# check <want rc> <command>
check() {
  local want="$1" c="$2"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" XDG_CONFIG_HOME="$TMP/xdg" bash "$GG" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  if [ "$rc" = "$want" ]; then echo "✔ rc $rc: $c"; else echo "✖ rc $rc (want $want): $c — $(head -c 160 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; FAILS=$((FAILS + 1)); fi
}

echo "   #618: a NUL ends the ANSI-C word; the rest of its body is dropped, the command after it is judged as typed"
check 2 $'git$\'\\x00foo\' push --force origin main'
check 2 $'git$\'\\0foo\' push --force origin main'
check 2 $'git$\'\\u0000foo\' push --force origin main'
check 2 $'$\'git\\x00zz\' push --force origin main'
check 2 $'git$\'\\x00\\\'x\' push --force origin main'
check 0 $'git$\'\\x00foo\' status'

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
