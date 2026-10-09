#!/usr/bin/env bash
# The PreToolUse(Bash) fast path of hooks/block-dangerous-git.sh and hooks/hardware_safety_gate.sh (2026-10-09): any quote in a
# command (grep -n "x" f, git log --format='%h') sent it to the full python parser, ~55 ms per hook per call, on most real commands.
# Quotes only matter because they can hide a word (g'i't, "gi"t), so they are dropped before the trigger-word check; a REAL
# backslash (printf '\x67it' | sh, a gi\<newline>t continuation), $, a backtick or a glob still go to the parser.
# A python3 shim on PATH logs each start of the parser.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

REAL_PY="$(command -v python3)"
mkdir -p "$TMP/bin" "$TMP/repo"
printf '#!/bin/sh\necho start >> "%s/py.log"\nexec "%s" "$@"\n' "$TMP" "$REAL_PY" > "$TMP/bin/python3"
chmod +x "$TMP/bin/python3"
git -C "$TMP/repo" init -q .

# run <hook> <command>: exit code in $RC, "1" in $PY when the parser (python3) started
run() {
  : > "$TMP/py.log"
  "$REAL_PY" -c 'import json,sys; print(json.dumps({"session_id":"s","hook_event_name":"PreToolUse","cwd":sys.argv[2],
    "tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$2" "$TMP/repo" > "$TMP/in.json"
  ( cd "$TMP/repo" && PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$TMP/repo" bash "$DEVKIT_DIR/hooks/$1" < "$TMP/in.json" >/dev/null 2>&1 )
  RC=$?
  PY=$([ -s "$TMP/py.log" ] && echo 1 || echo 0)
}

# Quoted, harmless, no trigger word: allowed WITHOUT starting python.
for c in 'grep -n "def main" src/app.py' "ls -la 'my dir'" 'echo "hello world" > notes.txt' \
         $'cat <<\'EOF\' > a.txt\nplain text\nEOF' 'npm run "lint:fix"'; do
  for h in block-dangerous-git.sh hardware_safety_gate.sh; do
    run "$h" "$c"
    [ "$RC" = 0 ] && [ "$PY" = 0 ] && ok "$h fast path: $(printf '%s' "$c" | head -1)" \
      || fail "$h: '$(printf '%s' "$c" | head -1)' rc=$RC python started=$PY (want 0 / 0)"
  done
done

# A trigger word hidden by quotes, or a real backslash / $ / glob: the full parser decides (python starts), and blocks.
for c in "g'i't push --force origin main" '"git" push -f origin main' 'gi""t reset --hard' 'G=git; $G push -f origin main'; do
  run block-dangerous-git.sh "$c"
  [ "$PY" = 1 ] && [ "$RC" = 2 ] && ok "block-dangerous-git: parser decides and blocks: $c" \
    || fail "block-dangerous-git: '$c' rc=$RC python started=$PY (want 2 / 1)"
done
# Encoded words reach the parser (what it then decides is its own documented limit, not the fast path's)
for c in "printf '\\x67it push -f origin main' | sh" $'gi\\\nt push -f origin main'; do
  run block-dangerous-git.sh "$c"
  [ "$PY" = 1 ] && ok "block-dangerous-git: a real backslash goes to the parser: $(printf '%s' "$c" | head -1)" \
    || fail "block-dangerous-git: '$(printf '%s' "$c" | head -1)' skipped the parser"
done
for c in "a'd'b -s X reboot" '"adb" reboot' "r'm' -rf ../" "printf '\\x61db reboot' | sh"; do
  run hardware_safety_gate.sh "$c"
  [ "$PY" = 1 ] && ok "hardware_safety_gate: parser decides: $c" || fail "hardware_safety_gate: '$c' skipped the parser (rc=$RC)"
done

[ "$FAILS" -eq 0 ] && echo "✅ test_hook_fast_path_quotes: all passed" || { echo "❌ test_hook_fast_path_quotes: $FAILS failed"; exit 1; }
