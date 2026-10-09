#!/usr/bin/env bash
# Regression test (audit 2026-10-09) for bin/push_gate.py:
#  D2 `Test-approved-by:` anywhere in any commit message of the pushed range let the push through ("fix; Test-approved-by: whatever" →
#     exit 0, no receipt). Now: a real trailer `Test-approved-by: antigravity <task-id>` (git's trailer block, id T0001-name) AND an
#     antigravity-pm record of that task of THIS repository with verdicts.audit.verdict == "pass"
#     (${ANTIGRAVITY_PM_STATE_HOME:-~/.antigravity-pm}/projects/*/tasks/<id>/task.json). A missing record is named in the refusal.
#  D3 `git commit --amend` that only rewords the gated commit (same tree) was blocked (exit 2). Now it passes; an amend that changes
#     the tree is still blocked.
#  D4 a hand-written .git/postfix-gate/full_pass.json {"exit":0,"head":"<HEAD>"} let any push through. Now the fields the gate writes
#     must be there and agree with each other and with the repo (fingerprint of head+dirty, project, tests, the run-log line).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"; PG="$DEVKIT_DIR/bin/push_gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"   # never the real ~/.antigravity-pm
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
R="$TMP/repo"
expect() {   # expect <name> <exit> [text the output must contain]
  OUT="$(python3 "$PG" "$R" 2>&1)"; RC=$?
  if [ "$RC" = "$2" ] && { [ -z "${3:-}" ] || printf '%s' "$OUT" | grep -qF -- "$3"; }; then ok "$1 (exit $RC)"
  else bad "$1: exit $RC, expected $2${3:+ with \"$3\"} — $(printf '%s' "$OUT" | head -c 300)"; fi
}
newrepo() {
  rm -rf "$R" "$TMP/origin.git"; mkdir -p "$R/src" "$R/.agents" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  echo "fun ok() = 1" > src/Core.kt
  cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
  git add -A && git commit -qm init
  git init -q --bare "$TMP/origin.git" && git remote add origin "$TMP/origin.git" && git push -q -u origin HEAD 2>/dev/null
}
run_gate() { CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --run-tests --full --brief "$@" >/dev/null 2>&1; }
RCPT() { echo "$(git -C "$R" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"; }
pm_task() {   # pm_task <task-id> <audit verdict|none> <project dir>
  python3 - "$ANTIGRAVITY_PM_STATE_HOME" "$@" <<'PY'
import json, os, sys
home, tid, verdict, project = sys.argv[1:5]
d = os.path.join(home, "projects", os.path.basename(project) + "-0123456789abcdef", "tasks", tid)
os.makedirs(d, exist_ok=True)
t = {"id": tid, "project": project, "round": 0, "verdicts": {}}
if verdict != "none":
    t["verdicts"]["audit"] = {"verdict": verdict, "round": 0, "reviewer": "pm"}
json.dump(t, open(os.path.join(d, "task.json"), "w"))
PY
}

# ── D2: approval needs a real trailer AND an antigravity-pm audit pass ───────────────────────────────────────────────────
newrepo
echo "fun ok() = 2" > src/Core.kt; git commit -qam "ungated code"
expect "D2 setup: an ungated code commit is refused" 2
git commit -q --allow-empty -m "fix; Test-approved-by: whatever"
expect "D2: 'Test-approved-by:' inside a subject line is no approval" 2
git commit -q --allow-empty -m "audit" -m "Test-approved-by: antigravity T0004"
expect "D2: a trailer with a malformed task id is no approval" 2 "T0004"
git commit -q --allow-empty -m "audit" -m "Test-approved-by: antigravity T0005-fix-core"
expect "D2: a well-formed trailer with NO antigravity-pm record is refused, naming the missing record" 2 "T0005-fix-core"
pm_task T0005-fix-core fail "$R"
expect "D2: … a record whose audit verdict is fail: refused" 2
pm_task T0005-fix-core pass "$TMP/elsewhere"
expect "D2: … an audit pass recorded for ANOTHER project: refused" 2
git commit -q --allow-empty -m "note" -m "Test-approved-by: antigravity T0006-mid-body" -m "more text after it"
pm_task T0006-mid-body pass "$R"
expect "D2: a Test-approved-by line that is not in the trailer block (text follows): refused" 2
pm_task T0005-fix-core pass "$R"
expect "D2: trailer + antigravity-pm audit pass for this repository: allowed" 0

# ── D3: an amend that only rewords the gated commit (same tree) is covered; a changed tree is not ─────────────────────────
newrepo
echo "fun ok() = 2" > src/Core.kt; git commit -qam "fix"
run_gate --diff "$(git rev-parse HEAD~1)"   # the tree is clean: the gate judges the commit (a clean tree alone exits 3, no receipt)
expect "D3 setup: the gated commit itself: allowed" 0
git commit -q --amend -m "fix (reworded)"
expect "D3: amend that only rewords the gated commit (same tree): allowed" 0
echo "fun ok() = 3" > src/Core.kt; git commit -q --amend -am "fix (reworded, code changed)"
expect "D3: amend that changes the tree: refused" 2

# ── D4: a receipt must be what the gate writes, for this repository ──────────────────────────────────────────────────────
newrepo
echo "fun ok() = 2" > src/Core.kt; git commit -qam "ungated code"
mkdir -p "$(dirname "$(RCPT)")"
printf '{"exit":0,"head":"%s"}' "$(git rev-parse HEAD)" > "$(RCPT)"
expect "D4: a hand-written {exit:0, head} receipt is refused" 2
python3 - "$(RCPT)" "$(git rev-parse HEAD)" "$R" <<'PY'
import json, sys, time
json.dump({"exit": 0, "head": sys.argv[2], "dirty": {}, "project": sys.argv[3], "fingerprint": "0123456789abcdef01234567",
           "time": time.time(), "tested_at": time.time(), "result_format": 2, "gate_sha": "x", "matrix_sha": "y", "local_sha": "z",
           "tests": [{"id": "REG-1", "status": "PASS"}]}, open(sys.argv[1], "w"))
PY
expect "D4: a hand-written receipt with every field but an invented fingerprint is refused" 2 "fingerprint"
git reset -q --hard HEAD~1; echo "fun ok() = 2" > src/Core.kt; run_gate; git commit -qam "gated"
expect "D4 control: the receipt the gate really wrote: allowed" 0
cp "$(RCPT)" "$TMP/real.json"
python3 - "$(RCPT)" <<'PY'
import json, sys
r = json.load(open(sys.argv[1])); r["exit"] = False; json.dump(r, open(sys.argv[1], "w"))
PY
expect "D4: the real receipt with \"exit\": false (== 0 in Python) is refused" 2
cp "$TMP/real.json" "$(RCPT)"
python3 - "$(RCPT)" <<'PY'
import json, sys
r = json.load(open(sys.argv[1])); r["tests"][0]["status"] = "FAIL"; json.dump(r, open(sys.argv[1], "w"))
PY
expect "D4: the real receipt with a FAIL suite is refused" 2
cp "$TMP/real.json" "$(RCPT)"
python3 - "$(RCPT)" "$TMP/elsewhere" <<'PY'
import json, os, sys
os.makedirs(sys.argv[2], exist_ok=True)
r = json.load(open(sys.argv[1])); r["project"] = sys.argv[2]; json.dump(r, open(sys.argv[1], "w"))
PY
expect "D4: the real receipt naming a project outside this repository is refused" 2
cp "$TMP/real.json" "$(RCPT)"
mv "$(dirname "$(RCPT)")/runs.jsonl" "$TMP/runs.jsonl"
expect "D4: the real receipt with no matching run-log line (runs.jsonl) is refused" 2 "runs.jsonl"
mv "$TMP/runs.jsonl" "$(dirname "$(RCPT)")/runs.jsonl"
expect "D4 control: run log back: allowed again" 0

# D4 must not refuse what the gate really wrote: a deleted file, a new executable script, a file left dirty and unpushed (ponytail),
# a linked worktree (receipt in its git dir, run log in the common dir)
newrepo
echo "x" > src/Old.kt; git add src/Old.kt; git commit -qm "old file"; git push -q origin HEAD 2>/dev/null
git rm -q src/Old.kt; printf '#!/bin/sh\necho hi\n' > src/run.sh; chmod +x src/run.sh; echo "fun ok() = 2" > src/Core.kt; echo "notes" > NOTES.txt
run_gate; git add src; git commit -qm "delete + new executable + edit (NOTES.txt left dirty)"
expect "D4 compat: real receipt with a deleted file, a new executable, an unpushed dirty file: allowed" 0
git worktree add -q --detach "$TMP/wt" >/dev/null 2>&1
( cd "$TMP/wt" && echo "fun ok() = 5" > src/Core.kt && CLAUDE_PROJECT_DIR="$TMP/wt" python3 "$GATE" --run-tests --full --brief >/dev/null 2>&1 \
  && git commit -qam "worktree work" )
OUT="$(python3 "$PG" "$TMP/wt" 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "D4 compat: real receipt of a linked worktree (run log in the common dir): allowed (exit 0)" \
  || bad "D4 compat: linked worktree receipt refused: exit $RC — $(printf '%s' "$OUT" | head -c 300)"

[ "$FAILS" -eq 0 ] && echo "✅ test_push_gate_integrity: all passed" || { echo "❌ test_push_gate_integrity: $FAILS failed"; exit 1; }
