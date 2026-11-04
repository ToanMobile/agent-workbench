#!/usr/bin/env bash
# rules/essentials.md "Every prompt" step 3: the scoped gate runs ONCE per PR, on the final tree after review fixes.
# 03/11/2026 (workbench runs.jsonl, 24 h): 23 repeated scoped runs on one project = 18.2 % of suite seconds, 18 of
# them after an exit 0 on the same work (ny-guard-v2: 9 runs in 3.5 h). Mid-task turns run the paired oracle and the
# changed tests with `bash <test>` and reply CHƯA XONG; a large task keeps gate, audit, fix, gate. bash 3.2 compatible.
set -u
DK="$(cd "$(dirname "$0")/../.." && pwd)"
ESS="$DK/rules/essentials.md"
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

[ -f "$ESS" ] || { echo "✖ missing $ESS"; exit 1; }
# step 3 only: from its "3. " line to the "4. " line, joined into one line (the wrap point must not matter)
step3="$(awk '/^## Every prompt/{e=1} e && /^3\. /{f=1} e && /^4\. /{f=0} f' "$ESS" | tr '\n' ' ' | tr -s ' ')"
[ -n "$step3" ] || { echo "✖ step 3 of 'Every prompt' not found in rules/essentials.md"; exit 1; }

has() { case "$step3" in *"$1"*) return 0 ;; esac; return 1; }
has "Once per handover" && ok "step 3: once per handover (one PR, worktree finish or main push)" || fail "step 3 does not say the gate runs once per handover"
has "on the final tree after review fixes" && ok "step 3: on the final tree, after review fixes" \
  || fail "step 3 does not place the gate on the final tree after review fixes"
has "large task: gate, audit, fix, gate" && ok "step 3: a large task keeps gate, audit, fix, gate" \
  || fail "step 3 drops the large-task order gate, audit, fix, gate"
has "Mid-task: only the step 2 oracle and changed tests (\`bash <test>\`), reply CHƯA XONG" \
  && ok "step 3: a mid-task turn runs the oracle and the changed tests, replies CHƯA XONG, no gate" \
  || fail "step 3 does not tell a mid-task turn to run only the oracle and changed tests and reply CHƯA XONG"
has "post-fix-gate.py --run-tests --scoped --brief" && ok "step 3: the scoped gate command is kept" \
  || fail "step 3 lost the scoped gate command"
has "Exit 0 is required" && has "writes the task receipt" && ok "step 3: exit 0 and the task receipt stay the bar" \
  || fail "step 3 lost 'Exit 0 is required' or the task receipt"
# 03/11 owner: in a PR repo the merge gate IS the one gate — no gate in the worktree before pushing the PR branch, XONG waits for
# the merge receipt; a trunk-push repo still gates before `agent-kit integrate`
has "PR repo: the merge gate is that gate" && ok "step 3: PR repo — the merge gate is the gate, no pre-push gate" \
  || fail "step 3 does not make the merge gate the one gate of a PR repo"
has "XONG waits for its merge receipt" && ok "step 3: PR repo XONG waits for the merge receipt" \
  || fail "step 3 does not say a PR repo's XONG waits for the merge receipt"
grep -q "A trunk push and every XONG need the latest gate on that content at exit 0" "$ESS" \
  && ok "Git: trunk push and XONG keep the gate bar" || fail "Git: trunk push / XONG lost the gate bar"
has "PR repo: the merge gate is that gate (no pre-push gate)" && ok "step 3: a PR branch push needs no gate of its own" \
  || fail "step 3: still demands a gate before every PR branch push"
grep -q "Every commit and push needs the latest gate" "$ESS" && fail "Git: still demands a gate before every commit and push" \
  || ok "Git: no longer demands a gate before every push (only trunk push and XONG)"
# the Git rule still re-gates after a pull, merge or conflict fix: "once" must not have removed it
grep -q "re-run the step 3 gate after any pull, merge or conflict fix" "$ESS" \
  && ok "Git: re-gate after a pull, merge or conflict fix is kept" || fail "Git: the re-gate after a pull/merge/conflict fix is gone"

[ "$FAILS" = 0 ] && echo "✅ test_gate_once_per_pr: all checks passed" || { echo "❌ test_gate_once_per_pr: $FAILS failed"; exit 1; }
