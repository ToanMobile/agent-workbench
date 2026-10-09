#!/usr/bin/env bash
# hooks/churn_guard.sh started python on every Edit/Write (~30 ms on macOS, more with the transcript read) although it can warn only
# at the Nth landed edit of one file NAME since the last evidence call (N = CHURN_GUARD_MAX, 3 by default; plan
# docs/plans/audit-2026-10-09-followup.md step 3 item 4). Every landed edit is a tool_use line of the transcript that names the file,
# so a transcript with fewer than N lines naming it cannot reach N: bash now counts those lines with `grep -c -F` (8 ms on a 27 MB
# transcript) and exits 0 before python. Decision-neutral: the only difference is the "pass" line python logged.
#   1. fewer than N lines naming the file: rc 0 and python NOT started (a python3 shim on PATH logs each start);
#   2. N or more lines (also with evidence in between): python starts and decides as before (warn at the 3rd, pass after evidence);
#   3. a path spelled with a JSON escape, a non-numeric CHURN_GUARD_MAX, no transcript: python starts.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${CG_HOOK:-$DEVKIT_DIR/hooks/churn_guard.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
REAL_PY="$(command -v python3)" || { echo "skip: python3 missing"; exit 0; }

mkdir -p "$TMP/bin" "$TMP/repo"
printf '#!/bin/sh\necho start >> "%s/py.log"\nexec "%s" "$@"\n' "$TMP" "$REAL_PY" > "$TMP/bin/python3"
chmod +x "$TMP/bin/python3"
R="$TMP/repo"
git -C "$R" init -q . && git -C "$R" config user.email t@t && git -C "$R" config user.name t && git -C "$R" config commit.gpgsign false

# transcript <file> <spec…>: one assistant line per spec — e<name> = an Edit of /p/<name>, b = a Bash call (evidence), r<name> = a Read
transcript() {
  local f="$1"; shift; : > "$f"; local i=0 s
  for s in "$@"; do
    i=$((i + 1))
    case "$s" in
      e*) printf '{"type":"assistant","message":{"id":"m%s","content":[{"type":"tool_use","id":"t%s","name":"Edit","input":{"file_path":"/p/%s","old_string":"a","new_string":"b"}}]}}\n' "$i" "$i" "${s#e}" >> "$f" ;;
      r*) printf '{"type":"assistant","message":{"id":"m%s","content":[{"type":"tool_use","id":"t%s","name":"Read","input":{"file_path":"/p/%s"}}]}}\n' "$i" "$i" "${s#r}" >> "$f" ;;
      b)  printf '{"type":"assistant","message":{"id":"m%s","content":[{"type":"tool_use","id":"t%s","name":"Bash","input":{"command":"ls"}}]}}\n' "$i" "$i" >> "$f" ;;
    esac
  done
}
# run <transcript> <file_path as it goes in the JSON> [VAR=val…]: rc in $RC, "1" in $PY when python started
run() {
  local tr="$1" fp="$2"; shift 2
  : > "$TMP/py.log"
  printf '{"session_id":"s","transcript_path":"%s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' \
    "$tr" "$R" "$fp" > "$TMP/in.json"
  ( cd "$R" && env PATH="$TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$R" "$@" bash "$HOOK" < "$TMP/in.json" > /dev/null 2> "$TMP/err" )
  RC=$?
  PY=$([ -s "$TMP/py.log" ] && echo 1 || echo 0)
}
T="$TMP/t.jsonl"

# 1. too few earlier lines naming the file: nothing can warn
transcript "$T"
run "$T" /p/Foo.kt
[ "$RC" = 0 ] && [ "$PY" = 0 ] && ok "empty transcript: rc 0, python not started" || fail "empty transcript: rc=$RC python=$PY (want 0/0)"
transcript "$T" eFoo.kt b
rm -f "$R/.claude/audit-gate/churn_guard.log"
run "$T" /p/Foo.kt
[ "$RC" = 0 ] && [ "$PY" = 0 ] && ok "one earlier edit of the file: rc 0, python not started" || fail "one earlier edit: rc=$RC python=$PY (want 0/0)"
grep -q "Foo.kt: 1/3 lines naming it — pass (fast path)" "$R/.claude/audit-gate/churn_guard.log" 2>/dev/null && ok "  … and the call still leaves its 'pass' line in the log" || fail "no pass line in the log: $(cat "$R/.claude/audit-gate/churn_guard.log" 2>/dev/null)"
transcript "$T" eBar.kt eBar.kt eBar.kt rFoo.kt
run "$T" /p/Foo.kt
[ "$RC" = 0 ] && [ "$PY" = 0 ] && ok "other files edited, one Read of this one: python not started" || fail "other files: rc=$RC python=$PY (want 0/0)"
run "$T" "/p/dir with space/Foo.kt"
[ "$RC" = 0 ] && ok "a path with a space is judged by its base name too (rc 0)" || fail "space path rc=$RC"

# 2. enough lines: python decides, exactly as before. It counts the LANDED edits of the file name since the last evidence call in the
#    transcript (the trigger itself is in it by then) and warns at exactly N; the bash count is never above that, so N-1 lines cannot warn.
transcript "$T" eFoo.kt eFoo.kt
run "$T" /p/Foo.kt
[ "$RC" = 0 ] && [ "$PY" = 0 ] && ok "two lines naming the file (below the 3rd): rc 0, python not started" || fail "two lines: rc=$RC python=$PY (want 0/0)"
transcript "$T" eFoo.kt eFoo.kt eFoo.kt
run "$T" /p/Foo.kt
[ "$RC" = 2 ] && [ "$PY" = 1 ] && grep -q "CHURN-GUARD" "$TMP/err" && ok "three edits, no evidence: the 3rd still warns (rc 2, python started)" || fail "3rd edit: rc=$RC python=$PY (want 2/1)"
transcript "$T" eFoo.kt eFoo.kt eFoo.kt b
run "$T" /p/Foo.kt
[ "$RC" = 0 ] && [ "$PY" = 1 ] && ok "three edits, then evidence: python starts and passes (rc 0)" || fail "evidence after: rc=$RC python=$PY (want 0/1)"
transcript "$T" eFoo.kt eFoo.kt eFoo.kt eFoo.kt
run "$T" /p/Foo.kt
[ "$RC" = 0 ] && [ "$PY" = 1 ] && ok "a 4th edit is past the threshold: python starts, already warned (rc 0)" || fail "4th edit: rc=$RC python=$PY (want 0/1)"
transcript "$T" eFoo.kt
run "$T" /p/Foo.kt CHURN_GUARD_MAX=2
[ "$RC" = 0 ] && [ "$PY" = 0 ] && ok "CHURN_GUARD_MAX=2, one line: below the 2nd, python not started" || fail "MAX=2, one line: rc=$RC python=$PY (want 0/0)"
transcript "$T" eFoo.kt eFoo.kt
run "$T" /p/Foo.kt CHURN_GUARD_MAX=2
[ "$RC" = 2 ] && [ "$PY" = 1 ] && ok "CHURN_GUARD_MAX=2, two edits: the 2nd warns (rc 2, python started)" || fail "MAX=2: rc=$RC python=$PY (want 2/1)"
transcript "$T"
run "$T" /p/Foo.kt CHURN_GUARD_MAX=2
[ "$RC" = 0 ] && [ "$PY" = 0 ] && ok "CHURN_GUARD_MAX=2 with an empty transcript: python not started" || fail "MAX=2 empty: rc=$RC python=$PY (want 0/0)"

# 3. cases the bash count does not cover: python starts
transcript "$T"
run "$T" "/p/Fo\\u006f.kt"
[ "$PY" = 1 ] && ok "a JSON escape in the path: python starts" || fail "escaped path: python=$PY (want 1)"
run "$T" /p/Foo.kt CHURN_GUARD_MAX=abc
[ "$PY" = 1 ] && ok "a non-numeric CHURN_GUARD_MAX: python starts" || fail "MAX=abc: python=$PY (want 1)"
run "$TMP/none.jsonl" /p/Foo.kt
[ "$RC" = 0 ] && [ "$PY" = 1 ] && ok "no transcript file: python starts (and fails open)" || fail "no transcript: rc=$RC python=$PY (want 0/1)"

[ "$FAILS" -eq 0 ] && echo "✅ test_churn_guard_fast_path: all passed" || { echo "❌ test_churn_guard_fast_path: $FAILS failed"; exit 1; }
