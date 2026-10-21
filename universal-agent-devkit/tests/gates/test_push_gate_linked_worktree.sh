#!/usr/bin/env bash
# Regression test (issue #5) for bin/push_gate.py in Trunk Mode: the gate runs in a linked worktree and writes its receipt under
# <common>/worktrees/<name>/postfix-gate/, the work is merged into main, and `git push` from main looked only at <common>/postfix-gate/.
#  L1 a receipt of a linked worktree whose head is in the history of main's pushed commit (ff merge) covers the push.
#  L2 an ungated commit made on main after that merge is still refused.
#  L3 code changed in the worktree after its gate covers nothing; L3b nor does a receipt whose head is NOT in the pushed history
#     (the gated commit rewritten, only a docs file added: without the ancestry rule the diff would pass as "needs no test").
#  L4 a forged receipt in a linked worktree (invented fingerprint) is refused like one in main.
#  L5/L6 a linked worktree whose folder is gone, or that has no regression matrix, vouches for nothing.
#  L7 the issue's own flow: gate in the worktree, `worktree finish` merges it into main and REMOVES it (its git dir and receipt go
#     with it): the push from main is still covered. L8 an ungated commit on main after that is refused.
#  L9 a stale receipt carried into main earlier does not hide a covering worktree. L10 a worktree gated on UNCOMMITTED work at main's
#     HEAD does not cover that HEAD. L11 `automerge --keep` (the Stop hook) then `worktree remove` keeps the push covered. L12 a
#     worktree's own remote view is no receipt for a tag push. L13 a carried receipt naming another project's run is refused.
#     L14 a linked worktree whose check raises does not stop the others from covering the push. L15 a receipt carried into main is
#     judged by the linked rules (gated on uncommitted work that main later reverted: refused). L16 a linked worktree with no receipt
#     does not vouch through its own upstream ("@{u}..rev is docs only"). L17 a linked worktree whose receipt of the pushed content is
#     not an exit 0 (the exit 2 the gate keeps for an UNVERIFIED or partial run, same fingerprint and head) does not cover the push.
# Every refusal must be a verdict, never "không kiểm được biên nhận gate" (a crash also exits 2).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"; PG="$DEVKIT_DIR/bin/push_gate.py"; WTPY="$DEVKIT_DIR/scripts/git/worktree.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
R="$TMP/repo"; W="$TMP/wt"
expect() {   # expect <name> <exit> [text the reason (push_gate.check, printed by the CLI only on a refusal) must contain]
  OUT="$(python3 "$PG" "$R" 2>&1)"; RC=$?
  WHY="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import push_gate; print(push_gate.check(sys.argv[2])[1])' "$DEVKIT_DIR/bin" "$R" 2>&1)"
  if [ "$RC" = "$2" ] && ! printf '%s' "$OUT" | grep -qF "không kiểm được biên nhận gate" \
      && { [ -z "${3:-}" ] || printf '%s' "$WHY" | grep -qF -- "$3"; }; then ok "$1 (exit $RC)"
  else bad "$1: exit $RC, expected $2${3:+ with \"$3\"} — $(printf '%s | %s' "$OUT" "$WHY" | head -c 400)"; fi
}
newrepo() {
  git -C "$R" worktree prune 2>/dev/null; rm -rf "$R" "$W" "$TMP/origin.git"; mkdir -p "$R/src" "$R/.agents" && cd "$R" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  echo "fun ok() = 1" > src/Core.kt
  cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
  printf '.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/evidence/\n.agents/regression_journal/\n.claude/\n' > .gitignore   # gate bookkeeping
  git add -A && git commit -qm init
  git init -q --bare "$TMP/origin.git" && git remote add origin "$TMP/origin.git" && git push -q -u origin HEAD 2>/dev/null
  git worktree add -q -b task "$W" main
}
gated_worktree_commit() {   # edit code in the worktree, run the full gate there, commit
  echo "fun ok() = $1" > "$W/src/Core.kt"
  CLAUDE_PROJECT_DIR="$W" python3 "$GATE" --run-tests --full --brief > "$TMP/gate.out" 2>&1 \
    || bad "setup: gate --full in the worktree failed (exit $?): $(tail -3 "$TMP/gate.out")"
  git -C "$W" commit -qam "task work $1" || bad "setup: commit of the gated work failed"
}

newrepo
gated_worktree_commit 2
git -C "$R" merge -q --ff-only task || bad "L1 setup: merge failed"
expect "L1: worktree gated, merged ff into main: the push from main is covered" 0 "covered by the gate receipt of the linked worktree"

echo "fun ok() = 3" > "$R/src/Core.kt"; git -C "$R" commit -qam "ungated on main" || bad "L2 setup: commit failed"
expect "L2: an ungated commit on main after the merge is refused" 2

newrepo
gated_worktree_commit 2
git -C "$W" commit -q --amend -m "reworded" && echo "fun ok() = 9" > "$W/src/Core.kt" && git -C "$W" commit -qam "changed after gate" \
  && git -C "$R" merge -q --ff-only task || bad "L3 setup: amend / commit / merge failed"
expect "L3: code changed in the worktree after its gate: refused" 2

newrepo
echo "fun ok() = 2" > "$W/src/Core.kt"; git -C "$W" commit -qam "task work 2" || bad "L3b setup: commit failed"
CLAUDE_PROJECT_DIR="$W" python3 "$GATE" --run-tests --full --brief --diff main > "$TMP/gate.out" 2>&1 || bad "L3b setup: gate --full failed: $(tail -3 "$TMP/gate.out")"
git -C "$W" reset -q --soft HEAD~1 && echo "# notes" > "$W/NOTES.md" && git -C "$W" add NOTES.md && git -C "$W" commit -qm "rewritten after gate" \
  && git -C "$R" merge -q --ff-only task || bad "L3b setup: rewrite / merge failed"
expect "L3b: the gated commit rewritten after the gate (receipt head not in the pushed history): refused" 2

newrepo
gated_worktree_commit 2
RW="$(git -C "$W" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"
python3 - "$RW" <<'PY'
import json, sys
r = json.load(open(sys.argv[1])); r["fingerprint"] = "0123456789abcdef01234567"; json.dump(r, open(sys.argv[1], "w"))
PY
[ $? = 0 ] || bad "L4 setup: forging the receipt failed"
git -C "$R" merge -q --ff-only task || bad "L4 setup: merge failed"
expect "L4: a forged worktree receipt (invented fingerprint): refused" 2

# A linked worktree with no receipt must never vouch for main: its own early "nothing to check" answers are not coverage.
newrepo
echo "fun ok() = 4" > "$R/src/Core.kt"; git -C "$R" commit -qam "ungated on main" && rm -rf "$W" || bad "L5 setup: commit failed"
expect "L5: a linked worktree whose folder is gone (prunable) does not cover an ungated push" 2

newrepo
git -C "$W" rm -q .agents/regression_matrix.active.json && git -C "$W" commit -qm "no matrix on this branch" || bad "L6 setup: removing the matrix failed"
echo "fun ok() = 5" > "$R/src/Core.kt"; git -C "$R" commit -qam "ungated on main" || bad "L6 setup: commit failed"
expect "L6: a linked worktree without a regression matrix does not cover an ungated push" 2

newrepo
gated_worktree_commit 2
(cd "$R" && GIT_CONFIG_GLOBAL=/dev/null python3 "$WTPY" finish "$W" > "$TMP/finish.out" 2>&1) || bad "L7 setup: worktree finish failed: $(tail -3 "$TMP/finish.out")"
[ -d "$W" ] && bad "L7 setup: worktree finish left the worktree in place: $(tail -3 "$TMP/finish.out")"
expect "L7: worktree gated, then merged and removed by worktree finish: the push from main is covered" 0 "covered"

echo "fun ok() = 6" > "$R/src/Core.kt"; git -C "$R" commit -qam "ungated on main" || bad "L8 setup: commit failed"
expect "L8: an ungated commit on main after worktree finish is refused" 2

# the next task: main keeps the (now stale) receipt the first finish carried; a new worktree gated and merged by hand still covers
newrepo
gated_worktree_commit 2
(cd "$R" && GIT_CONFIG_GLOBAL=/dev/null python3 "$WTPY" finish "$W" > "$TMP/finish.out" 2>&1) || bad "L9 setup: worktree finish failed: $(tail -3 "$TMP/finish.out")"
git -C "$R" worktree add -q -b task2 "$W" main || bad "L9 setup: worktree add failed"
gated_worktree_commit 7
git -C "$R" merge -q --ff-only task2 || bad "L9 setup: merge failed"
expect "L9: main holds a stale valid receipt, a linked worktree's receipt covers the new head: the push is covered" 0 \
  "covered by the gate receipt of the linked worktree"

# a worktree at main's HEAD that passed the gate only thanks to UNCOMMITTED work: main's HEAD itself was never tested
newrepo
echo "fun ok() = 4" > "$R/src/Core.kt"; git -C "$R" commit -qam "ungated on main" && git -C "$W" merge -q --ff-only main \
  || bad "L10 setup: commit / merge failed"
echo "fun ok() = 2" > "$W/src/Core.kt"
CLAUDE_PROJECT_DIR="$W" python3 "$GATE" --run-tests --full --brief > "$TMP/gate.out" 2>&1 || bad "L10 setup: gate --full failed: $(tail -3 "$TMP/gate.out")"
expect "L10: a worktree at main's HEAD gated on uncommitted work does not cover main's untested HEAD" 2

# the Stop hook's path: `automerge --keep` merges and keeps the worktree, a later `worktree remove` takes its git dir with it
newrepo
gated_worktree_commit 2
(cd "$R" && GIT_CONFIG_GLOBAL=/dev/null python3 "$WTPY" automerge "$W" --keep > "$TMP/finish.out" 2>&1) || bad "L11 setup: automerge --keep failed: $(tail -3 "$TMP/finish.out")"
(cd "$R" && GIT_CONFIG_GLOBAL=/dev/null python3 "$WTPY" remove "$W" > "$TMP/remove.out" 2>&1) || bad "L11 setup: worktree remove failed: $(tail -3 "$TMP/remove.out")"
[ -d "$W" ] && bad "L11 setup: the worktree is still there"
expect "L11: merged with automerge --keep, then removed: the push from main is covered" 0 "covered"

# a tag push: a linked worktree's own remote view ("already on the remote") is no receipt
newrepo
echo "fun ok() = 8" > "$R/src/Core.kt"; git -C "$R" commit -qam "ungated, unpushed" && git -C "$R" tag v8 && git -C "$R" config extensions.worktreeConfig true \
  && git -C "$W" config --worktree "url.$R.insteadOf" "$TMP/origin.git" || bad "L12 setup: commit / tag / worktree config failed"
OUT="$(python3 "$PG" "$R" v8 --tag-remote origin 2>&1)"; RC=$?
[ "$RC" = 2 ] && ! printf '%s' "$OUT" | grep -qF "không kiểm được biên nhận gate" \
  && ok "L12: a tag of an ungated commit is not covered by a linked worktree's remote view (exit $RC)" \
  || bad "L12: tag push through a linked worktree's remote view: exit $RC, expected 2 — $(printf '%s' "$OUT" | head -c 300)"

# the carried receipt's run-log lookup goes by carried_from: naming a project with no full PASS line finds nothing
newrepo
gated_worktree_commit 2
(cd "$R" && GIT_CONFIG_GLOBAL=/dev/null python3 "$WTPY" finish "$W" > "$TMP/finish.out" 2>&1) || bad "L13 setup: worktree finish failed: $(tail -3 "$TMP/finish.out")"
python3 - "$(git -C "$R" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1])); assert r.get("carried_from"), "no carried receipt in main"
r["carried_from"] = "/nowhere/other-project"; json.dump(r, open(sys.argv[1], "w"))
PY
[ $? = 0 ] || bad "L13 setup: main holds no carried receipt"
expect "L13: a carried receipt whose carried_from names another project's run: refused" 2 "runs.jsonl"

# one linked worktree whose check raises (a git error in a half-broken worktree) must not hide another that covers the push
newrepo
gated_worktree_commit 2
git -C "$R" merge -q --ff-only task
WHY="$(python3 - "$DEVKIT_DIR/bin" "$R" "$W" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
import push_gate
real = push_gate._own_check
def own_check(cwd, rev, tag_remote, linked):
    if cwd == "/broken-worktree":
        raise RuntimeError("git diff failed")
    return real(cwd, rev, tag_remote, linked)
push_gate._own_check = own_check
push_gate.linked_worktrees = lambda top: ["/broken-worktree", sys.argv[3]]
ok, why = push_gate.check(sys.argv[2])
print(ok, why)
PY
)"
case "$WHY" in "True covered by the gate receipt of the linked worktree"*) ok "L14: a linked worktree whose check raises is skipped, the next one covers the push" ;;
  *) bad "L14: a raising linked worktree broke the fallback: $(printf '%s' "$WHY" | tail -3)" ;; esac

# a receipt carried into main is judged by the linked rules too: its gate passed on UNCOMMITTED work that `worktree finish` committed;
# main then reverts that work, so the pushed tree (back to the base) is not the tested one even though head..rev changes nothing
newrepo
echo "fun ok() = 2" > "$W/src/Core.kt"
CLAUDE_PROJECT_DIR="$W" python3 "$GATE" --run-tests --full --brief > "$TMP/gate.out" 2>&1 || bad "L15 setup: gate --full failed: $(tail -3 "$TMP/gate.out")"
(cd "$R" && GIT_CONFIG_GLOBAL=/dev/null python3 "$WTPY" finish "$W" > "$TMP/finish.out" 2>&1) || bad "L15 setup: worktree finish failed: $(tail -3 "$TMP/finish.out")"
grep -qF "carried_from" "$(git -C "$R" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json" 2>/dev/null \
  || bad "L15 setup: finish carried no receipt into main: $(tail -3 "$TMP/finish.out")"
echo "fun ok() = 1" > "$R/src/Core.kt"; git -C "$R" commit -qam "revert the gated work on main" || bad "L15 setup: commit failed"
expect "L15: a carried receipt gated on uncommitted work, that work reverted on main: refused" 2 "khác bản gate đã test"

# a linked worktree with NO receipt whose upstream already holds main's ungated code: its own "@{u}..rev is docs only" answer is no receipt
newrepo
echo "fun ok() = 5" > "$W/src/Core.kt"; git -C "$W" commit -qam "ungated code" && git -C "$W" push -q -u origin task 2>/dev/null \
  && git -C "$R" merge -q --ff-only task && echo "# notes" > "$R/NOTES.md" && git -C "$R" add NOTES.md && git -C "$R" commit -qm "docs" \
  || bad "L16 setup: commit / push / merge failed"
expect "L16: a linked worktree without a receipt, its upstream holding main's ungated code, does not cover the push" 2

# a receipt of exactly the pushed content whose verdict is not exit 0: write_full_pass_receipt keeps the PASS receipt as "exit": 2 for an
# UNVERIFIED run (an edited test awaiting review) or a partial run of the same code; only "exit": 0 covers a push (QA issue #5, surviving
# mutant: without `receipt.get("exit") != 0` in _own_check every push_gate test stayed green)
newrepo
gated_worktree_commit 2
git -C "$R" merge -q --ff-only task || bad "L17 setup: merge failed"
expect "L17 control: the exit-0 receipt covers the push" 0 "covered by the gate receipt of the linked worktree"
python3 - "$(git -C "$W" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1])); assert r.get("exit") == 0, r.get("exit"); r["exit"] = 2; json.dump(r, open(sys.argv[1], "w"))
PY
[ $? = 0 ] || bad "L17 setup: turning the receipt down to exit 2 failed"
expect "L17: a linked worktree receipt of the pushed content with exit 2 (UNVERIFIED / partial): refused" 2

# A linked worktree must not exempt a file from the test with ITS OWN matrix / checklist: main's checklist links README.md to REG-1
# (`covers`, git-ignored, per checkout: the worktree never saw the link). README.md committed on main after the merge is then watched
# by the matrix, so it needs a test, and the worktree receipt (its head older than that commit) must not call it "docs only".
newrepo
gated_worktree_commit 2
git -C "$R" merge -q --ff-only task || bad "L18 setup: merge failed"
echo "# readme" > "$R/README.md"; git -C "$R" add README.md && git -C "$R" commit -qm "readme (ungated)" || bad "L18 setup: readme commit failed"
expect "L18 control: no link, README.md needs no test: the worktree receipt covers the push" 0 "covered by the gate receipt of the linked worktree"
printf '%s' '{"items": {"REG-1": {"kind": "test", "covers": ["README.md"]}}}' > "$R/.agents/regression_status.json" \
  || bad "L18 setup: writing the covers link failed"
expect "L18: main links README.md to REG-1 and README.md changed after the worktree gate: the worktree cannot exempt it" 2 "chưa có biên nhận gate --full"

# L19: the exemption needs BOTH sides to agree. The worktree's own checklist links NOTES.md to REG-1 (a stricter rule main does not
# have: git-ignored, per checkout), main's has no such link: NOTES.md changed on main after the worktree gate is not "docs only".
newrepo
gated_worktree_commit 2
printf '%s' '{"items": {"REG-1": {"kind": "test", "covers": ["NOTES.md"]}}}' > "$W/.agents/regression_status.json" || bad "L19 setup: writing the worktree link failed"
git -C "$R" merge -q --ff-only task || bad "L19 setup: merge failed"
echo "# notes" > "$R/NOTES.md"; git -C "$R" add NOTES.md && git -C "$R" commit -qm "notes (ungated)" || bad "L19 setup: notes commit failed"
expect "L19: a rule only the worktree's checklist has (NOTES.md→REG-1) also keeps NOTES.md from being exempted: refused" 2 "chưa có biên nhận gate --full"

# L20: the work tree of main cannot be located (`git worktree list` fails): fail closed, the worktree receipt exempts nothing
newrepo
gated_worktree_commit 2
git -C "$R" merge -q --ff-only task || bad "L20 setup: merge failed"
echo "# readme" > "$R/README.md"; git -C "$R" add README.md && git -C "$R" commit -qm "readme (ungated)" || bad "L20 setup: readme commit failed"
expect "L20 control: main matrix found, README.md docs only: the worktree receipt covers the push" 0 "covered by the gate receipt of the linked worktree"
WHY="$(python3 - "$DEVKIT_DIR/bin" "$R" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
import push_gate
real_git, real_own, state = push_gate.git, push_gate._own_check, {"linked": False}
def git(top, *args, **kw):
    if state["linked"] and args[:2] == ("worktree", "list"):
        return 1, ""
    return real_git(top, *args, **kw)
def own(cwd, rev, tag_remote, linked):
    state["linked"] = bool(linked)
    try:
        return real_own(cwd, rev, tag_remote, linked)
    finally:
        state["linked"] = False
push_gate.git, push_gate._own_check = git, own
print(*push_gate.check(sys.argv[2]))
PY
)"
WHY="$(printf '%s' "$WHY" | tail -1)"   # the line before is the warning untestable_only prints on stderr
case "$WHY" in "False "*) ok "L20: the work tree of main not found: fail closed, the receipt exempts nothing" ;;
  *) bad "L20: expected a refusal when main cannot be located, got: $(printf '%s' "$WHY" | tail -2)" ;; esac

# L21 (#154, 21/10): the worktree edits an EXISTING test and passes its --full with --auto-approve-tests (exit 0); `worktree finish`'s
#     merge gate (--diff <main>, partial, no approval flag) ends exit 2 "edited_test" — the session's own business, never a reason to refuse
#     the merge — and used to turn that exit-0 receipt down to exit 2, so the push from main was refused and the gate had to run again.
newrepo
mkdir -p "$R/tests" && printf 'exit 0\n' > "$R/tests/test_core.sh" && git -C "$R" add tests/test_core.sh && git -C "$R" commit -qm "a test" \
  && git -C "$W" merge -q --ff-only main || bad "L21 setup: test on main failed"
echo "fun ok() = 21" > "$W/src/Core.kt"; printf 'exit 0 # v2\n' > "$W/tests/test_core.sh"
CLAUDE_PROJECT_DIR="$W" python3 "$GATE" --run-tests --full --brief --auto-approve-tests > "$TMP/gate.out" 2>&1 \
  || bad "L21 setup: gate --full --auto-approve-tests in the worktree failed (exit $?): $(tail -3 "$TMP/gate.out")"
git -C "$W" commit -qam "task work with an edited test" || bad "L21 setup: commit failed"
(cd "$R" && GIT_CONFIG_GLOBAL=/dev/null python3 "$WTPY" finish "$W" > "$TMP/finish.out" 2>&1) || bad "L21 setup: worktree finish failed: $(tail -3 "$TMP/finish.out")"
expect "L21: an edited test approved by the worktree's own --full, then worktree finish: the push from main is still covered" 0 "covered"

[ "$FAILS" = 0 ] && echo "ALL OK" && exit 0
echo "$FAILS FAILED"; exit 1
