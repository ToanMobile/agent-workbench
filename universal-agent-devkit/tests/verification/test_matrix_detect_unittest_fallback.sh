#!/usr/bin/env bash
# Hồi quy (13/11, audit prompt cài đặt): matrix_detect chọn `python3 -m pytest -q` cho mọi repo có tests/test_*.py mà không kiểm python3
# của máy có pytest hay không. Đo thật: repo thử Python (test viết bằng unittest) trên máy chưa cài pytest → gate REJECT, "Test hồi quy
# đạt: 0/1", log "No module named pytest" (14:07:37 và 14:24:57). Nay khi dự án KHÔNG khai báo pytest, python3 không import được pytest
# và file test dùng unittest thì ma trận chạy `python3 -m unittest discover -s <thư mục test>`. Mọi trường hợp khác giữ nguyên pytest:
# dự án khai báo pytest (pytest.ini, conftest.py, tox.ini, pyproject/setup.cfg), máy có pytest, hoặc test viết kiểu pytest.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # không thừa hưởng GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MD="$DEVKIT_DIR/scripts/governance/matrix_detect.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
unset CLAUDE_PROJECT_DIR TARGET_DIR DEVKIT_SOURCE_EXTS
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# cmds <dự án> <1|0: python3 có pytest không> → các lệnh detect() chọn, nối bằng " | ". Không phụ thuộc máy chạy test có pytest hay không.
cmds() {
  python3 - "$MD" "$1" "$2" <<'PY' 2>&1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("matrix_detect", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m._pytest_available = lambda: sys.argv[3] == "1"
print(" | ".join(cmd for _, cmd in m.detect(sys.argv[2])))
PY
}
expect() {  # mô tả, dự án, có pytest, lệnh mong đợi
  local got; got="$(cmds "$2" "$3" | tail -1)"
  [ "$got" = "$4" ] && ok "$1" || fail "$1: got '$(printf '%s' "$got" | cut -c1-160)', expected '$4'"
}
unittest_proj() {  # $1 = tên, $2 = thư mục test (tests|test)
  P="$TMP/$1"; mkdir -p "$P/$2"
  printf 'def add(a, b):\n    return a + b\n' > "$P/calc.py"
  printf 'import unittest\n\nimport calc\n\n\nclass AddTest(unittest.TestCase):\n    def test_add(self):\n        self.assertEqual(calc.add(2, 3), 5)\n' > "$P/$2/test_calc.py"
}

unittest_proj u1 tests
expect "A1: unittest tests, pytest not importable → unittest discover" "$P" 0 "python3 -m unittest discover -s tests"
expect "A2: the same project on a machine with pytest → pytest (unchanged)" "$P" 1 "python3 -m pytest -q"
# Chạy thật lệnh A1 từ gốc dự án: nó phải tìm thấy test và import được module ở gốc.
out="$(cd "$P" && python3 -m unittest discover -s tests 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'Ran 1 test'; } && ok "A1b: the generated unittest command really runs the project's test (exit 0, Ran 1 test)" \
  || fail "A1b: 'python3 -m unittest discover -s tests' exit $rc: $(printf '%s' "$out" | tail -2 | tr '\n' ' ' | cut -c1-160)"
unittest_proj u2 test
expect "A3: tests under test/ → discover -s test" "$P" 0 "python3 -m unittest discover -s test"
unittest_proj u3 tests; : > "$P/conftest.py"
expect "A4: a project that declares pytest (conftest.py) keeps pytest even when it is not importable" "$P" 0 "python3 -m pytest -q"
unittest_proj u4 tests; printf '[tool.pytest.ini_options]\naddopts = "-q"\n' > "$P/pyproject.toml"
expect "A5: pytest named in pyproject.toml keeps pytest" "$P" 0 "python3 -m pytest -q"
P="$TMP/u5"; mkdir -p "$P/tests"; printf 'def test_add():\n    assert 1 + 1 == 2\n' > "$P/tests/test_plain.py"
expect "A6: pytest-style tests (no unittest import) keep pytest: unittest would run nothing" "$P" 0 "python3 -m pytest -q"
P="$TMP/u6"; mkdir -p "$P/tests"; printf '# import unittest is only mentioned in a comment\ndef test_x():\n    assert True\n' > "$P/tests/test_c.py"
expect "A7: 'import unittest' inside a comment is not a unittest test" "$P" 0 "python3 -m pytest -q"

[ "$FAILS" -eq 0 ] && echo "✅ test_matrix_detect_unittest_fallback: all passed" || { echo "❌ test_matrix_detect_unittest_fallback: $FAILS failed"; exit 1; }
