#!/usr/bin/env bash
# Regression test (audit 2026-10-09): bin/regression_checklist.py sync_from_matrix only ever ADDED matrix suites. A suite gone from
# the matrix stayed a "⏳ chưa chạy" row for ever and kept the safety % down (the workbench carried a test fixture's
# `REG-01 echo FULL_TEST_EXECUTED`: "An toàn 39%"). A row the matrix no longer has is dropped only when it holds nothing: never run,
# no history, no bug / REQ linking it. A row with results or links stays.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
python3 - "$DEVKIT_DIR/bin" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import regression_checklist as rc

fails = 0
def check(ok, name):
    global fails
    print(("✔ " if ok else "✖ ") + name)
    fails += 0 if ok else 1

matrix = {"rules": [{"component": "core", "watch_files": ["src/*"],
                     "mandatory_regression_tests": [{"id": "REG-NOW", "name": "now", "command": "true"}]}]}
data = {"items": {
    "REG-RETIRED": {"id": "REG-RETIRED", "kind": "test", "last": None, "history": [], "title": "gone", "command": "echo x"},
    "REG-RAN": {"id": "REG-RAN", "kind": "test", "last": {"status": "PASS"}, "history": [{"status": "PASS"}], "title": "ran"},
    "REG-LINKED": {"id": "REG-LINKED", "kind": "test", "last": None, "history": [], "title": "linked"},
    "BUG-1": {"id": "BUG-1", "kind": "bug", "tests": ["REG-LINKED"], "title": "a bug"},
}}
rc.sync_from_matrix(data, matrix)
items = data["items"]
check("REG-NOW" in items, "a matrix suite becomes a row")
check("REG-RETIRED" not in items, "a never-run row the matrix no longer has is dropped")
check("REG-RAN" in items, "a row with results is kept")
check("REG-LINKED" in items, "a row a bug links is kept")
check("BUG-1" in items, "bug rows are never touched")

empty = {"items": {"REG-RETIRED": {"id": "REG-RETIRED", "kind": "test", "last": None, "history": []}}}
rc.sync_from_matrix(empty, {})
check("REG-RETIRED" in empty["items"], "no matrix (none found / unreadable): nothing is dropped")

print("✅ test_checklist_retired_rows: all passed" if not fails else "❌ test_checklist_retired_rows: %d failed" % fails)
sys.exit(1 if fails else 0)
PY
