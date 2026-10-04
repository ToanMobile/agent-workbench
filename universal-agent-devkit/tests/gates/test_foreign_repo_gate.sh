#!/usr/bin/env bash
# Regression test (Goods audit 2026-09-27): hooks run for the project the session STARTED in. A PM
# session in agent-workbench edited Goods; every Stop gate checked the workbench, none ever Goods.
# hooks/foreign_repo_gate.sh: a session that Edit/Wrote files of ANOTHER repo with the DevKit
# installed is stopped ONCE, with that repo's gate command; later stops pass. Repos without the
# DevKit, and edits inside the project, are not its business.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/foreign_repo_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
mk() { mkdir -p "$TMP/$1/src" && git -C "$TMP/$1" init -q . && echo "x" > "$TMP/$1/src/A.kt"; }
mk proj; mk goods; mk plain
mkdir -p "$TMP/goods/.agents/devkit"
TR="$TMP/tr.jsonl"
edit() { python3 -c 'import json,sys
print(json.dumps({"type":"assistant","message":{"id":"m","content":[{"type":"tool_use","id":"t","name":sys.argv[1],"input":{"file_path":sys.argv[2],"old_string":"a","new_string":"b"}}]}}))' "$1" "$2" >> "$TR"; }
stop() { printf '{"session_id":"%s","hook_event_name":"Stop","transcript_path":"%s"}' "$1" "$TR" \
  | CLAUDE_PROJECT_DIR="$TMP/proj" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }

: > "$TR"; edit Edit "$TMP/proj/src/A.kt"
stop s1; [ $? = 0 ] && ok "edits inside the project: not its business" || fail "own project edit blocked"
edit Write "$TMP/plain/src/A.kt"
stop s1; [ $? = 0 ] && ok "a repo without the DevKit: not its business" || fail "plain repo blocked"
edit Edit "$TMP/goods/src/A.kt"
stop s1; rc=$?
[ "$rc" = 2 ] && grep -q "goods" "$TMP/err" && grep -q "post-fix-gate.py --run-tests --full" "$TMP/err" \
  && ok "an edit in another DevKit repo stops once, naming it and its gate command" || fail "foreign repo missed (rc=$rc): $(cat "$TMP/err")"
stop s1; [ $? = 0 ] && ok "  … then the next stop of the session passes" || fail "blocked twice for the same repo"
stop s2; [ $? = 2 ] && ok "  … a new session is told again" || fail "state leaked across sessions"
FOREIGN_REPO_GATE=0 stop s3; [ $? = 0 ] && ok "FOREIGN_REPO_GATE=0 turns it off" || fail "escape hatch ignored"
printf '{"session_id":"s4","hook_event_name":"Stop","transcript_path":"/nope"}' \
  | CLAUDE_PROJECT_DIR="$TMP/proj" bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && ok "no transcript: fail-open" || fail "missing transcript blocked"

[ "$FAILS" -eq 0 ] && echo "✅ test_foreign_repo_gate: all passed" || { echo "❌ test_foreign_repo_gate: $FAILS failed"; exit 1; }
