#!/bin/bash
# assertion_lint (#1415, OfficeReader PR #506): lời gọi thật `captureRoboImage(` của Roborazzi là assertion (ở chế độ verify nó so ảnh
# với baseline và làm test FAIL khi lệch); chữ `captureRoboImage` chỉ nằm trong comment hoặc chuỗi thì vẫn là test rỗng;
# `setContent {}` không capture vẫn là test rỗng. Không miễn trừ theo tên file hay thư mục.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
cd "$D"

mkdir -p src

cat << 'KOTLIN' > src/HomeScreenScreenshotTest.kt
import org.junit.Test
class HomeScreenScreenshotTest {
    @Test
    fun captureOnRoot() {
        composeTestRule.setContent { HomeScreen() }
        composeTestRule.onRoot().captureRoboImage("build/outputs/roborazzi/home.png")
    }

    @Test
    fun captureTopLevel() {
        captureRoboImage("build/outputs/roborazzi/dialog.png") { Dialog() }
    }

    @Test
    fun setContentOnly() {
        composeTestRule.setContent { HomeScreen() }
    }

    @Test
    fun captureInLineComment() {
        composeTestRule.setContent { HomeScreen() }
        // composeTestRule.onRoot().captureRoboImage("home.png")
    }

    @Test
    fun captureInBlockComment() {
        composeTestRule.setContent { HomeScreen() }
        /* tạm tắt:
           captureRoboImage("home.png")
        */
    }

    @Test
    fun captureInString() {
        composeTestRule.setContent { HomeScreen() }
        println("captureRoboImage(home.png)")
    }

    @Test
    fun captureInRawString() {
        val note = """
            captureRoboImage("home.png")
        """
        println(note)
    }

    @Test
    fun captureAfterUrlString() {
        val url = "https://example.com/a" // ghi chú
        composeTestRule.onRoot().captureRoboImage()
    }

    @Test
    fun captureAfterQuoteChar() {
        val q = '"'
        captureRoboImage("a.png") { Text("x") }
    }

    @Test
    fun captureViaHelper() {
        shoot("home")
    }

    @Test
    fun captureViaCommentOnlyHelper() {
        noShoot("home")
    }

    private fun shoot(name: String) {
        composeTestRule.onRoot().captureRoboImage("build/$name.png")
    }

    private fun noShoot(name: String) {
        // captureRoboImage("build/$name.png")
        println(name)
    }
}
KOTLIN

LINT_SCRIPT="$DEVKIT_ROOT/scripts/linters/assertion_lint.py"
OUTPUT=$(python3 -I "$LINT_SCRIPT" src/HomeScreenScreenshotTest.kt 2>&1)
RC=$?
ERRORS=0

expect_flagged() {
    if echo "$OUTPUT" | grep -q "HomeScreenScreenshotTest.kt:$1:"; then
        echo "OK: dòng $1 bị báo rỗng ($2)"
    else
        echo "FAIL: dòng $1 KHÔNG bị báo rỗng ($2)"
        ERRORS=$((ERRORS+1))
    fi
}

expect_not_flagged() {
    if echo "$OUTPUT" | grep -q "HomeScreenScreenshotTest.kt:$1:"; then
        echo "FAIL: dòng $1 bị báo rỗng ($2)"
        ERRORS=$((ERRORS+1))
    else
        echo "OK: dòng $1 không bị báo ($2)"
    fi
}

# Số dòng là dòng của @Test
expect_not_flagged 3  "AC1: .captureRoboImage(...) trên onRoot()"
expect_not_flagged 9  "AC1: captureRoboImage(...) { } cấp cao nhất"
expect_flagged 14     "AC2: chỉ setContent {} không capture"
expect_flagged 19     "AC3: captureRoboImage chỉ trong comment //"
expect_flagged 25     "AC3: captureRoboImage chỉ trong comment /* */"
expect_flagged 33     "AC3: captureRoboImage chỉ trong chuỗi"
expect_flagged 39     "AC3: captureRoboImage chỉ trong chuỗi thô ba nháy"
expect_not_flagged 47 "chuỗi có // rồi comment thật, capture ở dòng sau vẫn được tính"
expect_not_flagged 53 "ký tự '\"' không mở chuỗi nuốt lời gọi capture"
expect_not_flagged 59 "helper cùng file gọi captureRoboImage thật"
expect_flagged 64     "helper chỉ có captureRoboImage trong comment"

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
