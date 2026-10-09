#!/usr/bin/env bash
# Regression test: bin/push_gate.py lets a push through only when the last full PASS of
# bin/post-fix-gate.py (receipt head + dirty blobs) covers what the push sends. Audit 2026-09-28:
# nothing enforced "every push needs the latest gate at exit 0".
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"; PG="$DEVKIT_DIR/bin/push_gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
expect() { # name expected-exit
  local out rc; out="$(python3 "$PG" "$TMP/repo" 2>&1)"; rc=$?
  [ "$rc" = "$2" ] && echo "✔ $1 (exit $rc)" || { echo "✖ $1: exit $rc, expected $2 — $out"; FAILS=$((FAILS + 1)); }
}
mkdir -p "$TMP/repo/src" "$TMP/repo/.agents" && cd "$TMP/repo" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt; echo "a" > other.txt
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
git add -A && git commit -qm init
run_gate() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --run-tests --full --brief >/dev/null 2>&1; }

echo "fun ok() = 2" > src/Core.kt
expect "no gate run yet: push blocked" 2
run_gate; expect "tested content, not committed yet: push of HEAD has nothing new" 0
git commit -qam "fix" ; expect "the tested content committed: push allowed" 0
echo "b" > other.txt; expect "another file dirty and not pushed: allowed (ponytail)" 0
echo "fun ok() = 3" > src/Core.kt; git commit -qm "after gate" -- src/Core.kt
expect "a change committed after the gate: push blocked" 2
# 2026-10-09: the line alone is something the agent writes itself; it counts only with antigravity-pm's audit pass record
# (outside the repo) for that task of this repository (tests/gates/test_push_gate_integrity.sh has the refused forms).
git commit -q --allow-empty -m "audit" -m "Test-approved-by: antigravity T0004-audit"
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"
expect "Test-approved-by with no antigravity-pm audit record: blocked" 2
mkdir -p "$TMP/pm/projects/repo-x/tasks/T0004-audit"
printf '{"id":"T0004-audit","project":"%s","verdicts":{"audit":{"verdict":"pass","round":1}}}\n' "$TMP/repo" \
  > "$TMP/pm/projects/repo-x/tasks/T0004-audit/task.json"
expect "Test-approved-by in the pushed commits, audit recorded as pass: allowed" 0
unset ANTIGRAVITY_PM_STATE_HOME
git reset -q --hard HEAD~2; git checkout -q -- . 2>/dev/null
rm -f .agents/regression_matrix.active.json; git commit -qam "no matrix"
expect "a repo without a regression matrix is not checked" 0

# 2026-09-29 (Goods-Triple-Shelf-Match-3D): a commit of .claude/settings.json only could not be
# pushed — no receipt, and the full gate REJECTed unrelated WIP in the working tree. Pushed files
# that post-fix-gate's needs_no_test() classifies as needing no test AND no matrix rule watches
# need no receipt. Code, or a watched file, still needs one.
cd "$TMP" && rm -rf "$TMP/repo" "$TMP/origin.git" && mkdir -p "$TMP/repo/src" "$TMP/repo/.agents" "$TMP/repo/.claude" && cd "$TMP/repo" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt; echo '{}' > .claude/settings.json
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
git add -A && git commit -qm init
git init -q --bare "$TMP/origin.git" && git remote add origin "$TMP/origin.git" && git push -q -u origin HEAD 2>/dev/null
echo '{"hooks":{}}' > .claude/settings.json; echo "# notes" > NOTES.md; git add -A; git commit -qm "agent config + doc"
echo "fun ok() = 9" > src/Core.kt   # unrelated failing WIP left in the tree, not pushed
expect "only agent config + a doc pushed, no receipt: allowed" 0
git commit -qam "code"
expect "a code file in the pushed range, no receipt: blocked" 2
git reset -q --hard HEAD~1
# A rename is a delete of the old path: `git diff --name-only` with rename detection named only the
# new one (review 2026-09-29), so moving watched code to docs/ looked like "a doc" and passed.
mkdir -p docs && git mv src/Core.kt docs/Core.md && git commit -qm "move code to docs"
expect "a watched code file renamed to a doc, no receipt: blocked" 2
git reset -q --hard HEAD~1
CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --run-tests --full --brief >/dev/null 2>&1
mkdir -p docs && git mv src/Core.kt docs/Core.md && git commit -qm "move code to docs after the gate"
expect "a watched code file renamed to a doc after the gate PASS: blocked" 2
git reset -q --hard HEAD~1
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]},
 {"component":"Cfg","watch_files":[".claude/settings.json"],
 "mandatory_regression_tests":[{"id":"REG-CFG","name":"config","command":"true"}]}]}
JSON
git commit -qam "a rule now watches the agent config" && git push -q origin HEAD 2>/dev/null
echo '{"hooks":{"Stop":[]}}' > .claude/settings.json; git commit -qm "config" -- .claude/settings.json
expect "the pushed config is watched by a matrix rule, no receipt: blocked" 2

# An UNTESTED full run (exit 4: a suite's untested_exit, 2026-09-29) leaves a receipt with
# "exit": 4 (its PASS suites are reused by the next run) — never the exit 0 a push needs.
cd "$TMP" && rm -rf "$TMP/repo" "$TMP/origin.git" && mkdir -p "$TMP/repo/src" "$TMP/repo/.agents" && cd "$TMP/repo" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"},
  {"id":"REG-CAR","name":"real car","command":"exit 2","untested_exit":2}]}]}
JSON
git add -A && git commit -qm init
git init -q --bare "$TMP/origin.git" && git remote add origin "$TMP/origin.git" && git push -q -u origin HEAD 2>/dev/null
echo "fun ok() = 2" > src/Core.kt
CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --run-tests --full --brief >/dev/null 2>&1; g=$?
git commit -qam "fix"
rexit="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("exit"))' "$(git rev-parse --absolute-git-dir)/postfix-gate/full_pass.json" 2>/dev/null)"
[ "$g" = 4 ] && [ "$rexit" = 4 ] && echo "✔ setup: --full UNTESTED wrote an exit-4 receipt" \
  || { echo "✖ setup: gate exit $g, receipt exit '$rexit'"; FAILS=$((FAILS + 1)); }
expect "an exit-4 (UNTESTED) receipt covering the pushed code: push blocked" 2

[ "$FAILS" -eq 0 ] && echo "push gate: all checks passed" || { echo "push gate: $FAILS FAILED"; exit 1; }
