#!/usr/bin/env bash
# A camelCase hook payload ({"toolName":"Bash","toolInput":{"command":…}}, the envelope Grok uses, hooks/devkit_harness.py)
# passed the guards with exit 0 (audit 2026-10-09, finding C6): they read only tool_name / tool_input, found no command and
# allowed it — `git push -f origin main` through block-dangerous-git, `rm -rf src` through hardware_safety_gate, a Write into
# the main checkout from a worktree session through worktree_guard, a blind Edit through precode_gate. Each guard now reads
# toolName / toolInput as well (block-dangerous-git also `input`, like hardware_safety_gate), and read_ledger records a
# camelCase Read so the edit after it is not blocked.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS="${CP_HOOKS:-$DEVKIT_DIR/hooks}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

R="$TMP/repo"
mkdir -p "$R/src"
git -C "$R" init -q . && git -C "$R" config user.email t@t && git -C "$R" config user.name t && git -C "$R" config commit.gpgsign false
printf 'class A\n' > "$R/src/A.kt" && git -C "$R" add -A && git -C "$R" commit -qm init
: > "$TMP/empty.jsonl"
M="$TMP/main"
mkdir -p "$M/src" && printf 'x\n' > "$M/src/a.kt"
git -C "$M" init -q . && git -C "$M" config user.email t@t && git -C "$M" config user.name t && git -C "$M" config commit.gpgsign false
git -C "$M" add -A && git -C "$M" commit -qm init && git -C "$M" worktree add -q --detach "$TMP/wt"
W="$TMP/wt"
python3 -I -c 'import json,sys; open(sys.argv[1],"w").write(json.dumps({"type":"user","cwd":sys.argv[2],"message":{"role":"user","content":"go"}})+"\n")' \
  "$TMP/wt.jsonl" "$W"

# check <want rc> <hook> <project dir> <json payload> <label>
check() {
  local want="$1" h="$2" proj="$3" p="$4" label="$5"
  printf '%s' "$p" > "$TMP/in.json"
  ( cd "$proj" && CLAUDE_PROJECT_DIR="$proj" bash "$HOOKS/$h" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  local rc=$?
  [ "$rc" = "$want" ] && ok "rc $rc: $h — $label" || fail "rc $rc (want $want): $h — $label $(head -c 160 "$TMP/err" | tr '\n' ' ')"
}
grok() {   # grok <cwd> <toolName> <toolInput json> [transcript]: Grok's envelope (camelCase + the snake aliases it sends)
  printf '{"hookEventName":"PreToolUse","hook_event_name":"PreToolUse","sessionId":"g1","session_id":"g1","transcript_path":"%s","workspaceRoot":"%s","cwd":"%s","toolName":"%s","toolInput":%s}' \
    "${4:-$TMP/empty.jsonl}" "$1" "$1" "$2" "$3"
}

check 2 block-dangerous-git.sh "$R" "$(grok "$R" Bash '{"command":"git push -f origin main"}')" "toolInput git push -f"
check 2 block-dangerous-git.sh "$R" '{"tool_name":"Bash","input":{"command":"git reset --hard"}}' "input git reset --hard"
check 0 block-dangerous-git.sh "$R" "$(grok "$R" Bash '{"command":"git status"}')" "toolInput git status"
check 2 hardware_safety_gate.sh "$R" "$(grok "$R" Bash '{"command":"rm -rf src"}')" "toolInput rm -rf src"
check 0 hardware_safety_gate.sh "$R" "$(grok "$R" Bash '{"command":"ls -la"}')" "toolInput ls -la"
# bash 3.2 (macOS /bin/bash) splits a word like "$(cmd "{\"a\":\"b\"}")" at its escaped quotes, so the payload reached `check` mangled
# and the hook ran on garbage (macOS 2026-10-09: rc 0 for these two, want 2). A payload with \" inside is built in an assignment,
# which bash 3.2 parses right, and then passed as "$var".
P_WRITE="$(grok "$W" Write "{\"file_path\":\"$M/src/a.kt\",\"content\":\"y\"}" "$TMP/wt.jsonl")"
P_EDIT="$(grok "$R" Edit "{\"file_path\":\"$R/src/A.kt\",\"old_string\":\"A\",\"new_string\":\"B\"}")"
P_READ="$(grok "$R" Read "{\"file_path\":\"$R/src/A.kt\"}" | sed 's/"PreToolUse"/"PostToolUse"/g')"
check 2 worktree_guard.sh "$W" "$P_WRITE" "toolInput Write into the main checkout from a worktree session"
check 2 precode_gate.sh "$R" "$P_EDIT" "toolInput Edit of a file never read"
check 0 read_ledger.sh "$R" "$P_READ" "toolInput Read recorded"
check 0 precode_gate.sh "$R" "$P_EDIT" "toolInput Edit after the camelCase Read"

[ "$FAILS" -eq 0 ] && echo "✅ test_hook_camelcase_payload: all passed" || { echo "❌ test_hook_camelcase_payload: $FAILS failed"; exit 1; }
