#!/usr/bin/env bash
# Regression test: scripts/red_proof.py — a bug's test must be seen RED on the unfixed code.
# Two runs in one sandbox (a copy of the base tree, never the working tree):
#   RED run   = base code + the test          → must fail, and the output must name the test
#   GREEN run = base code + the test + the fix → must pass (control: the sandbox works)
# RED+GREEN → PROVEN; GREEN+GREEN → VACUOUS (🚫 test vô hiệu); anything else → INCONCLUSIVE.
#  - session mode: base = HEAD, fix = the uncommitted source changes; no uncommitted fix → INCONCLUSIVE
#  - --fix-commit <sha>: base = HEAD with that commit reverted (past bugs)
#  - heavy suites (Gradle/Unity) wait for --heavy (nightly); a broken sandbox is never a proof
#  - a bug whose suite passed is PASS only once PROVEN; before that ⏳ UNPROVEN; VACUOUS shows apart
#  - Stop: a proven fix starts the proof of this session's bugs in the background, and a bug of
#    this session whose test is VACUOUS holds the stop
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"; PROOF="$DEVKIT_DIR/scripts/red_proof.py"; KIT="$DEVKIT_DIR/bin/agent-kit"
STOP_GATE="$DEVKIT_DIR/hooks/test_evidence_gate.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TEST_ADD='import os, sys, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
import calc
class TestAdd(unittest.TestCase):
    def test_add(self):
        self.assertEqual(calc.add(2, 2), 4)
'
TEST_VACUOUS='import os, sys, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
import calc
class TestNothing(unittest.TestCase):
    def test_nothing(self):
        self.assertTrue(callable(calc.add))
'
new_project() {  # new_project <command>
  P="$TMP/p$RANDOM"; mkdir -p "$P/src" "$P/tests" "$P/.agents"
  ( cd "$P" && git init -q . && git config user.email t@t && git config user.name t
    printf 'def add(a, b):\n    return a - b\n' > src/calc.py
    python3 -c 'import json,sys; json.dump({"adopted": True, "rules": [{"component": "Calc", "watch_files": ["src/*.py", "tests/*.py"],
      "mandatory_regression_tests": [{"id": "REG-CALC", "name": "calc", "command": sys.argv[1]}]}]},
      open(".agents/regression_matrix.active.json", "w"))' "$1"
    printf '.env\n' > .gitignore
    git add -A && git commit -qm init )
}
st() { python3 -c "
import sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r, pathlib
d=r.load(pathlib.Path('$P')); print(r.effective_status(d, d['items']['$1']))"; }
proof() { python3 -c "import json;print((json.load(open('$P/.agents/regression_status.json'))['items']['$1'].get('red_proof') or {}).get('status','-'))"; }
bid() { printf '%s' "$1" | grep -o 'BUG-[A-Za-z0-9_-]*' | head -1; }
UT="python3 -m unittest discover -s tests"

# ── session mode: fix uncommitted, test new ─────────────────────────────────
new_project "$UT"; cd "$P"
printf 'def add(a, b):\n    return a + b\n' > src/calc.py
printf '%s' "$TEST_ADD" > tests/test_calc.py
B1="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add trừ thay vì cộng" --fixed --test tests/test_calc.py 2>&1)")"
CLAUDE_PROJECT_DIR="$P" python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1
[ "$(st "$B1")" = UNPROVEN ] && ok "suite PASS but the test never seen RED → UNPROVEN, not PASS" || fail "before proof: $(st "$B1")"
python3 "$PROOF" "$P" --bug "$B1" --wait >/dev/null 2>&1
[ "$(proof "$B1")" = PROVEN ] && [ "$(st "$B1")" = PASS ] && ok "RED without the fix + GREEN with it → PROVEN → PASS" \
  || fail "proven: proof=$(proof "$B1") st=$(st "$B1")"
log="$(python3 -c "import json;print(json.load(open('$P/.agents/regression_status.json'))['items']['$B1']['red_proof'].get('log',''))")"
[ -n "$log" ] && grep -q "RED run" "$P/$log" && grep -q "GREEN run" "$P/$log" && ok "proof log keeps both sandbox runs" || fail "log: $log"
git -C "$P" status --porcelain | grep -q "src/calc.py" && grep -q "a + b" src/calc.py && ok "working tree untouched (the fix is still there)" || fail "working tree changed"

printf '%s' "$TEST_VACUOUS" > tests/test_vacuous.py
B2="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "test không bắt gì" --fixed --test tests/test_vacuous.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B2" --wait >/dev/null 2>&1
[ "$(proof "$B2")" = VACUOUS ] && [ "$(st "$B2")" = VACUOUS ] && ok "GREEN without the fix too → VACUOUS (🚫 test vô hiệu)" \
  || fail "vacuous: proof=$(proof "$B2") st=$(st "$B2")"
grep -q "TEST VÔ HIỆU" .agents/regression_checklist.md && ok "view shows 🚫 TEST VÔ HIỆU" || fail "view"

# ── Stop: VACUOUS bug of this session holds the stop ────────────────────────
python3 - "$P" "$B2" <<'PY'
import json, sys
p = sys.argv[1] + "/.agents/regression_status.json"; d = json.load(open(p))
d["items"][sys.argv[2]]["sessions"] = ["sv"]; json.dump(d, open(p, "w"))
PY
python3 - "$P/tr.jsonl" "$P/src/calc.py" <<'PY'
import json, sys
out, src = sys.argv[1], sys.argv[2]
steps = [("Bash", {"command": "python3 -m pytest tests"}, "FAILED tests/test_calc.py::test_add\n1 failed", True),
         ("Edit", {"file_path": src, "old_string": "-", "new_string": "+"}, "ok", False),
         ("Bash", {"command": "python3 -m pytest tests"}, "2 passed in 0.01s", False)]
lines = []
for i, (name, inp, res, err) in enumerate(steps):
    lines.append(json.dumps({"message": {"content": [{"type": "tool_use", "id": f"t{i}", "name": name, "input": inp}]}}))
    lines.append(json.dumps({"message": {"content": [{"type": "tool_result", "tool_use_id": f"t{i}", "content": res, "is_error": err}]}}))
open(out, "w").write("\n".join(lines) + "\n")
PY
err="$(python3 -c 'import json,sys; print(json.dumps({"session_id": "sv", "transcript_path": sys.argv[1], "last_assistant_message": "Đã fix lỗi add, test RED→GREEN."}))' "$P/tr.jsonl" \
       | CLAUDE_PROJECT_DIR="$P" LESSON_REMINDER=0 RED_PROOF=0 bash "$STOP_GATE" 2>&1 >/dev/null)"; rc=$?
[ $rc = 2 ] && printf '%s' "$err" | grep -q "TEST VÔ HIỆU" && printf '%s' "$err" | grep -q "$B2" \
  && ok "Stop: a bug of this session whose test is VACUOUS holds the stop" || fail "stop vacuous: rc=$rc $err"

# ── Stop starts the proof in the background ─────────────────────────────────
printf 'def add(a, b):\n    return a - b\n' > src/calc.py; rm -f tests/test_vacuous.py
python3 - "$P" "$B1" "$B2" <<'PY'
import json, sys
p = sys.argv[1] + "/.agents/regression_status.json"; d = json.load(open(p))
d["items"].pop(sys.argv[3], None)
it = d["items"][sys.argv[2]]; it.pop("red_proof", None); it["sessions"] = ["sb"]; json.dump(d, open(p, "w"))
PY
printf 'def add(a, b):\n    return a + b\n' > src/calc.py
python3 -c 'import json,sys; print(json.dumps({"session_id": "sb", "transcript_path": sys.argv[1], "last_assistant_message": "Đã fix lỗi add, test RED→GREEN."}))' "$P/tr.jsonl" \
  | CLAUDE_PROJECT_DIR="$P" LESSON_REMINDER=0 bash "$STOP_GATE" >/dev/null 2>&1
for _ in $(seq 1 40); do [ "$(proof "$B1")" = PROVEN ] && break; sleep 0.3; done
[ "$(proof "$B1")" = PROVEN ] && ok "Stop after a proven fix starts the RED-proof of this session's bugs (background)" || fail "background proof: $(proof "$B1")"

# ── fix already committed: no uncommitted fix → INCONCLUSIVE; --fix-commit reverts it ─
new_project "$UT"; cd "$P"
printf 'def add(a, b):\n    return a + b\n' > src/calc.py; printf '%s' "$TEST_ADD" > tests/test_calc.py
git add -A && git commit -qm "fix add"; FIX="$(git rev-parse --short HEAD)"
B3="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add sai (cũ)" --fixed --test tests/test_calc.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B3" --wait >/dev/null 2>&1
[ "$(proof "$B3")" = INCONCLUSIVE ] && ok "fix already committed, commit unknown → INCONCLUSIVE (never a guess)" || fail "committed: $(proof "$B3")"
python3 "$PROOF" "$P" --bug "$B3" --fix-commit "$FIX" --wait >/dev/null 2>&1
[ "$(proof "$B3")" = PROVEN ] && ok "--fix-commit: revert the fix in the sandbox → RED, HEAD → GREEN → PROVEN" || fail "revert: $(proof "$B3")"

# ── broken sandbox (needs an ignored local file nobody declared) → INCONCLUSIVE, never PROVEN ─
new_project "test -f secret.local && $UT"; cd "$P"; printf 'secret.local\n' >> .gitignore; git commit -qam ign; touch secret.local
printf 'def add(a, b):\n    return a + b\n' > src/calc.py; printf '%s' "$TEST_ADD" > tests/test_calc.py
B4="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add sai env" --fixed --test tests/test_calc.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B4" --wait >/dev/null 2>&1
[ "$(proof "$B4")" = INCONCLUSIVE ] && ok "sandbox cannot run the suite (GREEN run fails) → INCONCLUSIVE" || fail "env: $(proof "$B4")"

# …declared in .agents/local/red_proof.json → copied into the sandbox (never written back) → PROVEN
mkdir -p .agents/local && printf '{"copy": ["secret.local"]}' > .agents/local/red_proof.json
python3 "$PROOF" "$P" --bug "$B4" --wait >/dev/null 2>&1
[ "$(proof "$B4")" = PROVEN ] && ok "ignored build input declared in .agents/local/red_proof.json → copied in → PROVEN" || fail "copy: $(proof "$B4")"
# well-known ignored build inputs (local.properties, google-services.json, libs/*.aar, .env…) are copied by default
new_project "test -f local.properties && $UT"; cd "$P"; printf 'local.properties\n' >> .gitignore; git commit -qam ign; touch local.properties
printf 'def add(a, b):\n    return a + b\n' > src/calc.py; printf '%s' "$TEST_ADD" > tests/test_calc.py
B6="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add sai lp" --fixed --test tests/test_calc.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B6" --wait >/dev/null 2>&1
[ "$(proof "$B6")" = PROVEN ] && ok "local.properties (ignored) copied by default" || fail "default copy: $(proof "$B6")"

# ── old fix, file edited after it: the revert merges (3-way), not "patch failed" ─
new_project "$UT"; cd "$P"
printf '# header\n\n\n\ndef add(a, b):\n    return a - b\n' > src/calc.py; git commit -qam "bug"
printf '# header\n\n\n\ndef add(a, b):\n    return a + b\n' > src/calc.py; git commit -qam "fix add"; FIX="$(git rev-parse --short HEAD)"
printf 'def mul(a, b):\n    return a * b\n# header\n\n\n\ndef add(a, b):\n    return a + b\n' > src/calc.py; git commit -qam "later edit, away from the fix"
printf '%s' "$TEST_ADD" > tests/test_calc.py; git add tests && git commit -qm test
B7="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add sai (sửa cũ)" --fixed --test tests/test_calc.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B7" --fix-commit "$FIX" --wait >/dev/null 2>&1
[ "$(proof "$B7")" = PROVEN ] && ok "revert of an old fix merges with later edits (git revert in a worktree) → PROVEN" || fail "3-way: $(proof "$B7") $(python3 -c "import json;print(json.load(open('$P/.agents/regression_status.json'))['items']['$B7'].get('red_proof',{}).get('reason'))")"
git worktree list | grep -q red-proof && fail "sandbox worktree left behind" || ok "sandbox worktree removed afterwards"
printf 'def mul(a, b):\n    return a * b\n# header\n\n\n\ndef add(a, b):\n    return int(a) + int(b)\n' > src/calc.py; git commit -qam "edit ON the fixed line"
python3 - "$P" "$B7" <<'PY'
import json, sys
p = sys.argv[1] + "/.agents/regression_status.json"; d = json.load(open(p)); d["items"][sys.argv[2]].pop("red_proof", None); json.dump(d, open(p, "w"))
PY
python3 "$PROOF" "$P" --bug "$B7" --fix-commit "$FIX" --wait >/dev/null 2>&1
python3 -c "import json;r=json.load(open('$P/.agents/regression_status.json'))['items']['$B7']['red_proof'];assert r['status']=='INCONCLUSIVE' and 'src/calc.py' in r['reason'], r" 2>/dev/null \
  && ok "a real conflict (the fixed line itself changed since) → INCONCLUSIVE naming the file" || fail "conflict: $(proof "$B7")"
git reset -q --hard HEAD~1

# ── ambiguous evidence (two code commits named) → no auto-pick ─────────────
FIX2="$(git rev-parse --short HEAD~1)"
python3 - "$P" "$B7" "$FIX" "$FIX2" <<'PY'
import json, sys
p = sys.argv[1] + "/.agents/regression_status.json"; d = json.load(open(p)); it = d["items"][sys.argv[2]]
it.pop("red_proof", None); it["evidence"] = f"fix {sys.argv[3]}, notes {sys.argv[4]}"; json.dump(d, open(p, "w"))
PY
python3 "$PROOF" "$P" --pending --wait >/dev/null 2>&1
[ "$(proof "$B7")" = INCONCLUSIVE ] && python3 -c "import json;r=json.load(open('$P/.agents/regression_status.json'))['items']['$B7']['red_proof']['reason'];assert 'mơ hồ' in r, r" \
  && ok "evidence naming two code commits → INCONCLUSIVE 'mơ hồ', no guess" || fail "ambiguous: $(proof "$B7")"

# ── revert takes back only the fix's PRODUCTION code: test helpers other tests import and the
#    commit's notes (.agents/, .claude/, *.md) stay at HEAD (no compile break, no note conflict) ─
new_project "$UT"; cd "$P"
mkdir -p .agents/local && printf 'notes v1\n' > .agents/local/notes.md && git add -A && git commit -qm notes
printf 'def add(a, b):\n    return a + b\n' > src/calc.py
printf 'def two():\n    return 2\n' > tests/helper.py
printf 'import os, sys, unittest\nsys.path.insert(0, os.path.dirname(__file__))\nimport helper\nclass TestHelper(unittest.TestCase):\n    def test_two(self):\n        self.assertEqual(helper.two(), 2)\n' > tests/test_helper_user.py
printf 'notes v2 (fix)\n' > .agents/local/notes.md
git add -A && git commit -qm "fix add + helper + notes"; FIXH="$(git rev-parse --short HEAD)"
printf 'notes v3 (later)\n' > .agents/local/notes.md; git commit -qam "later notes"
printf '%s' "$TEST_ADD" > tests/test_calc.py; git add tests && git commit -qm "test for add"
B12="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add sai (helper)" --fixed --test tests/test_calc.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B12" --fix-commit "$FIXH" --wait >/dev/null 2>&1
[ "$(proof "$B12")" = PROVEN ] && ok "revert only the fix's production code (helper + notes kept at HEAD) → PROVEN" \
  || fail "prod-only revert: $(proof "$B12") $(python3 -c "import json;print(json.load(open('$P/.agents/regression_status.json'))['items']['$B12'].get('red_proof',{}).get('reason'))")"

# ── red only because the test no longer COMPILES (the revert removed what it calls) is not a
#    proof — even though the error names the test file ─────────────────────────────────────
new_project "$UT"; cd "$P"
printf 'def add(a, b):\n    return a + b\n\ndef helper():\n    return 1\n' > src/calc.py; git commit -qam "fix add + new helper"; FIXC="$(git rev-parse --short HEAD)"
printf 'import os, sys, unittest\nsys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))\nfrom calc import helper\nclass TestHelper(unittest.TestCase):\n    def test_helper(self):\n        self.assertEqual(helper(), 1)\n' > tests/test_calc.py
git add tests && git commit -qm "test only calls the new helper"
B13="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add sai (compile)" --fixed --test tests/test_calc.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B13" --fix-commit "$FIXC" --wait >/dev/null 2>&1
python3 -c "import json;r=json.load(open('$P/.agents/regression_status.json'))['items']['$B13']['red_proof'];assert r['status']=='INCONCLUSIVE' and 'biên dịch' in r['reason'], r" 2>/dev/null \
  && ok "red because the test cannot compile/import without the fix → INCONCLUSIVE, not PROVEN" \
  || fail "compile red: $(proof "$B13") $(python3 -c "import json;print(json.load(open('$P/.agents/regression_status.json'))['items']['$B13'].get('red_proof',{}).get('reason'))")"
cd "$TMP"

# ── revert takes back only SOURCE files that still exist: a data/binary file of the fix commit
#    (.wav, .gz) or a script deleted since is left alone instead of failing the whole revert ─
new_project "$UT"; cd "$P"
mkdir -p tools && printf 'old\n' > tools/run.sh && git add -A && git commit -qm tools
printf 'def add(a, b):\n    return a + b\n' > src/calc.py; printf 'RIFF' > tools/sample.wav; printf 'new\n' > tools/run.sh
git add -A && git commit -qm "fix add + sample + tool"; FIXS="$(git rev-parse --short HEAD)"
git rm -q tools/run.sh tools/sample.wav && git commit -qm "drop tools"
printf '%s' "$TEST_ADD" > tests/test_calc.py; git add tests && git commit -qm test
B14="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add sai (tools)" --fixed --test tests/test_calc.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B14" --fix-commit "$FIXS" --wait >/dev/null 2>&1
[ "$(proof "$B14")" = PROVEN ] && ok "files of the fix deleted since / not source code are not reverted → PROVEN" \
  || fail "source-only revert: $(proof "$B14") $(python3 -c "import json;print(json.load(open('$P/.agents/regression_status.json'))['items']['$B14'].get('red_proof',{}).get('reason'))")"
cd "$TMP"

# ── a bug linked to SEVERAL test files is PROVEN only when every one of them goes red; one red and
#    one still green (it guards a part the fix/patch did not touch) → INCONCLUSIVE, naming it ─
new_project "$UT"; cd "$P"
printf 'def add(a, b):\n    return a + b\n' > src/calc.py; printf '%s' "$TEST_ADD" > tests/test_calc.py
printf 'import unittest\nclass TestUnrelated(unittest.TestCase):\n    def test_ok(self):\n        self.assertTrue(True)\n' > tests/test_unrelated.py
B19="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add sai (2 file test)" --fixed --test tests/test_calc.py 2>&1)")"
CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs link "$B19" tests/test_unrelated.py >/dev/null 2>&1
python3 "$PROOF" "$P" --bug "$B19" --wait >/dev/null 2>&1
python3 -c "import json;r=json.load(open('$P/.agents/regression_status.json'))['items']['$B19']['red_proof'];assert r['status']=='INCONCLUSIVE' and 'test_unrelated' in r['reason'], r" 2>/dev/null \
  && ok "two linked test files, only one red without the fix → INCONCLUSIVE naming the green one" \
  || fail "multi-test: $(proof "$B19") $(python3 -c "import json;print(json.load(open('$P/.agents/regression_status.json'))['items']['$B19'].get('red_proof',{}).get('reason'))")"
cd "$TMP"

# ── only the bug's tests run when the suite has an impacted_command ────────
new_project "$UT"; cd "$P"
python3 - <<'PY'
import json
p = ".agents/regression_matrix.active.json"; d = json.load(open(p))
d["rules"][0]["mandatory_regression_tests"][0]["impacted_command"] = "python3 -m unittest -v {pytest_nodes}"; json.dump(d, open(p, "w"))
PY
git commit -qam impacted
printf 'def add(a, b):\n    return a + b\n' > src/calc.py; printf '%s' "$TEST_ADD" > tests/test_calc.py
printf 'import unittest\nclass TestOther(unittest.TestCase):\n    def test_other(self):\n        self.assertTrue(True)\n' > tests/test_other.py
git add tests/test_other.py && git commit -qm other
B8="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add sai impacted" --fixed --test tests/test_calc.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B8" --wait >/dev/null 2>&1
log="$(python3 -c "import json;print(json.load(open('$P/.agents/regression_status.json'))['items']['$B8']['red_proof'].get('log',''))")"
[ "$(proof "$B8")" = PROVEN ] && grep -q "unittest -v tests/test_calc.py" "$P/$log" && ! grep -q "test_other" "$P/$log" \
  && ok "impacted_command: only the bug's test file runs" || fail "impacted: $(proof "$B8") $(grep '^## ' "$P/$log" 2>/dev/null)"

# a filter that matches nothing ("Ran 0 tests") is not a GREEN run → INCONCLUSIVE, never VACUOUS
python3 - <<'PY'
import json
p = ".agents/regression_matrix.active.json"; d = json.load(open(p))
d["rules"][0]["mandatory_regression_tests"][0]["impacted_command"] = "python3 -m unittest -k no_such_test {pytest_nodes}"; json.dump(d, open(p, "w"))
PY
git commit -qam nomatch
python3 - "$P" "$B8" <<'PY'
import json, sys
p = sys.argv[1] + "/.agents/regression_status.json"; d = json.load(open(p)); d["items"][sys.argv[2]].pop("red_proof", None); json.dump(d, open(p, "w"))
PY
python3 "$PROOF" "$P" --bug "$B8" --wait >/dev/null 2>&1
[ "$(proof "$B8")" = INCONCLUSIVE ] && ok "command ran no test (filter matched nothing) → INCONCLUSIVE, not VACUOUS" || fail "no tests: $(proof "$B8")"

# ── monorepo: the Gradle module path is relative to the Gradle root the command cds into ─
M="$TMP/mono"; mkdir -p "$M/CarConnect/app/src/main/kotlin/pkg" "$M/CarConnect/app/src/test/kotlin/pkg" "$M/.agents"
( cd "$M" && git init -q . && git config user.email t@t && git config user.name t
  printf 'rootProject.name = "CarConnect"\ninclude(":app")\n' > CarConnect/settings.gradle.kts
  printf 'plugins { id("x") }\n' > CarConnect/app/build.gradle.kts
  printf 'package pkg\nfun add(a: Int, b: Int) = a - b\n' > CarConnect/app/src/main/kotlin/pkg/Calc.kt
  printf '#!/bin/sh\necho "gradle args: $*"\ngrep -q "a + b" app/src/main/kotlin/pkg/Calc.kt || { echo "pkg.CalcTest > add FAILED"; exit 1; }\necho "BUILD SUCCESSFUL"\n' > CarConnect/gradlew
  chmod +x CarConnect/gradlew
  python3 -c 'import json; json.dump({"adopted": True, "rules": [{"component": "Car", "watch_files": ["CarConnect/*"],
    "mandatory_regression_tests": [{"id": "REG-CAR", "name": "car", "command": "cd CarConnect && ./gradlew testDebugUnitTest",
      "impacted_command": "cd CarConnect && ./gradlew {gradle_module_tests:testDebugUnitTest}"}]}]}, open(".agents/regression_matrix.active.json", "w"))'
  git add -A && git commit -qm init
  printf 'package pkg\nfun add(a: Int, b: Int) = a + b\n' > CarConnect/app/src/main/kotlin/pkg/Calc.kt
  printf 'package pkg\nimport org.junit.Test\nimport org.junit.Assert.assertEquals\nclass CalcTest {\n    @Test fun add() { assertEquals(4, add(2, 2)) }\n}\n' > CarConnect/app/src/test/kotlin/pkg/CalcTest.kt )
B9="$(bid "$(CLAUDE_PROJECT_DIR="$M" bash "$KIT" bugs add "cộng sai CarConnect" --fixed --test CarConnect/app/src/test/kotlin/pkg/CalcTest.kt 2>&1)")"
python3 "$PROOF" "$M" --bug "$B9" --heavy --wait >/dev/null 2>&1
P9="$(python3 -c "import json;r=json.load(open('$M/.agents/regression_status.json'))['items']['$B9']['red_proof'];print(r['status'], r.get('log',''))")"
LOG9="$M/${P9#* }"
[ "${P9%% *}" = PROVEN ] && grep -q "gradle args: :app:testDebugUnitTest --tests" "$LOG9" && ! grep -q ":CarConnect:app" "$LOG9" \
  && ok "monorepo: module path relative to the Gradle root (:app:…, not :CarConnect:app:…)" || fail "monorepo: $P9 $(grep 'gradle args' "$LOG9" 2>/dev/null | head -1)"

# ── an instrumented (androidTest) ref never lands in a JVM unit-test task: `testDebugUnitTest --tests
#    <androidTest class>` matches nothing → "no tests ran" → INCONCLUSIVE forever ─
( cd "$M" && mkdir -p CarConnect/app/src/androidTest/kotlin/pkg
  printf 'package pkg\nclass CalcDeviceTest\n' > CarConnect/app/src/androidTest/kotlin/pkg/CalcDeviceTest.kt
  git add CarConnect/app/src/androidTest && git commit -qm "device test" )
B9b="$(bid "$(CLAUDE_PROJECT_DIR="$M" bash "$KIT" bugs add "cộng sai lần hai" --fixed --test CarConnect/app/src/test/kotlin/pkg/CalcTest.kt 2>&1)")"
python3 - "$M/.agents/regression_status.json" "$B9b" <<'PY'
import json, sys
p, b = sys.argv[1:]; d = json.load(open(p))
d["items"][b].setdefault("test_refs", []).append("CarConnect/app/src/androidTest/kotlin/pkg/CalcDeviceTest.kt")
json.dump(d, open(p, "w"), ensure_ascii=False, indent=2)
PY
python3 "$PROOF" "$M" --bug "$B9b" --heavy --wait >/dev/null 2>&1
P9b="$(python3 -c "import json;r=json.load(open('$M/.agents/regression_status.json'))['items']['$B9b']['red_proof'];print(r['status'], r.get('log',''))")"
LOG9b="$M/${P9b#* }"
[ "${P9b%% *}" = PROVEN ] && grep -q "gradle args: :app:testDebugUnitTest --tests pkg.CalcTest" "$LOG9b" && ! grep "gradle args" "$LOG9b" | grep -q CalcDeviceTest \
  && ok "androidTest ref left out of the unit-test task" || fail "androidTest: $P9b $(grep 'gradle args' "$LOG9b" 2>/dev/null | head -1)"

# ── narrowed(): two tests in one module share ONE task (a repeated task's second --tests replaces
#    the first → only the last test ran); a suite gets only the modules its own command runs ─
mkdir -p "$M/CarConnect/lib/src/test/kotlin/pkg"; printf 'plugins { id("x") }\n' > "$M/CarConnect/lib/build.gradle.kts"
for f in app/src/test/kotlin/pkg/ATest app/src/test/kotlin/pkg/BTest lib/src/test/kotlin/pkg/LTest; do
  printf 'package pkg\nclass %s\n' "${f##*/}" > "$M/CarConnect/$f.kt"; done
NR="$(cd "$DEVKIT_DIR/scripts" && python3 - "$M" <<'PY'
import sys; from pathlib import Path
import red_proof as rp
M = Path(sys.argv[1]); a = "CarConnect/app/src/test/kotlin/pkg/"; l = "CarConnect/lib/src/test/kotlin/pkg/"
t = "cd CarConnect && ./gradlew {gradle_module_tests:testDebugUnitTest}"
print(rp.narrowed(M, t, [a + "ATest.kt", a + "BTest.kt"]))
print(rp.narrowed(M, t, [a + "ATest.kt", l + "LTest.kt"], scope="cd CarConnect && ./gradlew :lib:testDebugUnitTest"))
PY
)"
[ "$(printf '%s\n' "$NR" | sed -n 1p)" = "cd CarConnect && ./gradlew :app:testDebugUnitTest --tests 'pkg.ATest' --tests 'pkg.BTest'" ] \
  && ok "two tests in one module → one task, both --tests" || fail "one task: $(printf '%s\n' "$NR" | sed -n 1p)"
[ "$(printf '%s\n' "$NR" | sed -n 2p)" = "cd CarConnect && ./gradlew :lib:testDebugUnitTest --tests 'pkg.LTest'" ] \
  && ok "multi-suite bug: each suite gets only the modules it runs" || fail "scope: $(printf '%s\n' "$NR" | sed -n 2p)"

# ── a second top-level test class in the same file runs too (the filter used the file name only,
#    so AccessControlJvmTest inside CarTcpServerJvmLoopbackTest.kt never ran → VACUOUS) ─
printf 'package pkg\nclass TwoTest {\n}\n\ninternal class AlsoTest {\n    class Nested\n}\nabstract class BaseTest\ndata class Fixture(val a: Int)\n' \
  > "$M/CarConnect/app/src/test/kotlin/pkg/TwoTest.kt"
NR2="$(cd "$DEVKIT_DIR/scripts" && python3 - "$M" <<'PY'
import sys; from pathlib import Path
import red_proof as rp
print(rp.narrowed(Path(sys.argv[1]), "cd CarConnect && ./gradlew {gradle_module_tests:testDebugUnitTest}",
                  ["CarConnect/app/src/test/kotlin/pkg/TwoTest.kt"]))
PY
)"
[ "$NR2" = "cd CarConnect && ./gradlew :app:testDebugUnitTest --tests 'pkg.TwoTest' --tests 'pkg.AlsoTest'" ] \
  && ok "every top-level test class of a file is in the filter" || fail "classes: $NR2"

# ── "no tests ran" must not match a real total that ends in 0 ("20 tests completed, 2 failed") ─
NT="$(cd "$DEVKIT_DIR/scripts" && python3 -c 'import red_proof as rp
print(bool(rp.NO_TESTS.search("20 tests completed, 2 failed")), bool(rp.NO_TESTS.search("0 tests completed")))')"
[ "$NT" = "False True" ] && ok "NO_TESTS: 20 tests completed is a real run, 0 tests completed is not" || fail "NO_TESTS: $NT"

# ── a Kotlin test file holding SEVERAL test classes: every class is run (--tests per class) and
#    a failure in any of them counts as that file going red ─
K="$TMP/kmulti"; mkdir -p "$K/app/src/test/kotlin/pkg" && touch "$K/settings.gradle.kts" "$K/app/build.gradle.kts"
printf 'package pkg\n\nimport org.junit.Test\n\nclass LoopbackTest {\n    @Test fun a() {}\n}\n\ninternal class AccessControlJvmTest {\n    @Test fun b() {}\n}\n' > "$K/app/src/test/kotlin/pkg/LoopbackTest.kt"
python3 -c "import sys; sys.path.insert(0,'$DEVKIT_DIR/scripts'); import red_proof as r
from pathlib import Path
c = r.narrowed(Path('$K'), './gradlew :app:testDebugUnitTest {gradle_tests}', ['app/src/test/kotlin/pkg/LoopbackTest.kt'])
assert \"pkg.LoopbackTest\" in c and \"pkg.AccessControlJvmTest\" in c, c
names = r.test_names(Path('$K'), 'app/src/test/kotlin/pkg/LoopbackTest.kt')
assert names == {'LoopbackTest', 'AccessControlJvmTest'}, names
red = r.failed_stems('pkg.AccessControlJvmTest > b FAILED', {'LoopbackTest'}, {'LoopbackTest': names})
assert red == {'LoopbackTest'}, red
assert not r.failed_stems('pkg.OtherTest > c FAILED', {'LoopbackTest'}, {'LoopbackTest': names})" 2>"$TMP/km.err" \
  && ok "every test class of a multi-class file is run, and a failure in any of them reds that file" || fail "multi-class: $(tail -2 "$TMP/km.err")"

# ── the strict rule only requires red from linked files the (narrowed) command REALLY runs:
#    a linked .sh no suite runs, or a class outside `--tests`, is not "still green" ─
mkdir -p "$M/scripts/qa/tests"
SEL="$(cd "$DEVKIT_DIR/scripts" && python3 - "$M" <<'PY'
import sys; from pathlib import Path
import red_proof as rp
M = Path(sys.argv[1]); a = "CarConnect/app/src/test/kotlin/pkg/"
nar = "cd CarConnect && ./gradlew :app:testDebugUnitTest --tests 'pkg.ATest' --tests 'pkg.TwoTest' --tests 'pkg.AlsoTest'"
full = "cd CarConnect && ./gradlew testDebugUnitTest"
cases = [
  (a + "ATest.kt", nar, True), (a + "TwoTest.kt", nar, True), (a + "BTest.kt", nar, False),
  ("scripts/qa/tests/test_gate.sh", nar, False),
  (a + "BTest.kt", full, True), ("scripts/qa/tests/test_gate.sh", full, False), ("scripts/qa/tests/test_x.py", full, False),
  ("scripts/qa/tests/test_gate.sh", "bash scripts/qa/tests/test_gate.sh", True),
  ("scripts/qa/tests/test_artifact_promotion_gate.sh", "bash scripts/qa/ci/verify_prerelease_gates.sh", False),
  ("scripts/qa/tests/test_x.py", "python3 -m pytest scripts/qa/tests/test_x.py", True),
  ("scripts/qa/tests/test_y.py", "python3 -m pytest scripts/qa/tests/test_x.py", False),
  ("scripts/qa/tests/test_y.py", "cd scripts/qa && python3 -m pytest tests", True),
  ("scripts/qa/tests/test_gate.sh", "cd scripts/qa && python3 -m pytest tests", False),
  ("tests/test_calc.py", "python3 -m unittest tests.test_calc", True),
  ("tests/check_extra.sh", "python3 -m unittest tests.test_calc", False),
  ("Assets/T/EditMode/FooTests.cs", "unity-batch.sh -testPlatform EditMode --filter 'Ns.FooTests'", True),
  ("Assets/T/EditMode/BarTests.cs", "unity-batch.sh -testPlatform EditMode --filter 'Ns.FooTests'", False),
  ("tests/test_calc.py", "make test", True),
]
bad = [f"{t} | {c} -> {rp.selects(M, t, c)}" for t, c, want in cases if rp.selects(M, t, c) != want]
print("\n".join(bad) or "ok")
PY
)"
[ "$SEL" = ok ] && ok "selects(): only files the narrowed command really runs" || fail "selects(): $SEL"

P_KEEP="$P"
new_project "python3 -m unittest tests.test_calc"; cd "$P"
printf 'def add(a, b):\n    return a + b\n' > src/calc.py
printf '%s' "$TEST_ADD" > tests/test_calc.py
printf '#!/bin/sh\nexit 0\n' > tests/check_extra.sh
B12="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "cộng sai, thêm ref không chạy" --fixed --test tests/test_calc.py 2>&1)")"
python3 - "$P/.agents/regression_status.json" "$B12" <<'PY'
import json, sys
p, b = sys.argv[1:]; d = json.load(open(p))
d["items"][b].setdefault("test_refs", []).append("tests/check_extra.sh")
json.dump(d, open(p, "w"), ensure_ascii=False, indent=2)
PY
python3 "$PROOF" "$P" --bug "$B12" --heavy --wait >/dev/null 2>&1
[ "$(proof "$B12")" = PROVEN ] && ok "a linked file the command never runs does not block PROVEN" || fail "unrun ref: $(proof "$B12") $(python3 -c "import json;print((json.load(open('$P/.agents/regression_status.json'))['items']['$B12'].get('red_proof') or {}).get('reason',''))")"
P="$P_KEEP"; cd "$P"

# ── proof slots: "jobs" in .agents/local/red_proof.json lets N proofs run at once (default 1) ─
SL="$TMP/slots"; mkdir -p "$SL/.agents/local"
SLOT="$(cd "$DEVKIT_DIR/scripts" && python3 - "$SL" <<'PY'
import json, os, sys; from pathlib import Path
import red_proof as rp
P = Path(sys.argv[1]); st = P / ".claude" / "audit-gate"; st.mkdir(parents=True, exist_ok=True)
out = [rp.jobs_of(P)]
a = rp.proof_slot(st, 1, wait=False); out.append(rp.proof_slot(st, 1, wait=False) is None); a.close()
(P / ".agents/local/red_proof.json").write_text(json.dumps({"copy": [], "jobs": 2}))
out.append(rp.jobs_of(P))
a = rp.proof_slot(st, 2, wait=False); b = rp.proof_slot(st, 2, wait=False)
out.append(a is not None and b is not None and rp.proof_slot(st, 2, wait=False) is None)
os.environ["RED_PROOF_JOBS"] = "3"; out.append(rp.jobs_of(P))
print(out)
PY
)"
[ "$SLOT" = "[1, True, 2, True, 3]" ] && ok "proof slots: 1 by default, red_proof.json jobs=2 → two at once, a third waits; RED_PROOF_JOBS wins" \
  || fail "proof slots: $SLOT"

# ── unknown id → exit 2 with a suggestion; an id without the BUG- prefix is found ─
python3 "$PROOF" "$P" --bug "BUG-nope-xyz" --wait > "$TMP/unk" 2>&1; rc=$?
[ $rc = 2 ] && grep -q "không có" "$TMP/unk" && ok "unknown id → exit 2, said so" || fail "unknown id: rc=$rc $(cat "$TMP/unk")"
python3 "$PROOF" "$P" --bug "${B8#BUG-}" --wait > "$TMP/unk" 2>&1; rc=$?
[ $rc = 0 ] && ok "id without the BUG- prefix is found" || fail "prefix: rc=$rc $(cat "$TMP/unk")"

# ── the DevKit links git does not hold (.agents/active-profile → the profile) exist in the sandbox ─
new_project "bash .agents/active-profile/scripts/run-tests.sh"; cd "$P"
mkdir -p "$TMP/profile$$/scripts" && printf '#!/bin/sh\nexec python3 -m unittest discover -s tests\n' > "$TMP/profile$$/scripts/run-tests.sh"
ln -s "$TMP/profile$$" .agents/active-profile && printf '.agents/active-profile\n' >> .git/info/exclude
printf 'def add(a, b):\n    return a + b\n' > src/calc.py; printf '%s' "$TEST_ADD" > tests/test_calc.py
B10="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add sai profile" --fixed --test tests/test_calc.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B10" --wait >/dev/null 2>&1
[ "$(proof "$B10")" = PROVEN ] && ok "untracked DevKit link (.agents/active-profile) recreated in the sandbox → the suite runs → PROVEN" \
  || fail "devkit link: $(proof "$B10") $(python3 -c "import json;print(json.load(open('$P/.agents/regression_status.json'))['items']['$B10'].get('red_proof',{}).get('reason'))")"

# ── --pending never takes the user's unrelated uncommitted work as "the fix" of a past bug ─
new_project "$UT"; cd "$P"
printf 'def add(a, b):\n    return a + b\n' > src/calc.py; printf '%s' "$TEST_ADD" > tests/test_calc.py
git add -A && git commit -qm "old fix + test"
printf 'x = 1\n' > src/other.py                                   # unrelated work in progress
B11="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add sai (cũ, không có commit)" --fixed --test tests/test_calc.py 2>&1)")"
echo "# t" >> tests/test_calc.py; CLAUDE_PROJECT_DIR="$P" python3 "$GATE" --run-tests --full --allow-no-tests >/dev/null 2>&1; git checkout -q tests/test_calc.py
python3 "$PROOF" "$P" --pending --wait >/dev/null 2>&1
python3 -c "import json;r=json.load(open('$P/.agents/regression_status.json'))['items']['$B11']['red_proof'];assert r['status']=='INCONCLUSIVE' and 'commit fix' in r['reason'], r" 2>/dev/null \
  && ok "--pending: past bug with no fix commit → INCONCLUSIVE, never the user's unrelated uncommitted work as its fix" \
  || fail "pending/session: $(proof "$B11") $(python3 -c "import json;print(json.load(open('$P/.agents/regression_status.json'))['items']['$B11'].get('red_proof',{}).get('reason'))")"

# ── --patch: a patch that puts the bug BACK proves an old bug with no usable fix commit ─
reason() { python3 -c "import json;print((json.load(open('$P/.agents/regression_status.json'))['items']['$1'].get('red_proof') or {}).get('reason',''))"; }
new_project "$UT"; cd "$P"
printf 'def add(a, b):\n    return a + b\n' > src/calc.py; printf '%s' "$TEST_ADD" > tests/test_calc.py
git add -A && git commit -qm "old fix + test, commit long forgotten"
printf 'def add(a, b):\n    return a - b\n' > src/calc.py; git diff > "$TMP/bug-back.patch"; git checkout -q src/calc.py
printf 'def add(a, b):\n    return a + b  # same behaviour\n' > src/calc.py; git diff > "$TMP/harmless.patch"; git checkout -q src/calc.py
B15="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add sai (patch)" --fixed --test tests/test_calc.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B15" --patch "$TMP/bug-back.patch" --wait >/dev/null 2>&1
[ "$(proof "$B15")" = PROVEN ] && ok "--patch: HEAD + patch that puts the bug back → RED, HEAD → GREEN → PROVEN" \
  || fail "patch: $(proof "$B15") $(reason "$B15")"
[ -f "$P/.agents/local/red-patches/$B15.patch" ] && ok "--patch keeps the patch at .agents/local/red-patches/<ID>.patch (re-provable)" || fail "patch not kept"
grep -q "a + b" src/calc.py && [ -z "$(git -C "$P" status --porcelain -- src)" ] && ok "--patch never touches the working tree" || fail "patch touched the tree"
python3 -c "import json;r=json.load(open('$P/.agents/regression_status.json'))['items']['$B15']['red_proof'];assert r['mode']=='patch' and '.agents/local/red-patches/$B15.patch' in r['files'], r" 2>/dev/null \
  && ok "proof records mode=patch and hashes the patch (editing it → OUTDATED)" || fail "patch record"
B16="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "patch vô hại" --fixed --test tests/test_calc.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B16" --patch "$TMP/harmless.patch" --wait >/dev/null 2>&1
[ "$(proof "$B16")" = VACUOUS ] && ok "--patch that does not break the behaviour → VACUOUS (test or patch is wrong)" || fail "harmless patch: $(proof "$B16")"
B17="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "patch tự tìm" --fixed --test tests/test_calc.py 2>&1)")"
mkdir -p .agents/local/red-patches; cp "$TMP/bug-back.patch" ".agents/local/red-patches/$B17.patch"
python3 "$PROOF" "$P" --pending --wait >/dev/null 2>&1
[ "$(proof "$B17")" = PROVEN ] && ok "--pending picks .agents/local/red-patches/<ID>.patch by itself → PROVEN" || fail "auto patch: $(proof "$B17") $(reason "$B17")"
printf 'def add(a, b):\n    return a - b\n' > src/calc.py; printf '# weakened\n' >> tests/test_calc.py; git diff > "$TMP/touches-test.patch"; git checkout -q src/calc.py tests/test_calc.py
B18="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "patch sửa test" --fixed --test tests/test_calc.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B18" --patch "$TMP/touches-test.patch" --wait >/dev/null 2>&1
[ "$(proof "$B18")" = INCONCLUSIVE ] && reason "$B18" | grep -q "file test" && ok "patch that edits a test file → INCONCLUSIVE (a proof may not change the test)" \
  || fail "touches test: $(proof "$B18") $(reason "$B18")"
sed 's/return a + b/return a * b/' "$TMP/bug-back.patch" > "$TMP/stale.patch"
B19="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "patch lệch code" --fixed --test tests/test_calc.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B19" --patch "$TMP/stale.patch" --wait >/dev/null 2>&1
[ "$(proof "$B19")" = INCONCLUSIVE ] && reason "$B19" | grep -q "không áp được" && ok "patch that no longer applies → INCONCLUSIVE naming the file" \
  || fail "stale patch: $(proof "$B19") $(reason "$B19")"
B20="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "cũ, chưa có patch" --fixed --test tests/test_calc.py 2>&1)")"
python3 "$PROOF" "$P" --pending --wait >/dev/null 2>&1
[ "$(proof "$B20")" = INCONCLUSIVE ] || fail "setup: $B20 should be INCONCLUSIVE first, got $(proof "$B20")"
cp "$TMP/bug-back.patch" ".agents/local/red-patches/$B20.patch"
python3 "$PROOF" "$P" --pending --wait >/dev/null 2>&1
[ "$(proof "$B20")" = PROVEN ] && ok "--pending retries an INCONCLUSIVE bug once a patch is added for it → PROVEN" || fail "retry: $(proof "$B20") $(reason "$B20")"
python3 "$PROOF" "$P" --bug "$B15" --patch "$TMP/bug-back.patch" --fix-commit HEAD --wait >/dev/null 2>&1; [ $? = 2 ] \
  && ok "--patch with --fix-commit → exit 2" || fail "--patch + --fix-commit accepted"
python3 "$PROOF" "$P" --bug "$B15,$B16" --patch "$TMP/bug-back.patch" --wait >/dev/null 2>&1; [ $? = 2 ] \
  && ok "--patch with more than one bug → exit 2" || fail "--patch with 2 bugs accepted"

# ── heavy suite waits for --heavy ───────────────────────────────────────────
new_project "true || ./gradlew test; $UT"; cd "$P"
printf 'def add(a, b):\n    return a + b\n' > src/calc.py; printf '%s' "$TEST_ADD" > tests/test_calc.py
B5="$(bid "$(CLAUDE_PROJECT_DIR="$P" bash "$KIT" bugs add "add sai heavy" --fixed --test tests/test_calc.py 2>&1)")"
python3 "$PROOF" "$P" --bug "$B5" --wait >/dev/null 2>&1
[ "$(proof "$B5")" = PENDING ] && ok "heavy suite (Gradle) → PENDING for the nightly job" || fail "heavy: $(proof "$B5")"
python3 "$PROOF" "$P" --bug "$B5" --heavy --wait >/dev/null 2>&1
[ "$(proof "$B5")" = PROVEN ] && ok "--heavy (nightly) runs it" || fail "heavy run: $(proof "$B5")"
RED_PROOF=0 python3 "$PROOF" "$P" --pending --wait >/dev/null 2>&1; [ $? = 0 ] && ok "RED_PROOF=0 is a no-op" || fail "RED_PROOF=0"

[ "$FAILS" -eq 0 ] && echo "✅ test_red_proof: all passed" || { echo "❌ test_red_proof: $FAILS failed"; exit 1; }
