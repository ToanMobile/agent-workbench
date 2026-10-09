#!/usr/bin/env bash
# Regression test: holes in what bin/post-fix-gate.py audits (audit 2026-10-09, each reproduced on a throwaway repo).
#  A1  --since: committed work was compared with HEAD for the static checks, so an AWS key and a
#      `# ... existing code ...` placeholder committed in <since>..HEAD were "already in HEAD": exit 0, receipt written.
#  A2  a runner script a base-ref suite command runs (`sh scripts/check.sh`) could be edited to `exit 0`: exit 0.
#  A4  removing a committed forbidden file (`git rm --cached .env`, a deleted key) was itself a finding: the
#      remediation commit was blocked by --staged (exit 1) and --full (exit 1).
#  A5  the secret scan skipped .agents/{archive,evidence,context}/ and .claude/audit-gate/: a key there was exit 3.
#  A6  an appended test that REDEFINES an existing one (shadowing it) counted as append-only: exit 0.
#  A7  a suite that printed run_impacted.sh's own failure line (`✖ tests/x.sh`), then passed on the re-run, was
#      recorded PASS (infra_retry) instead of FLAKY (still FAIL).
#  A11 `git diff --name-only` without -z quoted a non-ASCII path (src/cfg_é.py): --since never audited it.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# Fresh repo per scenario: src/core.py, a passing suite, a matrix watching src/ tests/ scripts/.
mk() {
  local d="$TMP/$1"
  mkdir -p "$d/src" "$d/tests" "$d/scripts" && cd "$d" || exit 1
  git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf 'def f():\n    return 1\n' > src/core.py
  printf '#!/bin/sh\ngrep -q return src/core.py\n' > tests/test_core.sh
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*","scripts/*",".env",".gitignore","secrets/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/test_core.sh"}]}]}
JSON
  git add -A && git commit -qm init
}
# gate [args...]: the JSON summary line in $OUT, the exit code in $RC
gate() {
  OUT="$(CLAUDE_PROJECT_DIR="$PWD" POSTFIX_GATE_FORCE_FULL=1 FLAKY_RETRY_MAX_S=60 python3 "$GATE" --matrix "$PWD/matrix.json" \
         --lang en --json "$@" 2>&1)"; RC=$?
  JSON="$(printf '%s\n' "$OUT" | grep '^{' | tail -1)"
}
# j <python expression over d>: a field of the last JSON summary
j() { printf '%s' "$JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1" 2>/dev/null; }
expect_rc() {  # expect_rc <name> <want>
  if [ "$RC" = "$2" ]; then ok "$1 (exit $RC)"
  else bad "$1: exit $RC, want $2"; printf '%s\n' "$OUT" | grep -v '^{' | grep -E '✖|VERDICT|Traceback|Error' | head -8; fi
}

# ── A1: --since audits the committed content against <since>, not against HEAD ──────────────────────────────
mk since_secret; base="$(git rev-parse HEAD)"
printf 'KEY = "AKIA%s"\n' ABCDEFGHIJKLMNOP > src/cfg.py && git add -A && git commit -qm "add cfg"
printf 'def g():\n    # ... existing code ...\n    return 2\n' > src/core2.py && git add -A && git commit -qm "add core2"
gate --run-tests --full --since "$base"
expect_rc "A1: a key and a placeholder committed in <since>..HEAD are REJECTed" 1
[ "$(j 'd["static"]["secrets"]')" -ge 1 ] 2>/dev/null && ok "A1: the committed AWS key is a finding" \
  || bad "A1: the committed AWS key is not a finding (static: $(j 'd["static"]'))"
[ "$(j 'd["static"]["lazy"]')" -ge 1 ] 2>/dev/null && ok "A1: the committed placeholder is a finding" \
  || bad "A1: the committed placeholder is not a finding (static: $(j 'd["static"]'))"
[ ! -f .git/postfix-gate/full_pass.json ] && ok "A1: no full-pass receipt for the rejected range" \
  || bad "A1: a full-pass receipt was written for a range holding a key"

mk since_preexisting
printf 'KEY = "AKIA%s"\n' ABCDEFGHIJKLMNOP > src/cfg.py && git add -A && git commit -qm "old key"; base="$(git rev-parse HEAD)"
printf 'KEY = "AKIA%s"\nX = 1\n' ABCDEFGHIJKLMNOP > src/cfg.py && git commit -qam "touch cfg"
gate --run-tests --full --since "$base"
expect_rc "A1 control: a key already at <since> stays a warning, not a block" 0

mk since_clean; base="$(git rev-parse HEAD)"
printf 'def f():\n    return 2\n' > src/core.py && git commit -qam "clean fix"
gate --run-tests --full --since "$base"
expect_rc "A1 control: a clean committed fix passes under --since" 0

# A teammate's commit already on the upstream, pulled into the range, passed its own gate (as since_test_weakened):
# it is not this session's to block on; the same content committed locally is.
mk since_upstream; base="$(git rev-parse HEAD)"
br="$(git rev-parse --abbrev-ref HEAD)"
git init -q --bare -b "$br" "$TMP/remote.git" && git remote add origin "$TMP/remote.git" && git push -q -u origin "HEAD:$br" 2>/dev/null
git clone -q "$TMP/remote.git" "$TMP/mate" && (cd "$TMP/mate" && git config user.email m@m && git config user.name m \
  && git config commit.gpgsign false && printf 'def h():\n    # ... existing code ...\n    return 3\n' > src/mate.py \
  && git add -A && git commit -qm "mate" && git push -q origin HEAD 2>/dev/null)
git pull -q --no-rebase origin "$br" 2>/dev/null
printf 'def f():\n    return 2\n' > src/core.py && git commit -qam "my clean fix"
gate --run-tests --full --since "$base"
expect_rc "A1 control: a placeholder in a teammate's pulled-in commit does not block this session" 0

# ── A11: a non-ASCII path committed in the range is audited (-z, not a quoted name) ───────────────────────────
mk since_utf8; base="$(git rev-parse HEAD)"
printf 'KEY = "AKIA%s"\n' ABCDEFGHIJKLMNOP > "src/cfg_é.py" && git add -A && git commit -qm "add cfg_é"
gate --since "$base"
if [ "$(j '"src/cfg_é.py" in d["files"]')" = "True" ]; then ok "A11: src/cfg_é.py from the --since range is in the audited files"
else bad "A11: src/cfg_é.py from the --since range was dropped (files: $(j 'd["files"]'))"; fi

# ── A2: a runner script the base-ref suite command runs counts like an edited existing test ───────────────────
mk runner
printf '#!/bin/sh\nsh scripts/check.sh\n' > scripts/ci.sh
# set -e: a runner that stops at its first failure still accepts a pure append (a runner without it does not: tests/gates/test_gate_runner_no_errexit.sh)
printf '#!/bin/sh\nset -e\ngrep -q "return 1" src/core.py\n' > scripts/check.sh
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","scripts/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh scripts/check.sh"}]},
 {"component":"CI","watch_files":["ci/*"],"mandatory_regression_tests":[{"id":"REG-CI","name":"ci","command":"./scripts/ci.sh"}]}]}
JSON
git add -A && git commit -qm runner
printf 'def f():\n    return 2\n' > src/core.py
printf '#!/bin/sh\nexit 0\n' > scripts/check.sh
gate --run-tests --full
expect_rc "A2: scripts/check.sh (named by the suite command) set to 'exit 0' is not a PASS" 2
[ "$(j '"scripts/check.sh" in d["tests_touched"]')" = "True" ] && ok "A2: scripts/check.sh is reported as an edited suite runner" \
  || bad "A2: scripts/check.sh not reported (tests_touched: $(j 'd["tests_touched"]'))"
gate --run-tests --full --auto-approve-tests
expect_rc "A2: the existing approval path (--auto-approve-tests) still lifts it" 0
git checkout -q -- scripts/check.sh
printf '#!/bin/sh\ntrue\n' > scripts/ci.sh
gate --dry-run
[ "$(j '"scripts/ci.sh" in d["tests_touched"]')" = "True" ] && ok "A2: ./scripts/ci.sh (a ./ command) is protected too" \
  || bad "A2: ./scripts/ci.sh edit not reported (tests_touched: $(j 'd["tests_touched"]'))"
git checkout -q -- scripts/ci.sh
printf 'exit 0\n' >> scripts/check.sh
gate --dry-run
[ "$(j '"scripts/check.sh" in d["tests_touched"]')" = "True" ] && ok "A2: an appended 'exit 0' (forces the status green) is an edit" \
  || bad "A2: an appended 'exit 0' counted as a pure append (tests_touched: $(j 'd["tests_touched"]'))"
git checkout -q -- scripts/check.sh
printf 'grep -q def src/core.py\n' >> scripts/check.sh
printf 'def f():\n    return 1\n# note\n' > src/core.py
gate --run-tests --full
expect_rc "A2 control: a runner that only gains one more check (a pure append), with a passing change, is PASS" 0
git checkout -q -- scripts/check.sh
gate --run-tests --full
expect_rc "A2 control: an unchanged runner and a passing change is PASS" 0

mk runner_depth2
printf '#!/bin/sh\nsh scripts/check.sh\n' > scripts/ci.sh
printf '#!/bin/sh\ngrep -q "return 1" src/core.py\n' > scripts/check.sh
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","scripts/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"bash scripts/ci.sh"}]}]}
JSON
git add -A && git commit -qm runner
printf '#!/bin/sh\nexit 0\n' > scripts/check.sh
gate --dry-run
[ "$(j '"scripts/check.sh" in d["tests_touched"]')" = "True" ] && ok "A2: a script the named runner calls (depth 2) is protected" \
  || bad "A2: scripts/check.sh called by scripts/ci.sh not reported (tests_touched: $(j 'd["tests_touched"]'))"

# ── A4: deleting / untracking a committed forbidden file is never a finding ──────────────────────────────────
mk rm_env
printf 'FOO=bar\n' > .env && mkdir -p secrets && printf 'k\n' > secrets/id_rsa && git add -A && git commit -qm "oops"
git rm -q --cached .env && printf '.env\n' > .gitignore && git add .gitignore && git rm -q secrets/id_rsa
gate --staged
expect_rc "A4: --staged on the remediation commit (git rm --cached .env, rm id_rsa) is not REJECTed" 2
gate --run-tests --full
expect_rc "A4: --full on the same tree is not REJECTed" 0
printf 'FOO=baz\n' > cfg.env && git add cfg.env
gate --staged
expect_rc "A4 control: adding a .env file is still REJECTed" 1
git rm -q --cached cfg.env && rm cfg.env && git rm -q --cached .gitignore && rm .gitignore
gate --run-tests --full
expect_rc "A4 control: an untracked, unignored .env left in the tree is still a finding for --full" 1

# ── A5: secrets are scanned in the DevKit state folders too ───────────────────────────────────────────────────
mk state_dirs
mkdir -p .agents/archive .claude/audit-gate .agents/evidence/REG-1 .agents/context
printf 'K=AKIA%s\n' ABCDEFGHIJKLMNOP > .agents/archive/.env && git add -f .agents/archive/.env
gate --staged
expect_rc "A5: a key in a staged .agents/archive/.env is REJECTed" 1
git rm -q --cached .agents/archive/.env
printf 'token: "AKIA%s"\n' ABCDEFGHIJKLMNOP > .claude/audit-gate/run.log && git add -f .claude/audit-gate/run.log
gate --staged
expect_rc "A5: a key in a staged .claude/audit-gate/run.log is REJECTed" 1
git rm -q --cached .claude/audit-gate/run.log
printf 'notes\n' > .agents/context/notes.md && git add -f .agents/context/notes.md
gate --staged
expect_rc "A5 control: a clean staged .agents/context file is still nothing to audit" 3
git commit -qm notes
printf 'log\n' > .agents/evidence/REG-1/x.log && git add -f .agents/evidence/REG-1/x.log && git commit -qm ev
printf 'log ghp_%s\n' abcdefghijklmnopqrstuvwxyz0123456789AB > .agents/evidence/REG-1/x.log
gate --run-tests --full
expect_rc "A5: a key written into a tracked .agents/evidence log is REJECTed by --full" 1

# ── A6: an appended definition that redefines an existing test is an edit ─────────────────────────────────────
mk shadow
touch src/__init__.py tests/__init__.py
printf 'def sub(a, b):\n    return a - b\n' > src/calc.py
cat > tests/test_calc.py <<'EOF'
import unittest
from src.calc import sub


class T(unittest.TestCase):
    def test_sub(self):
        self.assertEqual(sub(3, 1), 2)
EOF
mkdir -p app/src/test/kotlin web
printf 'class FooTest {\n    @Test\n    fun adds() { assertEquals(2, add(1, 1)) }\n}\n' > app/src/test/kotlin/FooTest.kt
printf "it('adds', () => { expect(add(1, 1)).toBe(2) })\n" > web/add.test.js
printf '#!/bin/sh\ncheck() { [ "$(cat src/calc.py | wc -l)" -gt 0 ]; }\ncheck\n' > tests/test_calc.sh
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*","app/*","web/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"python3 -m unittest -q tests.test_calc"}]}]}
JSON
git add -A && git commit -qm init2
printf 'def sub(a, b):\n    return a + b\n' > src/calc.py
printf '\n    def test_sub(self):\n        self.assertIsNotNone(sub)\n' >> tests/test_calc.py
gate --run-tests --full
expect_rc "A6: python 'def test_sub' appended over the existing test_sub is not a PASS" 2
[ "$(j '"tests/test_calc.py" in d["tests_touched"]')" = "True" ] && ok "A6: the shadowing python test is an edited test" \
  || bad "A6: the shadowing python test is not an edited test (tests_touched: $(j 'd["tests_touched"]'))"
printf '    @Test\n    fun adds() { assertTrue(true) }\n' >> app/src/test/kotlin/FooTest.kt
printf "it('adds', () => { expect(true).toBe(true) })\n" >> web/add.test.js
printf 'check() { true; }\n' >> tests/test_calc.sh
gate --dry-run
for f in app/src/test/kotlin/FooTest.kt web/add.test.js tests/test_calc.sh; do
  [ "$(j "\"$f\" in d[\"tests_touched\"]")" = "True" ] && ok "A6: a redefinition appended to $f is an edit" \
    || bad "A6: a redefinition appended to $f counted as append-only (tests_touched: $(j 'd["tests_touched"]'))"
done
git checkout -q -- tests app web
printf 'def sub(a, b):\n    return a - b\n' > src/calc.py
printf '\n    def test_sub_zero(self):\n        self.assertEqual(sub(1, 1), 0)\n' >> tests/test_calc.py
printf "it('adds zero', () => { expect(add(1, 0)).toBe(1) })\n" >> web/add.test.js
gate --run-tests --full
expect_rc "A6 control: appending NEW test names stays append-only (PASS)" 0

# ── A7: `✖ tests/x.sh` is a test failure: fail then pass on the re-run is FLAKY (FAIL), not an infra PASS ─────────
mk flaky
cat > tests/run.sh <<EOF
#!/bin/sh
if [ ! -f "$TMP/flaky.flag" ]; then : > "$TMP/flaky.flag"; echo "✖ tests/test_x.sh"; exit 1; fi
echo "✔ tests/test_x.sh"
EOF
sed 's#"command":"sh tests/test_core.sh"#"command":"sh tests/run.sh"#' matrix.json > m.tmp && mv m.tmp matrix.json
git add -A && git commit -qm runner
printf 'def f():\n    return 2\n' > src/core.py
gate --run-tests --full
expect_rc "A7: a suite whose first run printed '✖ tests/test_x.sh' is not a PASS" 1
[ "$(j 'd["regression_tests"][0].get("flaky")')" = "True" ] && ok "A7: it is recorded FLAKY" \
  || bad "A7: not recorded FLAKY (status $(j 'd["regression_tests"][0]["status"]'), infra_retry $(j 'd["regression_tests"][0].get("infra_retry")'))"
rm -f "$TMP/flaky.flag"
cat > tests/run.sh <<EOF
#!/bin/sh
if [ ! -f "$TMP/flaky.flag" ]; then : > "$TMP/flaky.flag"; echo "daemon disappeared unexpectedly"; exit 1; fi
echo "ok"
EOF
gate --run-tests --full
[ "$(j 'd["regression_tests"][0]["status"]')/$(j 'd["regression_tests"][0].get("infra_retry")')" = "PASS/True" ] \
  && ok "A7 control: a broken build (no test failing) then green stays PASS flagged infra_retry" \
  || bad "A7 control: status $(j 'd["regression_tests"][0]["status"]') infra_retry $(j 'd["regression_tests"][0].get("infra_retry")')"

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_audit_holes: all tests passed" || { echo "❌ test_gate_audit_holes: $FAILS failed"; exit 1; }
