#!/usr/bin/env bash
# Regression test (đợt 2 lane B, 03/11; ported to gate speed v26 mục 1): the "edited test waits for review" reminder of
# hooks/regression_gate.sh follows the approval sources: when they change (the approved_tests.json ledger, the antigravity-pm audit
# record that entry names) and the agent runs its gate again, the result is judged again; the old reminder never stands in for it.
# v26: the Stop runs no gate. The agent's gate run (session-less, `post-fix-gate.py --run-tests --scoped --brief`) writes the
# "edited_test" outcome; the Stop blocks once with the cure and later only reminds. What moved from the hook to that gate run: the
# approval digest of bin/approval_digest.py (the hook re-ran the gate when it changed) — the gate run reads the sources itself.
#   1. first gate run: exit 2 (edited test); the Stop blocks once naming the file, the repeat reminds; the Stop runs no suite
#   2. a ledger entry alone (no audit record yet): the next gate run still exit 2; the Stop only reminds (no new block, never a PASS)
#   3. the antigravity-pm audit pass of that task lands: the next gate run judges again, exit 0 (the approval is named); its outcome is
#      gone, so the Stop no longer reminds. A record under a foreign ANTIGRAVITY_PM_STATE_HOME (this fixture) writes no receipt by design
#      (post-fix-gate pm_relaxed: anyone can forge one there), so the Stop still asks for the gate receipt: it blocks, without the reminder.
#   4. a new content after the approval: the approval does not carry over (sha256 of the test), exit 2 again, blocked once again
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/regression_gate.sh"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# Nothing of the real machine may approve: own HOME, own antigravity-pm home (a test fixture under the temp dir), no inherited ids.
unset CLAUDE_CODE_SESSION_ID DEVKIT_AGENT_ID DEVKIT_TRANSCRIPTS_DIR REGRESSION_GATE_TOUCHED_RECHECK_S DEVKIT_GATE_CACHE_MAX_S \
      DEVKIT_AUTO_APPROVE_TESTS CLAUDE_PROJECT_DIR
export HOME="$TMP/home"; mkdir -p "$HOME"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm" DEVKIT_PM_HOME_TEST=1
export DEVKIT_GATE_CACHE=0 WORKTREE_TRUNK_MODE=0

X="$TMP/repo"; mkdir -p "$X/src/test" "$X/.agents" && cd "$X" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt && echo "assert(true)" > src/test/CoreTest.kt
RUNS="$TMP/runs"; : > "$RUNS"
cat > .agents/regression_matrix.active.json <<JSON
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/*.kt","src/test/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-X","name":"core","command":"printf x >> $RUNS"}]}]}
JSON
printf '.claude/\n.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/regression_checklist.md\n' > .gitignore
git add -A && git commit -qm init
runs() { wc -c < "$RUNS" | tr -d ' '; }
stop() { printf '{"session_id":"s-k1","hook_event_name":"Stop","last_assistant_message":"XONG"}' \
  | CLAUDE_PROJECT_DIR="$X" bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; RC=$?; }
stop   # clean tree: verified_head = the start point, so the commits below are the change handed over
# the edit lives on a branch (an audit of a head already on the trunk is refused): commit it, as the cure says
git checkout -q -b issue-1 && echo "fun ok() = 2" > src/Core.kt && echo "// weakened" > src/test/CoreTest.kt && git commit -qam "edit test"
gate() { ( cd "$X" && CLAUDE_PROJECT_DIR="$X" python3 "$GATE" --run-tests --scoped --brief ) >"$TMP/gout" 2>&1; GRC=$?; }
REMIND="Vẫn chờ người duyệt"

# 1
gate; n0=$(runs); stop; r1=$RC; e1="$(cat "$TMP/err")"; stop; r2=$RC
[ "$GRC" = 2 ] && [ "$r1" = 2 ] && printf '%s' "$e1" | grep -q "src/test/CoreTest.kt" && [ "$r2" = 0 ] && grep -q "$REMIND" "$TMP/out" \
  && [ "$(runs)" = "$n0" ] && ok "1. gate exit 2 on the edited test: the Stop blocks once naming it, the repeat reminds, no suite at Stop" \
  || fail "1. gate=$GRC r1=$r1 r2=$r2 runs $n0 -> $(runs) err1='$(printf '%s' "$e1" | head -c 200)' out='$(head -c 200 "$TMP/out")'"

# 2: the ledger entry is written first
SHA="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' src/test/CoreTest.kt)"
mkdir -p .claude/audit-gate
python3 - "$X" "$SHA" <<'PY'
import json, sys
repo, sha = sys.argv[1], sys.argv[2]
json.dump({"approvals": [{"path": "src/test/CoreTest.kt", "sha256": sha, "reviewer": "antigravity", "author": "claude",
                          "task_id": "T0001-core-test", "reason": "assertion kept"}]},
          open(repo + "/.claude/audit-gate/approved_tests.json", "w"))
PY
gate; stop
[ "$GRC" = 2 ] && [ "$RC" = 0 ] && grep -q "$REMIND" "$TMP/out" && ! grep -q "KẾT LUẬN CỔNG POST-FIX AUDIT: PASS" "$TMP/gout" \
  && ok "2. a ledger entry with no audit record: the gate run still exit 2, the Stop only reminds (not a PASS)" \
  || fail "2. gate=$GRC rc=$RC out='$(head -c 200 "$TMP/out")' err='$(head -c 200 "$TMP/err")'"

# 3: the antigravity-pm audit verdict lands later: the next gate run judges again
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
gate; stop
[ "$GRC" = 0 ] && grep -q "T0001-core-test" "$TMP/gout" && ! grep -q "$REMIND" "$TMP/out" "$TMP/err" \
  && ok "3. the audit pass landed: the gate run judged again (exit 0, names the approval); the reminder is gone" \
  || fail "3. gate=$GRC rc=$RC out='$(head -c 200 "$TMP/out")' gate='$(grep -m2 -E 'KẾT LUẬN|T0001' "$TMP/gout")'"
[ "$RC" = 2 ] && grep -q "chưa có biên nhận" "$TMP/err" \
  && ok "3. an approval from a foreign antigravity-pm home writes no receipt: the Stop still asks for the gate receipt" \
  || fail "3. foreign pm home: rc=$RC err='$(head -c 200 "$TMP/err")'"

# 4: a new content of the test after the approval
echo "// weakened twice" > src/test/CoreTest.kt && git commit -qam "edit again"
gate; stop
[ "$GRC" = 2 ] && [ "$RC" = 2 ] && grep -q "src/test/CoreTest.kt" "$TMP/err" \
  && ok "4. the test changed after its approval: exit 2 again, blocked once again" \
  || fail "4. gate=$GRC rc=$RC err='$(head -c 200 "$TMP/err")'"

cd "$TMP" || exit 1
if [ "$FAILS" -ne 0 ]; then echo "regression gate reminder approval key: $FAILS FAILED"; exit 1; fi
echo "regression gate reminder approval key: all checks passed"
