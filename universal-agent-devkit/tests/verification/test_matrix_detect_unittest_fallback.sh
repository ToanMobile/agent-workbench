#!/usr/bin/env bash
# Hồi quy (13/11, audit prompt cài đặt): matrix_detect chọn `python3 -m pytest -q` cho mọi repo có tests/test_*.py mà không kiểm python3
# của máy có pytest hay không. Đo thật: repo thử Python (test viết bằng unittest) trên máy chưa cài pytest → gate REJECT, "Test hồi quy
# đạt: 0/1", log "No module named pytest" (14:07:37 và 14:24:57). Nay khi dự án KHÔNG khai báo pytest và mọi file test chắc chắn chạy
# được bằng unittest, LỆNH trong ma trận tự chọn lúc chạy: có pytest thì pytest, không thì `python3 -m unittest discover`.
# Việc chọn nằm trong lệnh, không nằm trong bước sinh ma trận: ma trận sinh ra phải giống nhau từng byte trên mọi máy, vì gate chỉ tin
# ma trận chưa commit khi nó khớp bản sinh lại (review OpenCodeReview 13/11, P1: bản đầu sinh khác nhau theo máy, gate còn "rules: 0").
# Mọi trường hợp khác giữ nguyên `python3 -m pytest -q`: dự án khai báo pytest, hoặc còn nghi ngờ unittest bỏ sót test.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MD="$DEVKIT_DIR/scripts/governance/matrix_detect.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
unset CLAUDE_PROJECT_DIR TARGET_DIR DEVKIT_SOURCE_EXTS
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

cmds() { python3 "$MD" "$1" 2>/dev/null | python3 -c 'import json,sys
try: print(" | ".join(t["command"] for t in json.load(sys.stdin)["rules"][0]["mandatory_regression_tests"]))
except Exception: print("none")'; }
expect() {  # mô tả, dự án, lệnh mong đợi
  local got; got="$(cmds "$2")"
  [ "$got" = "$3" ] && ok "$1" || fail "$1: got '$(printf '%s' "$got" | cut -c1-200)', expected '$3'"
}
either() { printf "if python3 -c 'import pytest' 2>/dev/null; then python3 -m pytest -q; else %s; fi" "$1"; }
PYTEST="python3 -m pytest -q"
unittest_proj() {  # $1 = tên, $2 = thư mục test (tests|test)
  P="$TMP/$1"; mkdir -p "$P/$2"
  printf 'def add(a, b):\n    return a + b\n' > "$P/calc.py"
  printf 'import unittest\n\nimport calc\n\n\nclass AddTest(unittest.TestCase):\n    def test_add(self):\n        self.assertEqual(calc.add(2, 3), 5)\n' > "$P/$2/test_calc.py"
}
# python3 giả trên PATH: `-c 'import pytest'` thất bại, mọi lời gọi khác chuyển cho python3 thật. Ép nhánh unittest trên mọi máy.
REAL_PY="$(command -v python3)"; mkdir -p "$TMP/nopytest"
printf '#!/bin/bash\nif [ "$1" = "-c" ] && [ "$2" = "import pytest" ]; then exit 1; fi\nexec "%s" "$@"\n' "$REAL_PY" > "$TMP/nopytest/python3"; chmod +x "$TMP/nopytest/python3"
run_without_pytest() { (cd "$1" && PATH="$TMP/nopytest:$PATH" bash -c "$(cmds "$1")" 2>&1); }

unittest_proj u1 tests
expect "A1: unittest-only project → one command that picks the runner when it RUNS" "$P" "$(either "python3 -m unittest discover -s tests")"
out="$(run_without_pytest "$P")"; rc=$?
{ [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'Ran 1 test'; } && ok "A1b: without pytest that command really runs the project's test (exit 0, Ran 1 test)" \
  || fail "A1b: exit $rc: $(printf '%s' "$out" | tail -2 | tr '\n' ' ' | cut -c1-160)"
printf 'import unittest\n\nimport calc\n\n\nclass BadTest(unittest.TestCase):\n    def test_bad(self):\n        self.assertEqual(calc.add(2, 3), 6)\n' > "$P/tests/test_bad.py"
out="$(run_without_pytest "$P")"; rc=$?
[ "$rc" != 0 ] && ok "A1c: a failing unittest test makes that command fail (exit $rc)" || fail "A1c: a failing test still exits 0"
rm -f "$P/tests/test_bad.py"
# Sinh ma trận phải giống nhau từng byte dù python3 có import được pytest hay không (pytest giả trên PYTHONPATH).
mkdir -p "$TMP/stub/pytest" && : > "$TMP/stub/pytest/__init__.py"
a="$(python3 "$MD" "$P" 2>/dev/null)"; b="$(PYTHONPATH="$TMP/stub" python3 "$MD" "$P" 2>/dev/null)"
[ -n "$a" ] && [ "$a" = "$b" ] && ok "A2: the generated matrix is byte-identical with and without an importable pytest" \
  || fail "A2: generation depends on the interpreter: '$(printf '%s' "$a" | grep -o '"command": "[^"]*' | cut -c1-90)' vs '$(printf '%s' "$b" | grep -o '"command": "[^"]*' | cut -c1-90)'"
unittest_proj u2 test
expect "A3: tests under test/ → discover -s test" "$P" "$(either "python3 -m unittest discover -s test")"
unittest_proj u3 tests; : > "$P/conftest.py"
expect "A4: a project that declares pytest (conftest.py) keeps plain pytest" "$P" "$PYTEST"
unittest_proj u4 tests; printf '[tool.pytest.ini_options]\naddopts = "-q"\n' > "$P/pyproject.toml"
expect "A5: pytest named in pyproject.toml keeps plain pytest" "$P" "$PYTEST"
P="$TMP/u5"; mkdir -p "$P/tests"; printf 'def test_add():\n    assert 1 + 1 == 2\n' > "$P/tests/test_plain.py"
expect "A6: pytest-style tests keep plain pytest: unittest would run nothing" "$P" "$PYTEST"
P="$TMP/u6"; mkdir -p "$P/tests"; printf '# class X(unittest.TestCase) is only mentioned in a comment\ndef test_x():\n    assert True\n' > "$P/tests/test_c.py"
expect "A7: a TestCase named only inside a comment is not a unittest test" "$P" "$PYTEST"
# Review 13/11 (principal-code-reviewer + OpenCodeReview): unittest chỉ được nêu khi nó chắc chắn chạy HẾT test của dự án; còn nghi
# ngờ thì giữ pytest để lỗi thiếu runner hiện ra, không để gate xanh trong khi một phần test không chạy.
unittest_proj u8 tests; printf 'def test_b():\n    assert False\n' > "$P/tests/test_b.py"
expect "A8: a directory mixing TestCase files and pytest-style files keeps plain pytest (unittest would skip test_b)" "$P" "$PYTEST"
P="$TMP/u9"; mkdir -p "$P/tests"; printf 'from unittest import mock\n\n\ndef test_m():\n    assert mock is not None\n' > "$P/tests/test_m.py"
expect "A9: 'from unittest import mock' in a pytest-style file is not a unittest test" "$P" "$PYTEST"
unittest_proj u10 tests; : > "$P/tests/__init__.py"; printf 'VALUE = 5\n' > "$P/tests/helpers.py"
printf 'import unittest\n\nimport calc\nfrom .helpers import VALUE\n\n\nclass RelTest(unittest.TestCase):\n    def test_rel(self):\n        self.assertEqual(calc.add(2, 3), VALUE)\n' > "$P/tests/test_rel.py"
expect "A10: a tests/ package gets '-t .' so relative imports work" "$P" "$(either "python3 -m unittest discover -s tests -t .")"
out="$(run_without_pytest "$P")"; rc=$?
{ [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'Ran 2 tests'; } && ok "A10b: without pytest that command runs both tests of the package (exit 0, Ran 2 tests)" \
  || fail "A10b: exit $rc: $(printf '%s' "$out" | tail -2 | tr '\n' ' ' | cut -c1-160)"
unittest_proj u11 tests; mkdir -p "$P/test"; cp "$P/tests/test_calc.py" "$P/test/test_other.py"
expect "A11: tests/ and test/ both hold unittest files → both directories run" "$P" "$(either "python3 -m unittest discover -s tests && python3 -m unittest discover -s test")"
unittest_proj u12 tests; mkdir -p "$P/tests/unit"; cp "$P/tests/test_calc.py" "$P/tests/unit/test_deep.py"
expect "A12: a nested test file unittest discovery would skip keeps plain pytest" "$P" "$PYTEST"
unittest_proj u13 tests; printf 'import unittest\n\n\nclass Base(unittest.TestCase):\n    pass\n' > "$P/tests/base.py"
printf 'from base import Base\n\n\nclass ViaBase(Base):\n    def test_x(self):\n        self.assertTrue(True)\n' > "$P/tests/test_via_base.py"
expect "A13: a test file with no direct TestCase subclass keeps plain pytest" "$P" "$PYTEST"
unittest_proj u14 tests; printf '\n\ndef test_broken():\n    assert 1 == 2\n' >> "$P/tests/test_calc.py"
expect "A14: a TestCase file that also has a module-level test function keeps plain pytest (unittest would skip it)" "$P" "$PYTEST"

[ "$FAILS" -eq 0 ] && echo "✅ test_matrix_detect_unittest_fallback: all passed" || { echo "❌ test_matrix_detect_unittest_fallback: $FAILS failed"; exit 1; }
