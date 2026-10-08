#!/usr/bin/env bash
# Regression test: hooks/regression_gate.sh must not run the whole gate again on every Stop while the
# only thing left is "an existing test was edited, a person has to review the diff".
# Measured 2026-10-08 on OfficeReader (10 sessions in one checkout): 70 of 71 Stop-hook gate runs in 17 h
# ended exit 2 with that reminder, 58 of them on a content that had not changed for 30 minutes, each run
# 31-37 s (suites ~10 s, static checks the rest) and each one printing the same reminder.
# The first Stop of a change still blocks and still runs the gate; the repeats OF THE SAME SESSION print the
# stored reminder without running it for REGRESSION_GATE_TOUCHED_RECHECK_S seconds (default 300, 0 = always
# run). After that the gate runs again, so the user's answer ("Duyệt") still clears the reminder. Never reused:
# by another session (the gate result depends on the session and its transcript), for a different content
# (also an edit inside an untracked file or a new commit), or when the reminder came with a BUSY suite.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/regression_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

X="$TMP/repo"; mkdir -p "$X/src/test" "$X/.agents" && cd "$X" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt && echo "assert(true)" > src/test/CoreTest.kt
RUNS="$TMP/runs"; : > "$RUNS"
cat > .agents/regression_matrix.active.json <<JSON
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt","src/test/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-X","name":"core","command":"printf x >> $RUNS"}]}]}
JSON
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt && echo "// weakened" > src/test/CoreTest.kt
runs() { wc -c < "$RUNS" | tr -d ' '; }

# This session edited the existing test (an Edit tool_use with no timestamp = this session's write).
python3 - "$X" "$TMP/s.jsonl" <<'PY'
import json, sys, time
repo, tp = sys.argv[1], sys.argv[2]
open(tp, "w").write("".join(json.dumps(r) + "\n" for r in [
    {"type": "user", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - 600)),
     "message": {"role": "user", "content": "fix it"}},
    {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "e1", "name": "Edit",
        "input": {"file_path": repo + "/src/test/CoreTest.kt", "old_string": "a", "new_string": "b"}}]}}]))
PY
stop() { printf '{"session_id":"s-y2","hook_event_name":"Stop","transcript_path":"%s"}' "$TMP/s.jsonl" \
  | env "$@" CLAUDE_PROJECT_DIR="$X" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
STATE="$X/.claude/audit-gate/regression_gate.state.json"
LOG="$X/.claude/audit-gate/regression_gate.log"
age_reminder() { python3 -c 'import json,sys,time
p = sys.argv[1]; d = json.load(open(p)); d["touched"]["s-y2"]["at"] = time.time() - float(sys.argv[2]); json.dump(d, open(p, "w"))' "$STATE" "$1"; }

# 1. first Stop of the change: the gate runs and blocks (unchanged behaviour)
stop X=1; rc=$?
[ "$rc" = 2 ] && grep -q "src/test/CoreTest.kt" "$TMP/err" && [ "$(runs)" = 1 ] \
  && ok "first stop: the gate ran once and blocked, naming the edited test" \
  || fail "first stop: rc=$rc runs=$(runs) err='$(head -3 "$TMP/err")'"

# 2. same content, right after: the stored reminder, no gate run
stop X=1; rc=$?
[ "$rc" = 0 ] && grep -q "src/test/CoreTest.kt" "$TMP/out" && grep -q "Vẫn chờ người duyệt" "$TMP/out" \
  && ok "repeat stop: allowed with the reminder naming the file" \
  || fail "repeat stop: rc=$rc out='$(head -c 300 "$TMP/out")' err='$(head -2 "$TMP/err")'"
[ "$(runs)" = 1 ] && grep -q "reused, no run" "$LOG" \
  && ok "repeat stop: the gate did NOT run again (suite run count still 1), logged as reused" \
  || fail "repeat stop re-ran the gate: runs=$(runs) log=$(tail -2 "$LOG")"
stop X=1; [ "$(runs)" = 1 ] && ok "a third stop in the window: still no run" || fail "third stop ran the gate (runs=$(runs))"

# 2b. a hand-written or corrupt timestamp never crashes the hook: it just means "run the gate"
python3 -c 'import json,sys
p = sys.argv[1]; d = json.load(open(p)); d["touched"]["s-y2"]["at"] = 10**400; json.dump(d, open(p, "w"))' "$STATE"
before=$(runs); stop X=1; rc=$?
[ "$rc" = 0 ] && [ "$(runs)" -gt "$before" ] && ! grep -q Traceback "$TMP/err" \
  && ok "a huge touched_at (OverflowError in the age): no crash, the gate runs" \
  || fail "huge touched_at: rc=$rc runs $before -> $(runs) err='$(head -3 "$TMP/err")'"

python3 -c 'import json,sys,time
p = sys.argv[1]; d = json.load(open(p)); d["touched"]["s-y2"]["at"] = time.time(); d["touched"]["s-y2"]["lines"] = "not a list"; json.dump(d, open(p, "w"))' "$STATE"
before=$(runs); stop X=1; rc=$?
[ "$rc" = 0 ] && [ "$(runs)" -gt "$before" ] && ! grep -q Traceback "$TMP/err" \
  && ok "a stored reminder whose lines are not a list is not reused: the gate runs" \
  || fail "wrong-typed lines: rc=$rc runs $before -> $(runs) err='$(head -3 "$TMP/err")'"

# 2c. another session never gets this session's reminder: its first Stop runs the gate itself
before=$(runs)
printf '{"session_id":"s-b","hook_event_name":"Stop","transcript_path":"%s"}' "$TMP/s.jsonl" \
  | CLAUDE_PROJECT_DIR="$X" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; rcb=$?
[ "$(runs)" -gt "$before" ] && ok "session B's first stop ran the gate itself (it did not take A's stored reminder)" \
  || fail "session B's first stop reused session A's reminder (runs stayed $before)"
before=$(runs)
printf '{"session_id":"s-b","hook_event_name":"Stop","transcript_path":"%s"}' "$TMP/s.jsonl" \
  | CLAUDE_PROJECT_DIR="$X" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; rcb2=$?
grep -q "reused, no run" "$LOG" && ok "session B repeats its own reminder without a run" || fail "B repeat ran (log: $(tail -2 "$LOG"))"
[ "$(runs)" = "$before" ] || fail "session B repeat ran the gate (runs $before -> $(runs))"
python3 -c 'import json,sys
d = json.load(open(sys.argv[1])); sys.exit(0 if "s-b" in d.get("touched", {}) and "s-y2" in d.get("touched", {}) else 1)' "$STATE" \
  && ok "the reminders are stored per session (s-y2 and s-b side by side), B's first stop did not reuse A's" \
  || fail "reminders not stored per session: $(python3 -c 'import json,sys; print(list(json.load(open(sys.argv[1])).get("touched", {})))' "$STATE")"

# 3. REGRESSION_GATE_TOUCHED_RECHECK_S=0 turns the reuse off
before=$(runs); stop REGRESSION_GATE_TOUCHED_RECHECK_S=0; rc=$?
[ "$rc" = 0 ] && [ "$(runs)" -gt "$before" ] && grep -q "src/test/CoreTest.kt" "$TMP/out" \
  && ok "REGRESSION_GATE_TOUCHED_RECHECK_S=0: the gate runs on every stop again, reminder still printed" \
  || fail "recheck=0: rc=$rc runs=$(runs) out='$(head -c 200 "$TMP/out")'"

# 4. after the window the gate runs again
age_reminder 400
before=$(runs); stop X=1; rc=$?
[ "$rc" = 0 ] && [ "$(runs)" -gt "$before" ] && ok "reminder older than the window: the gate runs again" || fail "aged reminder: rc=$rc runs $before -> $(runs)"
before=$(runs); stop X=1; [ "$(runs)" = "$before" ] && ok "and the window restarts from that run" || fail "window did not restart (runs $before -> $(runs))"

# 5. the user's answer still clears the reminder once the window is over
python3 - "$X" "$TMP/s.jsonl" <<'PY'
import json, sys, time
repo, tp = sys.argv[1], sys.argv[2]
q = "Duyệt diff test src/test/CoreTest.kt?"
iso = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() + 5))
rec = {"type": "user", "sessionId": "s-y2", "timestamp": iso,
       "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "q1", "content": "answered"}]},
       "toolUseResult": {"questions": [{"question": q, "header": "Test", "options": [
           {"label": "Duyệt", "description": "giữ diff"}, {"label": "Không", "description": "đổi hướng"}]}],
           "answers": {q: "Duyệt"}}}
open(tp, "a").write(json.dumps(rec) + "\n")
PY
age_reminder 400
sleep 6
stop X=1; rc=$?
if [ "$rc" = 0 ] && ! grep -q "Vẫn chờ người duyệt" "$TMP/out"; then
  ok "the user's approval clears the reminder once the window is over (the gate ran and passed)"
else
  fail "approval did not clear the reminder: rc=$rc runs=$(runs) out='$(head -c 300 "$TMP/out")' err='$(head -2 "$TMP/err")'"
fi

# 6. a different content never reuses the reminder
git checkout -q -- src/test/CoreTest.kt && echo "// weakened again" > src/test/CoreTest.kt
python3 - "$X" "$TMP/s.jsonl" <<'PY'
import json, sys, time
repo, tp = sys.argv[1], sys.argv[2]
open(tp, "w").write("".join(json.dumps(r) + "\n" for r in [
    {"type": "user", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - 600)),
     "message": {"role": "user", "content": "fix it"}},
    {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "e2", "name": "Edit",
        "input": {"file_path": repo + "/src/test/CoreTest.kt", "old_string": "a", "new_string": "b"}}]}}]))
PY
before=$(runs)
stop X=1; rc=$?
[ "$rc" = 2 ] && [ "$(runs)" -gt "$before" ] && ok "a new content with the test edit pending: blocked again and the gate ran" \
  || fail "new content: rc=$rc runs=$(runs) (before $before)"
stop X=1; rc=$?; before=$(runs)         # first repeat of the new content: its run was the blocked stop above
stop X=1
[ "$rc" = 0 ] && [ "$(runs)" = "$before" ] && ok "the repeat of the new content is again a reminder without a run" \
  || fail "window not honoured after the new content (rc=$rc runs $before -> $(runs))"
echo "scratch v1" > untracked.txt
stop X=1            # a new untracked file changes the status: a new content
before=$(runs)
echo "scratch v2 with other bytes" > untracked.txt      # same git status line, other bytes
stop X=1
[ "$(runs)" -gt "$before" ] && ok "an edit inside an untracked file (same status, other bytes) is a new content: the gate runs" \
  || fail "untracked edit reused the reminder (runs $before -> $(runs))"

# 7. an unrelated commit leaves status and `git diff HEAD` of the dirty files alone but changes the commit range:
#    the reminder of the old range must not be reused
stop X=1; before=$(runs)
echo "other" > other.txt && git add other.txt && git commit -qm "unrelated" -- other.txt
stop X=1
[ "$(runs)" -gt "$before" ] && ok "a new commit (same dirty files): the gate runs, the old reminder is not reused" \
  || fail "reminder reused across a new commit (runs $before -> $(runs))"

# 8. a reminder that came with a BUSY suite (another run holds the lock) is not stored: once the lock is free
#    the next Stop must run the suite, and a failing suite must block (it used to be hidden for the whole window)
BZ="$TMP/busy"; mkdir -p "$BZ/src/test" "$BZ/.agents" && cd "$BZ" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt && echo "assert(true)" > src/test/CoreTest.kt
RUNS2="$TMP/runs2"; : > "$RUNS2"
cat > .agents/regression_matrix.active.json <<JSON
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt","src/test/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-X","name":"core","command":"printf x >> $RUNS2; [ ! -f $TMP/failnow ]"}]}]}
JSON
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt && echo "// weakened" > src/test/CoreTest.kt
bstop() { printf '{"session_id":"s-y2","hook_event_name":"Stop","transcript_path":"%s"}' "$TMP/s2.jsonl" \
  | env "$@" CLAUDE_PROJECT_DIR="$BZ" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
python3 - "$BZ" "$TMP/s2.jsonl" <<'PY'
import json, sys, time
repo, tp = sys.argv[1], sys.argv[2]
open(tp, "w").write("".join(json.dumps(r) + "\n" for r in [
    {"type": "user", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - 600)),
     "message": {"role": "user", "content": "fix it"}},
    {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "e1", "name": "Edit",
        "input": {"file_path": repo + "/src/test/CoreTest.kt", "old_string": "a", "new_string": "b"}}]}}]))
PY
rm -f "$TMP/held"; mkdir -p "$BZ/.claude/audit-gate"
python3 - "$BZ" "$TMP/held" <<'PY' &
import fcntl, sys, time
with open(sys.argv[1] + "/.claude/audit-gate/test_run.lock", "a") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    open(sys.argv[2], "w").close()
    time.sleep(8)
PY
holder=$!
for _ in $(seq 1 50); do [ -f "$TMP/held" ] && break; sleep 0.1; done
bstop TEST_RUN_LOCK_WAIT_S=1; rc=$?
[ "$rc" = 2 ] && [ "$(wc -c < "$RUNS2" | tr -d ' ')" = 0 ] && grep -q "BUSY" "$TMP/err" \
  && ok "lock held: the stop is blocked for the edited test, the suite did not run (BUSY)" \
  || fail "busy stop: rc=$rc ran=$(wc -c < "$RUNS2") err='$(head -4 "$TMP/err")'"
wait "$holder" 2>/dev/null
touch "$TMP/failnow"
bstop X=1; rc=$?
[ "$(wc -c < "$RUNS2" | tr -d ' ')" -ge 1 ] && [ "$rc" = 2 ] && grep -q "REG-X" "$TMP/err" && ! grep -q "BUSY" "$TMP/err" \
  && ok "lock free again: the next stop runs the suite and the failing suite blocks (the BUSY line was not kept)" \
  || fail "after BUSY: rc=$rc ran=$(wc -c < "$RUNS2") err='$(head -4 "$TMP/err")' out='$(head -c 200 "$TMP/out")'"
# a fresh stored reminder, then a run that sees the failure: nothing may be left to hide it afterwards
rm -f "$TMP/failnow"
bstop X=1; rc=$?
[ "$rc" = 0 ] && grep -q "Vẫn chờ người duyệt" "$TMP/out" && ok "suite green again: the reminder is stored (touched test only)" \
  || fail "green suite, touched test: rc=$rc out='$(head -c 200 "$TMP/out")' err='$(head -3 "$TMP/err")'"
touch "$TMP/failnow"
# (the old loop guard may release the second block of one content with a visible warning: look at both streams)
bran=$(wc -c < "$RUNS2" | tr -d ' ')
bstop REGRESSION_GATE_TOUCHED_RECHECK_S=0
cat "$TMP/out" "$TMP/err" | grep -q "REG-X core: FAIL" && [ "$(wc -c < "$RUNS2" | tr -d ' ')" -gt "$bran" ] \
  && ok "RECHECK_S=0 run runs the suite and reports the failure" || fail "failure not seen: out='$(head -c 200 "$TMP/out")' err='$(head -3 "$TMP/err")'"
bran=$(wc -c < "$RUNS2" | tr -d ' ')
bstop X=1
cat "$TMP/out" "$TMP/err" | grep -q "REG-X core: FAIL" && ! grep -q "Vẫn chờ người duyệt diff test" "$TMP/out" && [ "$(wc -c < "$RUNS2" | tr -d ' ')" -gt "$bran" ] \
  && ok "after a run that saw a failure the older stored reminder is gone: the suite runs and the failure is reported again" \
  || fail "stale reminder hid a failure (ran $bran -> $(wc -c < "$RUNS2") times out='$(head -c 150 "$TMP/out")')"

cd "$TMP" || exit 1
if [ "$FAILS" -ne 0 ]; then echo "regression gate reminder throttle: $FAILS FAILED"; exit 1; fi
echo "regression gate reminder throttle: all checks passed"
