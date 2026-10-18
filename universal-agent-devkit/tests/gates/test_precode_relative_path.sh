#!/usr/bin/env bash
# Issue #9 (merged #10): precode_gate asked os.path.exists() of the path AS WRITTEN, before norm(): a relative file_path was looked up
# in the hook's own cwd, not the project, so an existing file read as "new" and its blind edit passed. It must use the normalised target.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
R="$TMP/repo"; mkdir -p "$R/src" "$TMP/elsewhere"
git -C "$R" init -q . && printf 'x\n' > "$R/src/A.kt"
: > "$TMP/empty.jsonl"
run() {   # run <session> <file_path>: hook exit code; hook started in a directory that is not the project (a session per call: a "new file" pass is noted in the ledger)
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"x","new_string":"y"}}' \
    "$1" "$TMP/empty.jsonl" "$R" "$2" | ( cd "$TMP/elsewhere" && CLAUDE_PROJECT_DIR="$R" bash "$DEVKIT_DIR/hooks/precode_gate.sh" >/dev/null 2>"$TMP/err" )
}
run s1 "src/A.kt"; rc=$?
[ "$rc" = 2 ] && ok "blind edit of an existing file by a relative path: blocked" || fail "relative path to an existing file passed as new: rc $rc"
run s2 "src/New.kt"; rc=$?
[ "$rc" = 0 ] && ok "a relative path to a genuinely new file: allowed" || fail "new file blocked: rc $rc"
run s3 "$R/src/A.kt"; rc=$?
[ "$rc" = 2 ] && ok "absolute path: still blocked" || fail "absolute path: rc $rc"
[ "$FAILS" -eq 0 ] && echo "✅ test_precode_relative_path: all passed" || { echo "❌ test_precode_relative_path: $FAILS failed"; exit 1; }
