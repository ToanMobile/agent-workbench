#!/usr/bin/env bash
# Regression test (Goods audit 2026-09-27): a bug row took its whole suite's status, so 12 failing
# tests with one root cause turned 33 bug rows ❌ — none of whose own tests had failed. When the
# suite run names its failing tests (Unity "[Failed] Ns.Class.Method", Gradle "Class > m FAILED",
# pytest "FAILED path::test"), a bug whose own test files (runs_in_suite) are not among them keeps
# its own result. A red run that names no test (compile error) stays FAIL for every row.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/.agents/evidence"
DEVKIT_DIR="$DEVKIT_DIR" P="$TMP/p" python3 - <<'PY'
import os, sys, time
sys.path.insert(0, os.path.join(os.environ["DEVKIT_DIR"], "bin"))
import regression_checklist as rc
from pathlib import Path
P = Path(os.environ["P"]); fails = 0
def check(name, want, got):
    global fails
    print(("✔ " if want == got else "✖ ") + name + ("" if want == got else f": {got}, expected {want}"))
    fails += want != got

def fresh():
    now = time.time()
    return {"version": 1, "items": {
        "REG-2": {"id": "REG-2", "kind": "test", "command": "run", "last": {"status": "PASS", "ts": now - 100}},
        "BUG-A": {"id": "BUG-A", "kind": "bug", "title": "a", "tests": ["REG-2"], "fixed": True, "state": "confirmed",
                  "runs_in_suite": ["Assets/Tests/EditMode/LevelTitleStringsTests.cs"],
                  "red_proof": {"status": "PROVEN", "ts": now - 200}},
        "BUG-B": {"id": "BUG-B", "kind": "bug", "title": "b", "tests": ["REG-2"], "fixed": True, "state": "confirmed",
                  "runs_in_suite": ["Assets/Tests/EditMode/LevelCatalogTests.cs"],
                  "red_proof": {"status": "PROVEN", "ts": now - 200}},
        "BUG-C": {"id": "BUG-C", "kind": "bug", "title": "c", "tests": ["REG-2"], "fixed": True, "state": "confirmed",
                  "red_proof": {"status": "PROVEN", "ts": now - 200}}}}

def run(output, log_name):
    data = fresh()
    (P / ".agents/evidence" / log_name).write_text(output, encoding="utf-8")
    rc.record_results(data, [{"id": "REG-2", "status": "FAIL", "exit_code": 1, "duration": "9s",
                              "log": ".agents/evidence/" + log_name, "output_tail": output[-50:]}],
                      task="t", commit=None, project=P)
    return {b: rc.effective_status(data, data["items"][b]) for b in ("BUG-A", "BUG-B", "BUG-C")}

unity = "# status: FAIL\n" + "\n".join(f"  [Failed] CozyGoods.Tests.EditMode.LevelCatalogTests.T{i}: boom" for i in range(10)) \
        + "\nFAIL: EditMode: 168 passed, 10 failed, 1 skipped\n"
st = run(unity, "u.log")
check("Unity: a bug whose own test did not fail keeps PASS", "PASS", st["BUG-A"])
check("Unity: the bug whose test failed is FAIL", "FAIL", st["BUG-B"])
check("Unity: a bug with no own test file stays with the suite (FAIL)", "FAIL", st["BUG-C"])
st = run("> Task :app:test\ncom.x.LevelCatalogTests > loads() FAILED\n3 tests completed, 1 failed\n", "g.log")
check("Gradle 'Class > m FAILED': other bug keeps PASS", "PASS", st["BUG-A"])
check("Gradle: named class → FAIL", "FAIL", st["BUG-B"])
st = run("error CS1002: ; expected\nCompilation failed\n", "c.log")
check("a red run naming no test (compile error) fails every row", ["FAIL", "FAIL"], [st["BUG-A"], st["BUG-B"]])
st = run("FAILED Assets/Tests/EditMode/LevelTitleStringsTests.py::test_title - assert 1 == 2\n=== 1 failed, 5 passed in 0.1s ===\n", "p.log")
check("pytest 'FAILED path::test' → that bug FAIL, the other PASS", ["FAIL", "PASS"], [st["BUG-A"], st["BUG-B"]])
# Only a run known to be complete, with every failure named, clears a bug (review 2026-09-27):
# anything else keeps the whole suite's FAIL.
st = run("FAILED tests/test_a.py::t\nERROR Assets/Tests/EditMode/LevelTitleStringsTests.py - ImportError\n=== 1 failed, 1 error in 0.1s ===\n", "e.log")
check("pytest ERROR on the bug's own file → FAIL", "FAIL", st["BUG-A"])
st = run("FAILED tests/test_a.py::t\n!!! stopping after 1 failures !!!\n=== 1 failed in 0.1s ===\n", "x.log")
check("pytest -x (stopped early) → FAIL", "FAIL", st["BUG-A"])
st = run("e: Assets/Tests/EditMode/LevelTitleStringsTests.kt:3 Unresolved reference\ncom.x.OtherTest > a() FAILED\n2 tests completed, 1 failed\n", "k.log")
check("a compile error next to a named failure → FAIL", "FAIL", st["BUG-A"])
st = run("  [Failed] CozyGoods.Tests.EditMode.LevelCatalogTests.T0: boom\n", "n.log")
check("no summary line (crashed mid-run) → FAIL", "FAIL", st["BUG-A"])
st = run("com.x.LevelTitleStringsTests$Inner > m() FAILED\n3 tests completed, 1 failed\n", "i.log")
check("an inner class Stem$Inner is the bug's own test → FAIL", "FAIL", st["BUG-A"])
st = run("com.x.LevelTitleStringsTest > m() FAILED\n3 tests completed, 1 failed\n", "s.log")
check("file LevelTitleStringsTests vs class LevelTitleStringsTest → FAIL (prefix)", "FAIL", st["BUG-A"])
sys.exit(1 if fails else 0)
PY
