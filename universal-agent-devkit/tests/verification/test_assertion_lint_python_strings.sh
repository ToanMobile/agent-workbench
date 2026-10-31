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
# x
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

    def test_fixture_then_comment(self):
        script = """
echo hi
"""
        Path("adb").write_text(script)  # assert adb exists

    def test_fixture_then_string_word(self):
        script = """
echo hi
"""
        log("fail() if missing")

    def test_col0_single_string(self):
        run(
"fail() {}",
        )

    def test_fstring_fixture_only(self):
        script = f"""
fail() {{ exit 1; }}
"""
        Path("adb").write_text(script)

    def test_assert_words_in_literals(self):
        assertEqual("assert a", "assert b")

    def test_assert_in_fstring_field(self):
        msg = f"""
{self.assertEqual(f(), 1)}
"""

    def test_masked_twice(self):
        log("assert.assert_called()")

    def test_comment_bridge(self):
        fail  # c
        (1)

    def test_comment_first(self):
        # comment trước dòng đầu của thân
        self.assertTrue(f())
PY

# Thụt lề bằng tab (tokenize: tab nhảy tới bội số 8).
printf 'class Tabs:\n\tdef test_tab_assert(self):\n\t\tself.assertEqual(f(), 1)\n\n\tdef test_tab_empty(self):\n\t\tprint(1)\n' > src/test_tabs.py

# "\f" trong lề (tokenize: cột về 0 tại "\f"): `    \fdef` là lệnh ở cột 0, `\f        self.assertEqual` vẫn trong method.
printf 'def test_ff_empty():\n    pass\n    \fdef test_ff_next():\n    assert x\n' > src/test_ff.py
printf 'class A:\n    def test_ff_assert(self):\n        x = 1\n\f        self.assertEqual(x, 1)\n' > src/test_ff2.py

# Lề tách bởi "\" nối dòng: Python đo lề tới dấu "\" đầu tiên, không phải ở dòng có token.
printf 'class A:\n    def test_bs_empty(self):\n        s = """\nx\n"""\n    \\\n        assert __name__\n' > src/test_bs.py
printf 'class A:\n    def test_bs_assert(self):\n        x = 1\n        \\\n    assert x\n' > src/test_bs2.py
# Test một dòng có "\f" trong chuỗi: thân đọc tới hết dòng `def` (tách ở "\n"), assert sau "\f" vẫn được tính.
printf 'def test_sep_oneliner(): x = "\f"; assert x == 1\n' > src/test_sep1.py

# tokenize ném IndentationError (lề lùi không khớp): quy tắc lề cũ, không traceback.
printf 'def test_indent_err():\n        x = 1\n    y = 2\n' > src/test_indent_err.py

LINT_SCRIPT="$DEVKIT_ROOT/scripts/linters/assertion_lint.py"

OUTPUT=$(python3 -I "$LINT_SCRIPT" src/test_strings.py src/test_broken.py src/test_seps.py src/test_masked.py \
         src/test_tabs.py src/test_indent_err.py src/test_ff.py src/test_ff2.py src/test_bs.py src/test_bs2.py src/test_sep1.py 2>&1)
RC=$?

ERRORS=0

# File chỉ xuống dòng bằng "\r" (gate --staged đọc blob không đổi xuống dòng): quy tắc lề cũ, tách cả ở "\r" — có dòng
# trống ("\r\r", tokenize từ chối) và không có (tokenize nhận nhưng gom cả file thành một dòng).
CR_OUT=$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import assertion_lint as a
print(a.findings("def test_a():\r    pass\r\rdef test_b():\r    assert x\r"), a.findings("def test_a():\r    pass\rdef test_b():\r    assert x\r"))' "$DEVKIT_ROOT/scripts/linters" 2>&1)
if [ "$CR_OUT" = "[(1, 'test_a')] [(1, 'test_a')]" ]; then
    echo "OK: file chỉ có \\r: test_a rỗng bị báo"
else
    echo "FAIL: file chỉ có \\r: $CR_OUT (cần [(1, 'test_a')] [(1, 'test_a')])"
    ERRORS=$((ERRORS+1))
fi

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
expect_not_flagged "src/test_masked.py" "36"   # comment ngắn ở cột 0 giữa thân không cắt thân (comment không mở lệnh)
expect_flagged "src/test_masked.py" "41"       # gõ sai tên mock assert: không phải assertion
expect_flagged "src/test_masked.py" "45"       # `assert` thụt lề trong chuỗi nhiều dòng cũng chỉ là chữ
expect_not_flagged "src/test_masked.py" "51"   # dòng mở chuỗi (assert bọc chuỗi) không bị che
expect_flagged "src/test_masked.py" "56"       # comment `# assert …` sau fixture cột 0 không phải assertion
expect_flagged "src/test_masked.py" "62"       # chữ `fail()` trong chuỗi một dòng không phải assertion
expect_flagged "src/test_masked.py" "68"       # chuỗi một dòng mở ở cột 0
expect_flagged "src/test_masked.py" "73"       # f-string nhiều dòng cũng được che
expect_not_flagged "src/test_masked.py" "79"   # chỉ che phần khớp assertion: hai literal vẫn khác nhau, không thành assertEqual(x, x)
expect_not_flagged "src/test_masked.py" "82"   # code trong {…} của f-string nhiều dòng không bị che
expect_flagged "src/test_masked.py" "87"       # che không tạo khớp mới (`assert` + phần che không thành `assert `)
expect_flagged "src/test_masked.py" "90"       # comment che giữ `#`: `fail` + comment + `(1)` dòng sau không thành `fail(`
expect_not_flagged "src/test_masked.py" "94"   # comment ngay sau dòng `def` (trước INDENT) không kết thúc thân
expect_not_flagged "src/test_tabs.py" "2"
expect_flagged "src/test_tabs.py" "5"
expect_flagged "src/test_indent_err.py" "1"
expect_flagged "src/test_ff.py" "1"            # `    \fdef` ở cột 0 (như tokenize) kết thúc thân test rỗng
expect_not_flagged "src/test_ff2.py" "2"       # `\f` rồi 8 dấu cách: vẫn trong method, assert được tính
expect_flagged "src/test_bs.py" "2"            # `    \` rồi assert: lề 4 (mức class), test rỗng
expect_not_flagged "src/test_bs2.py" "2"       # `        \` rồi assert: lề 8, vẫn trong method
expect_not_flagged "src/test_sep1.py" "1"

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
