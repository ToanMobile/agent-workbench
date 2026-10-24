#!/usr/bin/env bash
# hooks/block-dangerous-git.sh: a worker must not kill or wait on processes BY NAME (#144).
# 20/10: `pkill -f post-fix-gate` in one board killed the gates of every other board and of the interactive session;
# `pgrep -f "git push"` made a wait loop outlast its own push by 9 minutes (it matched another session's push).
# Blocked: pkill, killall, pgrep -f / --full (also behind wrappers, sh -c, $( ), xargs, find -exec).
# Allowed: kill <PID>, plain `pgrep NAME` (read-only lookup), the words as data (echo, grep, git commit -m).
# Only the hook runs here — never the commands.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GG="${GG_HOOK:-$DEVKIT_DIR/hooks/block-dangerous-git.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
unset DEVKIT_ALLOW_BRANCH
P="$TMP/proj"
mkdir -p "$P"
git -C "$P" init -q .

# check <want rc> <command>
check() {
  local want="$1" c="$2"
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s","transcript_path":"","cwd":sys.argv[2],"hook_event_name":"PreToolUse",
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$c" "$P" > "$TMP/in.json"
  ( cd "$P" && CLAUDE_PROJECT_DIR="$P" bash "$GG" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$? s="${c//$'\n'/ ⏎ }"
  # a block must be THIS rule (a crashed hook also exits 2)
  if [ "$want" = 2 ] && ! grep -q 'kill theo tên' "$TMP/err"; then rc="2 (other reason)"; fi
  if [ "$rc" = "$want" ]; then echo "✔ rc $rc: ${s:0:100}"
  else echo "✖ rc $rc (want $want): ${s:0:100} — $(head -c 160 "$TMP/err" | LC_ALL=C tr '\n' ' ')"; FAILS=$((FAILS + 1)); fi
}

# blocked: kill by name
check 2 'pkill -f post-fix-gate'
check 2 'pkill gradle'
check 2 'killall python3'
check 2 'killall -9 java'
check 2 '/usr/bin/pkill -f post-fix-gate'
check 2 'sudo pkill -f post-fix-gate'
check 2 'timeout 5 pkill gradle'
check 2 'cd /tmp && pkill -f gate'
check 2 'sleep 1; killall node'
check 2 'bash -c "pkill -f post-fix-gate"'
check 2 'echo done | xargs pkill'
check 2 'find /tmp -name x -exec pkill -f gate {} +'
check 2 'kill -9 $(pgrep -f post-fix-gate)'
check 2 'for i in 1 2 3; do pgrep -f "git push" >/dev/null || break; sleep 20; done'
check 2 'pgrep --full "git push"'
check 2 'pgrep -fl gate'
check 2 'pgrep -lf gate'
# allowed: a PID the session recorded, a name lookup without the full command line, the words as data
check 0 'kill 12345'
check 0 'kill -9 12345'
check 0 'kill -0 "$pid"'
check 0 'wait $pid'
check 0 'pgrep gradle'
check 0 'echo "do not run pkill -f x"'
check 0 'grep -rn pkill hooks/'
check 0 'git commit -m "guard: block pkill and killall"'
check 0 'printf "%s\n" killall'
check 0 'ls'

if [ "$FAILS" = 0 ]; then echo "PASS: kill-by-name guard"; exit 0; fi
echo "FAIL: $FAILS case(s)"; exit 1
