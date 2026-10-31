#!/bin/bash
# assertion_lint (#737, OfficeReader#242): chuỗi nhiều dòng ở cột 0 (script fake adb) không được cắt thân test Python,
# còn test rỗng thật vẫn phải bị báo — không nới linter. Thân method kết thúc ở dòng có lề ≤ lề của chính `def`.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
cd "$D"

mkdir -p src

cat << 'PY' > src/test_strings.py
import unittest
from pathlib import Path


class Strings(unittest.TestCase):
    def test_col0_heredoc_then_assert(self):
        script = """#!/usr/bin/env bash
if [ "$1" = x ]; then
  exit 0
fi
"""
        Path("adb").write_text(script)
        self.assertEqual(Path("adb").read_text(), script)

    def test_col0_fstring_then_assert(self):
        name = "x"
        script = f'''
echo {name}
'''
        self.assertIn(name, script)

    def test_empty_after_heredoc(self):
        script = """
echo hi
"""
        Path("adb").write_text(script)

    def test_empty_quote_marker(self):
        marker = '"""'
        print(marker)

    def test_plain_empty(self):
        value = 1
        print(value)

    def test_next_asserts(self):
        self.assertTrue(Path(".").exists())

    def test_fixture_defines_helper(self):
        src = """
def probe():
    pass
"""
        self.assertIn("probe", src)

    def test_calls_fixture_helper_name(self):
        probe()

    def test_multiline_signature(
        self,
    ) -> None:
        self.assertTrue(Path(".").exists())

    def test_mock_assert_only(self):
        m = Mock()
        m(1)
        m.assert_called_once_with(1)

    def test_mock_call_without_assert(self):
        m = Mock()
        m(1)
PY

# Không tokenize được (chuỗi ba nháy không đóng): quy tắc lề cũ, không traceback.
cat << 'PY' > src/test_broken.py
def test_empty_broken():
    pass

x = """unterminated
PY

# \f và U+2028 (octal của UTF-8) nằm trong chuỗi: không phải xuống dòng, không cắt thân test.
printf 'class Seps:\n    def test_formfeed_in_string(self):\n        s = "a\fb"\n        self.assertEqual(s, "a")\n\n    def test_line_separator_in_string(self):\n        s = "a\342\200\250b"\n        self.assertEqual(s, "a")\n' > src/test_seps.py

# Kéo thân qua chuỗi không được nới linter: chữ trong chuỗi nhiều dòng (dòng thứ hai trở đi) không phải assertion.
cat << 'PY' > src/test_masked.py
import unittest


class Masked(unittest.TestCase):
    def test_fixture_fail_fn_only(self):
        script = """#!/usr/bin/env bash
fail() { exit 1; }
check() { :; }
"""
        Path("adb").write_text(script)

    def test_docstring_col0_assert(self):
        """Doc.
assert nothing here
"""
        print(1)

    def write_fixture(self):
        Path("t.py").write_text("""
self.assertEqual(1, 2)
""")

    def test_only_calls_fixture_writer(self):
        self.write_fixture()

    def test_default_param_string(self, x="""
assert y
"""):
        print(x)

    def test_code_after_closing_quote(self):
        s = """
x
"""; self.assertEqual(s, "x")

    def test_comment_col0_then_assert(self):
        value = 1
# ghi chú ở cột 0
        self.assertEqual(value, 1)

    def test_mock_typo(self):
        m = Mock()
        m.assert_called_onec(1)

    def test_indented_fixture_assert_text(self):
        src = """
            assert x == 1
        """
        print(src)

    def test_assert_opens_string(self):
        self.assertEqual(dedent("""
            a
        """), "a\n")
PY

# Thụt lề bằng tab (tokenize: tab nhảy tới bội số 8).
printf 'class Tabs:\n\tdef test_tab_assert(self):\n\t\tself.assertEqual(f(), 1)\n\n\tdef test_tab_empty(self):\n\t\tprint(1)\n' > src/test_tabs.py

# tokenize ném IndentationError (lề lùi không khớp): quy tắc lề cũ, không traceback.
printf 'def test_indent_err():\n        x = 1\n    y = 2\n' > src/test_indent_err.py

LINT_SCRIPT="$DEVKIT_ROOT/scripts/linters/assertion_lint.py"

OUTPUT=$(python3 -I "$LINT_SCRIPT" src/test_strings.py src/test_broken.py src/test_seps.py src/test_masked.py \
         src/test_tabs.py src/test_indent_err.py 2>&1)
RC=$?

ERRORS=0

function expect_flagged() {
    if echo "$OUTPUT" | grep -q "$1:$2:"; then
        echo "OK: $1:$2 was flagged"
    else
        echo "FAIL: $1:$2 was NOT flagged"
        ERRORS=$((ERRORS+1))
    fi
}

function expect_not_flagged() {
    if echo "$OUTPUT" | grep -q "$1:$2:"; then
        echo "FAIL: $1:$2 was flagged"
        ERRORS=$((ERRORS+1))
    else
        echo "OK: $1:$2 was NOT flagged"
    fi
}

# Dòng của `def test_…`
expect_not_flagged "src/test_strings.py" "6"   # chuỗi """ có dòng cột 0, assert sau chuỗi
expect_not_flagged "src/test_strings.py" "15"  # f''' có dòng cột 0, assert sau chuỗi
expect_flagged "src/test_strings.py" "22"      # rỗng thật sau chuỗi nhiều dòng
expect_flagged "src/test_strings.py" "28"      # '"""' một dòng không mở chuỗi, không nuốt assert của test sau
expect_flagged "src/test_strings.py" "32"      # thân method dừng ở method kế tiếp (lề của def), không kéo tới cột 0
expect_not_flagged "src/test_strings.py" "36"
expect_not_flagged "src/test_strings.py" "39"  # `def probe():` cột 0 trong chuỗi fixture không cắt thân test
expect_flagged "src/test_strings.py" "46"      # `def` trong chuỗi giữ quy tắc lề cũ: probe không thành helper có assert
expect_not_flagged "src/test_strings.py" "49"  # `) -> None:` của chữ ký nhiều dòng là dòng tiếp nối, không cắt thân
expect_not_flagged "src/test_strings.py" "54"  # mock .assert_called_once_with là assertion (như verify của Mockito)
expect_flagged "src/test_strings.py" "59"      # gọi mock mà không assert: rỗng
expect_flagged "src/test_broken.py" "1"
expect_not_flagged "src/test_seps.py" "2"      # \f trong chuỗi
expect_not_flagged "src/test_seps.py" "6"      # U+2028 trong chuỗi
expect_flagged "src/test_masked.py" "5"        # fixture bash có `fail() {` / `check()`: rỗng
expect_flagged "src/test_masked.py" "12"       # docstring có dòng `assert` ở cột 0: rỗng
expect_flagged "src/test_masked.py" "23"       # helper chỉ ghi chuỗi có `self.assertEqual(` không thành helper có assert
expect_flagged "src/test_masked.py" "26"       # default của tham số là chuỗi nhiều dòng có `assert`
expect_not_flagged "src/test_masked.py" "31"   # code sau dấu đóng chuỗi trên cùng dòng vẫn được đọc
expect_not_flagged "src/test_masked.py" "36"   # comment ở cột 0 giữa thân không cắt thân
expect_flagged "src/test_masked.py" "41"       # gõ sai tên mock assert: không phải assertion
expect_flagged "src/test_masked.py" "45"       # `assert` thụt lề trong chuỗi nhiều dòng cũng chỉ là chữ
expect_not_flagged "src/test_masked.py" "51"   # dòng mở chuỗi (assert bọc chuỗi) không bị che
expect_not_flagged "src/test_tabs.py" "2"
expect_flagged "src/test_tabs.py" "5"
expect_flagged "src/test_indent_err.py" "1"

if [ "$RC" -ne 1 ] || echo "$OUTPUT" | grep -q "Traceback"; then
    echo "FAIL: rc=$RC (cần 1, không traceback)"
    ERRORS=$((ERRORS+1))
fi

if [ $ERRORS -gt 0 ]; then
    echo "$ERRORS FAILED"
    echo "Output was:"
    echo "$OUTPUT"
    exit 1
else
    echo "ALL OK"
    exit 0
fi
