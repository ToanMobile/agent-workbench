#!/usr/bin/env bash
# Regression test (đợt 2 lane B, 03/11): hooks/regression_gate.sh keys the stored "edited test waits for review" reminder on the
# content (the existing key) AND a digest of every source the gate reads to approve an edited test (bin/approval_digest.py:
# approved_tests.json, approved_hashes.json, the antigravity-pm audit records of the task ids the ledger and the
# Test-approved-by trailers name, the answers of the user that name a changed file in every candidate transcript, the trunk tip,
# the env that changes the verdict). The old 300 s window is gone: measured 03/11, 62 edited_test Stop runs a day, 36 of them
# the same (project, fp) again, ~47 s each, only because the window ran out.
# RED on the old hook: (a) a reminder older than 300 s with the same content and digest re-ran the gate; (b) a PM verdict that
# lands after the ledger entry, (c) an answer of the user in a transcript that is not the newest file, were not seen inside
# the window. (d) REGRESSION_GATE_TOUCHED_RECHECK_S=0 still runs the gate on every Stop (guard, green on both).
# The gate cache is off so every gate run starts the suite: the suite run count tells that the gate ran.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/regression_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# Nothing of the real machine may move the digest mid-test: own HOME (no ~/.claude/projects, no Antigravity brain logs),
# own antigravity-pm home (a test fixture under the temp dir), no inherited session or agent id.
unset CLAUDE_CODE_SESSION_ID DEVKIT_AGENT_ID DEVKIT_TRANSCRIPTS_DIR REGRESSION_GATE_TOUCHED_RECHECK_S DEVKIT_GATE_CACHE_MAX_S \
      DEVKIT_AUTO_APPROVE_TESTS
export HOME="$TMP/home"; mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm" DEVKIT_PM_HOME_TEST=1
export DEVKIT_GATE_CACHE=0 WORKTREE_TRUNK_MODE=0

X="$TMP/repo"; mkdir -p "$X/src/test" "$X/.agents" "$TMP/tr" && cd "$X" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt && echo "assert(true)" > src/test/CoreTest.kt
RUNS="$TMP/runs"; : > "$RUNS"
cat > .agents/regression_matrix.active.json <<JSON
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt","src/test/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-X","name":"core","command":"printf x >> $RUNS"}]}]}
JSON
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt && echo "// weakened" > src/test/CoreTest.kt
# the edited test is an hour old: a transcript written since then is a candidate of the gate, at any mtime after that
python3 -c 'import os,sys,time; t = time.time() - 3600; [os.utime(p, (t, t)) for p in sys.argv[1:]]' src/test/CoreTest.kt src/Core.kt
runs() { wc -c < "$RUNS" | tr -d ' '; }
TP="$TMP/tr/s.jsonl"
python3 - "$X" "$TP" <<'PY'
import json, sys, time
repo, tp = sys.argv[1], sys.argv[2]
open(tp, "w").write("".join(json.dumps(r) + "\n" for r in [
    {"type": "user", "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - 600)),
     "message": {"role": "user", "content": "fix it"}},
    {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "e1", "name": "Edit",
        "input": {"file_path": repo + "/src/test/CoreTest.kt", "old_string": "a", "new_string": "b"}}]}}]))
PY
stop() { printf '{"session_id":"s-k1","hook_event_name":"Stop","transcript_path":"%s"}' "$TP" \
  | env "$@" CLAUDE_PROJECT_DIR="$X" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
STATE="$X/.claude/audit-gate/regression_gate.state.json"
LOG="$X/.claude/audit-gate/regression_gate.log"
reused() { grep -c "reused, no run" "$LOG" 2>/dev/null | tr -d ' '; }
age_reminder() { python3 -c 'import json,sys,time
p = sys.argv[1]; d = json.load(open(p)); d["touched"]["s-k1"]["at"] = time.time() - float(sys.argv[2]); json.dump(d, open(p, "w"))' "$STATE" "$1"; }

# 1. first Stop of the change: the gate runs and blocks; the repeat prints the stored reminder without a run
stop X=1; rc=$?
[ "$rc" = 2 ] && grep -q "src/test/CoreTest.kt" "$TMP/err" && [ "$(runs)" = 1 ] \
  && ok "first stop: the gate ran once and blocked on the edited test" \
  || fail "first stop: rc=$rc runs=$(runs) err='$(head -3 "$TMP/err")'"
stop X=1; rc=$?
[ "$rc" = 0 ] && [ "$(runs)" = 1 ] && grep -q "Vẫn chờ người duyệt" "$TMP/out" \
  && ok "repeat stop: the stored reminder, no gate run" || fail "repeat stop: rc=$rc runs=$(runs) out='$(head -c 200 "$TMP/out")'"

# (a) older than the old 300 s window, same content, same approval sources: no run. The session transcript grows (its mtime
#     moves) with a line that is no answer of the user: the digest must not follow the transcript mtime.
age_reminder 400
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"still waiting for the review"}]}}' >> "$TP"
before=$(runs); rb=$(reused); stop X=1; rc=$?
[ "$rc" = 0 ] && [ "$(runs)" = "$before" ] && [ "$(reused)" -gt "$rb" ] && grep -q "Vẫn chờ người duyệt" "$TMP/out" \
  && ok "(a) reminder 400 s old, same content and approval digest, transcript grew: reused, the gate did NOT run" \
  || fail "(a) aged reminder with unchanged approval sources re-ran the gate: rc=$rc runs $before -> $(runs) log='$(tail -1 "$LOG")'"

# the default ceiling is DEVKIT_GATE_CACHE_MAX_S (6 h), and an explicit value of either switch is the ceiling
stop X=1 DEVKIT_GATE_CACHE_MAX_S=100     # the gate cache setting is part of the digest: this run stores a reminder under it
before=$(runs); stop X=1 DEVKIT_GATE_CACHE_MAX_S=100
[ "$(runs)" = "$before" ] || fail "cap: a fresh reminder under DEVKIT_GATE_CACHE_MAX_S=100 was not reused (runs $before -> $(runs))"
age_reminder 400
before=$(runs); stop X=1 DEVKIT_GATE_CACHE_MAX_S=100
[ "$(runs)" -gt "$before" ] && ok "cap: DEVKIT_GATE_CACHE_MAX_S=100 and a 400 s old reminder: the gate runs" \
  || fail "cap: DEVKIT_GATE_CACHE_MAX_S=100 did not bound the reuse (runs $before -> $(runs))"
before=$(runs); stop X=1
[ "$(runs)" -gt "$before" ] && ok "a changed gate cache setting (back to the default) is a new digest: the gate runs" \
  || fail "the reminder stored under DEVKIT_GATE_CACHE_MAX_S=100 was reused without it (runs $before -> $(runs))"
age_reminder 400
before=$(runs); stop X=1 REGRESSION_GATE_TOUCHED_RECHECK_S=300
[ "$(runs)" -gt "$before" ] && ok "cap: explicit REGRESSION_GATE_TOUCHED_RECHECK_S=300 and a 400 s old reminder: the gate runs" \
  || fail "cap: explicit RECHECK_S=300 did not bound the reuse (runs $before -> $(runs))"
age_reminder 22000
before=$(runs); stop X=1
[ "$(runs)" -gt "$before" ] && ok "cap: a reminder older than 21600 s (default ceiling): the gate runs" \
  || fail "cap: a 22000 s old reminder was reused (runs $before -> $(runs))"
before=$(runs); stop X=1
[ "$(runs)" = "$before" ] && ok "cap: and the next stop reuses the fresh reminder again" || fail "no reuse after the capped run (runs $before -> $(runs))"

# (d) RECHECK_S=0: the gate runs on every Stop
before=$(runs); stop REGRESSION_GATE_TOUCHED_RECHECK_S=0; stop REGRESSION_GATE_TOUCHED_RECHECK_S=0; rc=$?
[ "$rc" = 0 ] && [ "$(runs)" = $((before + 2)) ] && grep -q "src/test/CoreTest.kt" "$TMP/out" \
  && ok "(d) REGRESSION_GATE_TOUCHED_RECHECK_S=0: two stops, two gate runs, reminder printed" \
  || fail "(d) recheck=0: rc=$rc runs $before -> $(runs) out='$(head -c 200 "$TMP/out")'"

# (b) the ledger entry is written first: the next stop runs the gate (new source), then the repeat is reused...
SHA="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' src/test/CoreTest.kt)"
python3 - "$X" "$SHA" <<'PY'
import json, sys
repo, sha = sys.argv[1], sys.argv[2]
json.dump({"approvals": [{"path": "src/test/CoreTest.kt", "sha256": sha, "reviewer": "antigravity", "author": "claude",
                          "task_id": "T0001-core-test", "reason": "assertion kept"}]},
          open(repo + "/.claude/audit-gate/approved_tests.json", "w"))
PY
before=$(runs); stop X=1
[ "$(runs)" -gt "$before" ] && ok "(b) a new approved_tests.json entry: the gate runs" || fail "(b) ledger entry reused the reminder (runs $before -> $(runs))"
before=$(runs); stop X=1
[ "$(runs)" = "$before" ] && ok "(b) ledger unchanged, no verdict yet: the repeat is reused" || fail "(b) repeat after the ledger ran the gate (runs $before -> $(runs))"
# ... and the antigravity-pm verdict lands later, inside the old window: the next stop must judge again
python3 - "$X" "$ANTIGRAVITY_PM_STATE_HOME" "$(git rev-parse HEAD)" <<'PY'
import json, os, sys
repo, pm, head = sys.argv[1], sys.argv[2], sys.argv[3]
d = os.path.join(pm, "projects", "repo-abc", "tasks", "T0001-core-test")
os.makedirs(d, exist_ok=True)
json.dump({"id": "T0001-core-test", "project": os.path.realpath(repo),
           "verdicts": {"audit": {"verdict": "pass", "auditedHead": head, "notes": "auditedHead: " + head}},
           "dispatches": [{"kind": "audit", "agent": "antigravity", "at": "2026-11-03T00:00:00Z"}]},
          open(os.path.join(d, "task.json"), "w"))
PY
before=$(runs); stop X=1
[ "$(runs)" -gt "$before" ] && ok "(b) the PM audit verdict arrived after the ledger: the next stop runs the gate" \
  || fail "(b) the PM verdict that came after the ledger was not judged (reminder reused, runs $before -> $(runs))"
before=$(runs); stop X=1
[ "$(runs)" = "$before" ] && ok "(b) verdict unchanged: the repeat is reused" || fail "(b) repeat after the verdict ran the gate (runs $before -> $(runs))"
# an unrelated task.json field (PM bookkeeping) does not move the digest
python3 - "$ANTIGRAVITY_PM_STATE_HOME" <<'PY'
import json, os, sys
p = os.path.join(sys.argv[1], "projects", "repo-abc", "tasks", "T0001-core-test", "task.json")
d = json.load(open(p)); d["messages"] = ["status ping"]; json.dump(d, open(p, "w"))
PY
before=$(runs); stop X=1
[ "$(runs)" = "$before" ] && ok "(b) a PM field outside verdicts/audit dispatches: still reused" || fail "(b) unrelated PM field re-ran the gate (runs $before -> $(runs))"

# (c) an answer of the user in a candidate transcript that is NOT the newest file: the gate runs again
python3 - "$TMP/tr/other.jsonl" "$TP" <<'PY'
import json, os, sys, time
other, tp = sys.argv[1], sys.argv[2]
q = "Duyệt diff test src/test/CoreTest.kt?"
iso = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - 1500))
rec = {"type": "user", "sessionId": "s-other", "timestamp": iso,
       "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "q1", "content": "answered"}]},
       "toolUseResult": {"questions": [{"question": q, "header": "Test", "options": [
           {"label": "Duyệt", "description": "giữ diff"}, {"label": "Không", "description": "đổi hướng"}]}],
           "answers": {q: "Duyệt"}}}
open(other, "w").write(json.dumps(rec) + "\n")
t = time.time() - 1800                         # after the edited test (an hour old), before the session transcript
os.utime(other, (t, t))
now = time.time()
os.utime(tp, (now, now))
assert os.stat(other).st_mtime < os.stat(tp).st_mtime
PY
before=$(runs); stop X=1
[ "$(runs)" -gt "$before" ] && ok "(c) a user approval in an older candidate transcript (not the newest file): the gate runs" \
  || fail "(c) the user's answer in a non-newest transcript was not judged (runs $before -> $(runs))"

grep -q "approval digest failed" "$LOG" && fail "the approval digest failed in a stop: $(grep "approval digest failed" "$LOG" | tail -1)"
cd "$TMP" || exit 1
if [ "$FAILS" -ne 0 ]; then echo "regression gate reminder approval key: $FAILS FAILED"; exit 1; fi
echo "regression gate reminder approval key: all checks passed"
