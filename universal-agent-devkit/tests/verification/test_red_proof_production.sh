#!/usr/bin/env bash
# Regression test: scripts/testing/red_proof.py, "production" in .agents/local/red_proof.json (14/10, docs/issues-bugs.md A.4).
# TEST_PATH reads every file under tests/ as a test, and a proof never changes a test. A runner that lives under tests/ but is
# production code (agent-workbench: universal-agent-devkit/tests/run_impacted.sh, the command of REG-DK-ALL-01, exercised by
# test_run_impacted*.sh) could therefore never prove a bug fixed in it: its bug-back --patch was refused ("patch sửa file test"),
# its uncommitted fix was no fix in session mode, and a commit that changed only it was no fix commit for --pending.
# "production": [globs] declares such files production code in all three; a bug's own linked test stays a test whatever the globs
# say; anything but a list of non-empty strings (or an unreadable file) counts as no declaration, never a crash.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROOF="${RED_PROOF_UNDER_TEST:-$DEVKIT_DIR/scripts/testing/red_proof.py}"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# The production runner under tests/: `--all` must print "all". Its test runs it.
RUNNER_FIXED='[ "$1" = --all ] && echo all || echo some'
RUNNER_BUGGY='echo some'
TEST_RUNNER='import os, subprocess, unittest
HERE = os.path.dirname(os.path.abspath(__file__))
class TestRunner(unittest.TestCase):
    def test_all(self):
        out = subprocess.run(["sh", os.path.join(HERE, "runner.sh"), "--all"], capture_output=True, text=True).stdout.strip()
        self.assertEqual(out, "all")
'
UT="python3 -m unittest discover -s tests"
new_project() {  # a matrix suite that runs the unittest discovery; nothing committed yet
  P="$TMP/p$RANDOM"; mkdir -p "$P/tests" "$P/.agents"
  ( cd "$P" && git init -q . && git config user.email t@t && git config user.name t
    python3 -c 'import json,sys; json.dump({"adopted": True, "rules": [{"component": "Runner", "watch_files": ["tests/*"],
      "mandatory_regression_tests": [{"id": "REG-RUN", "name": "runner", "command": sys.argv[1]}]}]},
      open(".agents/regression_matrix.active.json", "w"))' "$UT"
    printf '.env\n' > .gitignore )
  cd "$P" || exit 1
}
declare_prod() { mkdir -p "$P/.agents/local"; printf '%s' "$1" > "$P/.agents/local/red_proof.json"; }
bid() { printf '%s' "$1" | grep -o 'BUG-[A-Za-z0-9_-]*' | head -1; }
add_bug() { bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "$@" --fixed 2>&1)"; }
field() { python3 -c "import json,sys;print((json.load(open('$P/.agents/regression_status.json'))['items'][sys.argv[1]].get('red_proof') or {}).get(sys.argv[2],'-'))" "$1" "$2"; }
forget() { python3 -c "import json,sys;p='$P/.agents/regression_status.json';d=json.load(open(p));d['items'][sys.argv[1]].pop('red_proof',None);json.dump(d,open(p,'w'))" "$1"; }

# ── --patch: a bug-back patch of the runner ──────────────────────────────────────────────────────
new_project
printf '%s\n' "$RUNNER_FIXED" > tests/runner.sh; printf '%s' "$TEST_RUNNER" > tests/test_runner.py
git add -A && git commit -qm "runner --all + its test"
printf '%s\n' "$RUNNER_BUGGY" > tests/runner.sh; git diff > "$TMP/runner-back.patch"; git checkout -q tests/runner.sh
B1="$(add_bug "runner --all bỏ qua" --test tests/test_runner.py)"
python3 "$PROOF" "$P" --bug "$B1" --patch "$TMP/runner-back.patch" --wait >/dev/null 2>&1
[ "$(field "$B1" status)" = INCONCLUSIVE ] && field "$B1" reason | grep -q "file test" \
  && ok "no declaration: a bug-back patch of a runner under tests/ edits a test → INCONCLUSIVE (as before)" \
  || fail "undeclared runner patch: $(field "$B1" status) $(field "$B1" reason)"
declare_prod '{"production": ["tests/runner.sh"]}'
python3 "$PROOF" "$P" --bug "$B1" --patch "$TMP/runner-back.patch" --wait >/dev/null 2>&1
[ "$(field "$B1" status)" = PROVEN ] \
  && ok "declared production: the runner's bug-back patch applies → its test RED, HEAD GREEN → PROVEN" \
  || fail "declared runner patch: $(field "$B1" status) $(field "$B1" reason)"

# A glob that also takes in the bug's linked test never makes that test production: a patch editing it is still refused,
# and only for the test (the runner it also matches is no test edit any more).
declare_prod '{"production": ["tests/*"]}'
printf '%s\n' "$RUNNER_BUGGY" > tests/runner.sh; printf '# weakened\n' >> tests/test_runner.py
git diff > "$TMP/both.patch"; git checkout -q tests/runner.sh tests/test_runner.py
B2="$(add_bug "runner + test sửa" --test tests/test_runner.py)"
python3 "$PROOF" "$P" --bug "$B2" --patch "$TMP/both.patch" --wait >/dev/null 2>&1
r2="$(field "$B2" reason)"
[ "$(field "$B2" status)" = INCONCLUSIVE ] && printf '%s' "$r2" | grep -q "tests/test_runner.py" && ! printf '%s' "$r2" | grep -q "tests/runner.sh" \
  && ok "a glob matching the linked test too: the patch that edits that test is refused for the test alone" \
  || fail "linked test declared production: $(field "$B2" status) $r2"

# Malformed declarations are no declaration: never a crash, the runner stays a test.
for cfg in '{"production": "tests/runner.sh"}' '{"production": [1, "", null]}' '["tests/runner.sh"]' '{"production": '; do
  declare_prod "$cfg"
  out="$(python3 "$PROOF" "$P" --bug "$B1" --patch "$TMP/runner-back.patch" --wait 2>&1)"; rc=$?
  { [ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q Traceback && [ "$(field "$B1" status)" = INCONCLUSIVE ] \
      && field "$B1" reason | grep -q "file test"; } \
    && ok "malformed red_proof.json ($cfg): ignored, no crash, the runner stays a test" \
    || fail "malformed ($cfg): rc=$rc $(field "$B1" status) $(field "$B1" reason) $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
done

# ── session mode: the runner fix is uncommitted, its test new ────────────────────────────────────
new_project
printf '%s\n' "$RUNNER_BUGGY" > tests/runner.sh; git add -A && git commit -qm "runner without --all"
printf '%s\n' "$RUNNER_FIXED" > tests/runner.sh; printf '%s' "$TEST_RUNNER" > tests/test_runner.py
B3="$(add_bug "runner --all (phiên này)" --test tests/test_runner.py)"
python3 "$PROOF" "$P" --bug "$B3" --wait >/dev/null 2>&1
[ "$(field "$B3" status)" = INCONCLUSIVE ] && field "$B3" reason | grep -q "chưa commit" \
  && ok "no declaration: an uncommitted fix of a runner under tests/ is no fix in session mode (as before)" \
  || fail "undeclared session fix: $(field "$B3" status) $(field "$B3" reason)"
declare_prod '{"production": ["tests/runner.sh"]}'
python3 "$PROOF" "$P" --bug "$B3" --wait >/dev/null 2>&1
[ "$(field "$B3" status)" = PROVEN ] && [ "$(field "$B3" mode)" = session ] \
  && ok "declared production: the uncommitted runner change is the session's fix → PROVEN" \
  || fail "declared session fix: $(field "$B3" status)/$(field "$B3" mode) $(field "$B3" reason)"
grep -q -- "--all" tests/runner.sh && ok "session proof leaves the working tree as it was" || fail "the working tree lost the fix"

# ── --pending: the fix commit named in the evidence changed only a production file under tests/ ──
TOOL_TEST='import os, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tool
class TestTool(unittest.TestCase):
    def test_all(self):
        self.assertEqual(tool.mode(["--all"]), "all")
'
new_project
printf 'def mode(args):\n    return "some"\n' > tests/tool.py; git add -A && git commit -qm "tool"
printf 'def mode(args):\n    return "all" if "--all" in args else "some"\n' > tests/tool.py; printf '%s' "$TOOL_TEST" > tests/test_tool.py
git add -A && git commit -qm "tool --all + its test"; FIX="$(git rev-parse --short HEAD)"
B4="$(add_bug "tool --all bỏ qua" --test tests/test_tool.py --evidence "fixed in $FIX")"
python3 "$PROOF" "$P" --pending --wait >/dev/null 2>&1
[ "$(field "$B4" status)" = INCONCLUSIVE ] && field "$B4" reason | grep -q "commit fix" \
  && ok "no declaration: a commit that changed only tests/ files is no fix commit (as before)" \
  || fail "undeclared fix commit: $(field "$B4" status) $(field "$B4" reason)"
declare_prod '{"production": ["tests/tool.py"]}'; forget "$B4"
python3 "$PROOF" "$P" --pending --wait >/dev/null 2>&1
[ "$(field "$B4" status)" = PROVEN ] && [ "$(field "$B4" mode)" = revert ] && [ "$(field "$B4" fix_commit)" = "$FIX" ] \
  && ok "declared production: the evidence's commit is the fix, its production file reverted → PROVEN" \
  || fail "declared fix commit: $(field "$B4" status)/$(field "$B4" mode)/$(field "$B4" fix_commit) $(field "$B4" reason)"

[ "$FAILS" -eq 0 ] && echo "✅ test_red_proof_production: all passed" || { echo "❌ test_red_proof_production: $FAILS failed"; exit 1; }
