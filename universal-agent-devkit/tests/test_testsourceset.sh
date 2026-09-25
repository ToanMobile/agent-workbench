#!/usr/bin/env bash
# Regression test: hooks/testsourceset_gate.sh compiles each touched module's UNIT-TEST
# source set with the task that module really has. AGP creates unit-test variants only
# for `testBuildType`: a module with `testBuildType = "release"` (OfficeReader's :app) has
# compileReleaseUnitTestKotlin and no compileDebugUnitTestKotlin, and used to be dropped
# as "lacks the task" — its broken src/test passed the gate. The task is derived the way
# scripts/matrix_detect.py reads testBuildType (comment lines ignored). Fake ./gradlew
# only: it records its arguments and answers like Gradle; no real build runs.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DEVKIT_DIR/hooks/testsourceset_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

N=0
# new_repo → sets R to a fresh git work tree with a fake ./gradlew. The fake knows the
# tasks listed in .tasks; a task in .broken fails with a Kotlin compile error; any other
# task is "not found in project", worded as Gradle words it.
new_repo() {
  N=$((N + 1))
  R="$TMP/r$N"
  mkdir -p "$R"
  git -C "$R" init -q
  cat > "$R/gradlew" <<'SH'
#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$*" >> "$here/.calls"
for a in "$@"; do
  case "$a" in -*) continue ;; esac
  grep -qxF -- "$a" "$here/.tasks" 2>/dev/null || {
    echo "Cannot locate tasks that match '$a' as task '${a##*:}' not found in project '${a%:*}'."
    exit 1; }
done
for a in "$@"; do
  if grep -qxF -- "$a" "$here/.broken" 2>/dev/null; then
    echo "e: file://$here/app/src/test/FooTest.kt:3:5 No value passed for parameter 'x'."
    echo "> Task $a FAILED"
    exit 1
  fi
done
exit 0
SH
  chmod +x "$R/gradlew"
  : > "$R/.tasks"; : > "$R/.broken"
  # the fake's bookkeeping is ignored, like a real build's outputs (not part of the tree)
  printf '.calls\n.tasks\n.broken\n' >> "$R/.git/info/exclude"
}

# module <dir> <build.gradle.kts body> — a module with one uncommitted Kotlin file.
module() {
  mkdir -p "$R/$1/src/main/kotlin"
  printf '%s\n' "$2" > "$R/$1/build.gradle.kts"
  printf 'class Foo\n' > "$R/$1/src/main/kotlin/Foo.kt"
}

gate() {
  ERR="$(printf '{"session_id":"tss-%s"}' "$N" | CLAUDE_PROJECT_DIR="$R" bash "$GATE" 2>&1 >/dev/null)"
  RC=$?
}

RELEASE_APP='plugins { id("com.android.application") }
android {
    // testBuildType = "debug"  (was, before AGP 9)
    testBuildType = "release"
}'

# ── 1. testBuildType = "release": the release unit-test task is compiled ──
new_repo
module app "$RELEASE_APP"
echo ":app:compileReleaseUnitTestKotlin" > "$R/.tasks"
gate
if [ "$RC" = 0 ] && grep -qF ":app:compileReleaseUnitTestKotlin" "$R/.calls"; then
  ok "testBuildType=release → :app:compileReleaseUnitTestKotlin"
else
  fail "testBuildType=release → want :app:compileReleaseUnitTestKotlin, exit 0; got exit $RC, calls: $(tr '\n' ' ' < "$R/.calls" 2>/dev/null)"
fi

# ── 2. …and a broken release test source set BLOCKS instead of being skipped ──
new_repo
module app "$RELEASE_APP"
echo ":app:compileReleaseUnitTestKotlin" > "$R/.tasks"
echo ":app:compileReleaseUnitTestKotlin" > "$R/.broken"
gate
if [ "$RC" = 2 ] && printf '%s' "$ERR" | grep -qF "compileReleaseUnitTestKotlin"; then
  ok "broken src/test of a release-testBuildType module blocks (exit 2)"
else
  fail "broken release src/test: want exit 2 naming compileReleaseUnitTestKotlin; got exit $RC: $(printf '%s' "$ERR" | head -3 | tr '\n' ' ')"
fi

# ── 3. only `> Task …:compileReleaseUnitTestKotlin FAILED` (no e: line) is still a compile failure
new_repo
module app "$RELEASE_APP"
echo ":app:compileReleaseUnitTestKotlin" > "$R/.tasks"
cat > "$R/gradlew" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$(cd "$(dirname "$0")" && pwd)/.calls"
echo "> Task :app:compileReleaseUnitTestKotlin FAILED"
exit 1
SH
chmod +x "$R/gradlew"
gate
[ "$RC" = 2 ] && ok "'…compileReleaseUnitTestKotlin FAILED' is read as a compile failure" \
  || fail "compileReleaseUnitTestKotlin FAILED read as infra (exit $RC)"

# ── 4. no testBuildType (or only in a comment) → Debug, as before ──────────
new_repo
module lib 'plugins { id("com.android.library") }
// testBuildType = "release"'
echo ":lib:compileDebugUnitTestKotlin" > "$R/.tasks"
gate
if [ "$RC" = 0 ] && grep -qF ":lib:compileDebugUnitTestKotlin" "$R/.calls" && ! grep -qF "Release" "$R/.calls"; then
  ok "no testBuildType (commented one ignored) → :lib:compileDebugUnitTestKotlin"
else
  fail "debug module: got exit $RC, calls: $(tr '\n' ' ' < "$R/.calls" 2>/dev/null)"
fi

# ── 5. groovy `testBuildType 'staging'` + a debug module, in one build ─────
new_repo
mkdir -p "$R/core/src/main/java"
printf "android {\n    testBuildType 'staging'\n}\n" > "$R/core/build.gradle"
printf 'class Bar {}\n' > "$R/core/src/main/java/Bar.java"
module lib 'plugins { id("com.android.library") }'
printf ':core:compileStagingUnitTestKotlin\n:lib:compileDebugUnitTestKotlin\n' > "$R/.tasks"
gate
if [ "$RC" = 0 ] && grep -qF ":core:compileStagingUnitTestKotlin" "$R/.calls" \
   && grep -qF ":lib:compileDebugUnitTestKotlin" "$R/.calls"; then
  ok "per-module: groovy testBuildType 'staging' and a debug module side by side"
else
  fail "mixed modules: got exit $RC, calls: $(tr '\n' ' ' < "$R/.calls" 2>/dev/null)"
fi

# ── 6. a module that really lacks its task is still skipped, not blamed ────
new_repo
module app "$RELEASE_APP"
module lib 'plugins { id("com.android.library") }'
echo ":lib:compileDebugUnitTestKotlin" > "$R/.tasks"
gate
if [ "$RC" = 0 ] && [ "$(wc -l < "$R/.calls" | tr -d ' ')" = 2 ] && tail -1 "$R/.calls" | grep -qxF ":lib:compileDebugUnitTestKotlin --quiet"; then
  ok "a module without its unit-test task is dropped and the rest re-run"
else
  fail "missing-task retry: got exit $RC, calls: $(tr '\n' '|' < "$R/.calls" 2>/dev/null)"
fi

# ── Non-Claude agent (Grok) / no usable transcript ────────────────────────────
# Grok (2026-09-25, OfficeReader) runs the Claude Stop hooks with its own transcript
# (updates.jsonl, {"method","params"} lines): scoping fell back to repo-wide and every
# stop compiled every test source set. The repo-wide result is re-used for an unchanged
# tree in a session, Grok's session-end Stop compiles nothing, and in degraded mode a
# session holds at most TESTSOURCESET_GATE_MAX_SESSION_BLOCKS (default 3) blocks.
printf '%s\n' '{"timestamp":1790240706,"method":"_x.ai/session/update","params":{"sessionId":"g","update":{"sessionUpdate":"hook_execution"}}}' > "$TMP/updates.jsonl"
gstop() { # <session> [reason] — a Grok-shaped Stop
  OUT="$(printf '{"hookEventName":"stop","hook_event_name":"Stop","sessionId":"%s","session_id":"%s","transcript_path":"%s","reason":"%s"}' \
      "$1" "$1" "$TMP/updates.jsonl" "${2:-end_turn}" \
    | GROK_HOOK_EVENT=stop CLAUDE_PROJECT_DIR="$R" bash "$GATE" 2>"$TMP/ts_err")"
  RC=$?; ERR="$(cat "$TMP/ts_err")"
}
calls() { grep -c . "$R/.calls" 2>/dev/null | tr -d ' ' || echo 0; }

# ── 7. Grok's session-end Stop compiles nothing ──
new_repo
module lib 'plugins { id("com.android.library") }'
echo ":lib:compileDebugUnitTestKotlin" > "$R/.tasks"
gstop g7 channel_closed
[ "$RC" = 0 ] && [ ! -s "$R/.calls" ] && ok "Grok session-end Stop (reason channel_closed): no compile" \
  || fail "session-end Stop compiled (exit $RC, calls: $(tr '\n' ' ' < "$R/.calls" 2>/dev/null))"

# ── 8. same tree, same Grok session: one compile, the PASS is re-used ──
gstop g8; rc1=$RC; gstop g8; rc2=$RC
[ "$rc1" = 0 ] && [ "$rc2" = 0 ] && [ "$(calls)" = 1 ] && grep -q "reused" "$R/.claude/audit-gate/testsourceset_gate.log" \
  && ok "Grok, unchanged tree: repo-wide compile runs once per session, then re-used" \
  || fail "no reuse (exits $rc1/$rc2, calls=$(calls))"
grep -q "agent=grok" "$R/.claude/audit-gate/testsourceset_gate.log" \
  && ok "the SCOPE log line names the agent and why the scope is repo-wide" || fail "agent not logged: $(grep SCOPE "$R/.claude/audit-gate/testsourceset_gate.log" | tail -1)"
echo 'class Foo2' > "$R/lib/src/main/kotlin/Foo.kt"
gstop g8
[ "$RC" = 0 ] && [ "$(calls)" = 2 ] && ok "Grok, changed tree: compiled again" || fail "changed tree not recompiled (calls=$(calls))"

# ── 9. broken src/test, same tree: blocked without recompiling, released with a message ──
new_repo
module lib 'plugins { id("com.android.library") }'
echo ":lib:compileDebugUnitTestKotlin" > "$R/.tasks"; echo ":lib:compileDebugUnitTestKotlin" > "$R/.broken"
gstop g9; r1=$RC; e1="$ERR"; gstop g9; r2=$RC; e2="$ERR"; gstop g9; r3=$RC
[ "$r1" = 2 ] && [ "$r2" = 2 ] && [ "$(calls)" = 1 ] && printf '%s' "$e2" | grep -q "compileDebugUnitTestKotlin" \
  && ok "Grok, broken src/test, unchanged tree: blocked again from the cached result (one compile)" \
  || fail "cached block (exits $r1/$r2, calls=$(calls), err2: $(printf '%s' "$e2" | head -2 | tr '\n' ' '))"
[ "$r3" = 0 ] && printf '%s' "$OUT" | grep -q systemMessage \
  && ok "…and the release after MAX_ATTEMPTS says so to the user (systemMessage)" || fail "silent release (exit $r3, out: $OUT)"

# ── 10. a new tree every stop (Grok edits every turn): total cap per session ──
new_repo
module lib 'plugins { id("com.android.library") }'
echo ":lib:compileDebugUnitTestKotlin" > "$R/.tasks"; echo ":lib:compileDebugUnitTestKotlin" > "$R/.broken"
RCS=""
for v in 1 2 3 4 5 6; do echo "class Foo$v" > "$R/lib/src/main/kotlin/Foo.kt"; gstop g10; RCS="$RCS$RC"; done
[ "$RCS" = 220200 ] && printf '%s' "$OUT" | grep -q systemMessage && printf '%s' "$OUT" | grep -q "g10" \
  && ok "Grok, new tree each stop: 3 blocks in the session, then released with a systemMessage naming it" \
  || fail "session cap (exits $RCS, out: $OUT)"

# ── 11. a Claude session with a real transcript is not capped per session ──
new_repo
module lib 'plugins { id("com.android.library") }'
echo ":lib:compileDebugUnitTestKotlin" > "$R/.tasks"; echo ":lib:compileDebugUnitTestKotlin" > "$R/.broken"
python3 - "$TMP/claude.jsonl" "$R/lib/src/main/kotlin/Foo.kt" <<'PY'
import json, sys
use = {"type": "tool_use", "id": "t1", "name": "Write", "input": {"file_path": sys.argv[2], "content": "class Foo"}}
open(sys.argv[1], "w").write(json.dumps({"type": "assistant", "message": {"content": [use]}}) + "\n")
PY
RCS=""
for v in 1 2 3 4 5 6; do echo "class Foo$v" > "$R/lib/src/main/kotlin/Foo.kt"
  printf '{"session_id":"c11","transcript_path":"%s"}' "$TMP/claude.jsonl" | CLAUDE_PROJECT_DIR="$R" bash "$GATE" >/dev/null 2>&1; RCS="$RCS$?"; done
[ "$RCS" = 220220 ] && ok "Claude session (scoped by its transcript): per-session attempts guard only, no total cap" \
  || fail "Claude session capped (exits $RCS)"

if [ "$FAILS" -ne 0 ]; then echo "test_testsourceset: $FAILS FAILED"; exit 1; fi
echo "test_testsourceset: all checks passed"
