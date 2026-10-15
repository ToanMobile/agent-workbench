#!/usr/bin/env bash
# docs/workflow-improvements.md I.3 P4: when logic is pulled out of an Android View into a new `internal object`, a test of the object alone
# proves nothing about the View (reverting the View's call site leaves it green: the vacuity gate called such a test empty). scripts/linters/
# wiring_pin.py scan finds that situation (new internal object next to a View file, no test names the View) and prints a source-text pin test
# skeleton: the View still names the object, and no longer holds the old branch. `verify` evaluates THE GENERATED FILE'S OWN LITERALS
# against the View source (kotlinc is not available here, so the Kotlin skeleton itself is not compiled: it is generated, then read back).
#   RED/GREEN on a fixture: pin saved -> verify exits 0; the View's call site reverted -> verify exits 1.
# bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WP="${WP_SCRIPT:-$DEVKIT_DIR/scripts/linters/wiring_pin.py}"   # WP_SCRIPT: a mutant, for the mutation check
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd -P "$TMP" && pwd -P)"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
[ -f "$WP" ] || { fail "scripts/linters/wiring_pin.py does not exist"; echo "❌ test_wiring_pin: $FAILS failed"; exit 1; }

R="$TMP/repo"; V="$R/app/src/main/java/com/x"; T="$R/app/src/test/java/com/x"
mkdir -p "$V" "$T"
git -C "$R" init -q . && git -C "$R" config user.email t@t && git -C "$R" config user.name t && git -C "$R" config commit.gpgsign false
printf 'plugins { id("com.android.application") }\n' > "$R/app/build.gradle.kts"
cat > "$V/SelectionView.kt" <<'KT'
package com.x

import android.content.Context
import android.util.Log
import android.view.View

class SelectionView(context: Context) : View(context) {
    fun pick(startDistance: Int, endDistance: Int): Int {
        Log.d("sel", "pick $startDistance")
        val chosen = if (startDistance <= endDistance) START else END
        return chosen
    }
    companion object { const val START = 0; const val END = 1 }
}
KT
cp "$V/SelectionView.kt" "$TMP/SelectionView.old.kt"
git -C "$R" add -A && git -C "$R" commit -q -m base

# the refactor, uncommitted: a new internal object, the View calls it, the old branch is gone, a test of the object alone
cat > "$V/SelectionRules.kt" <<'KT'
package com.x

internal object SelectionRules {
    fun pick(startDistance: Int, endDistance: Int): Int = if (startDistance <= endDistance) 0 else 1
}
KT
cat > "$V/SelectionView.kt" <<'KT'
package com.x

import android.content.Context
import android.view.View

class SelectionView(context: Context) : View(context) {
    fun pick(startDistance: Int, endDistance: Int): Int {
        val chosen = SelectionRules.pick(startDistance, endDistance)
        return chosen
    }
    companion object { const val START = 0; const val END = 1 }
}
KT
cat > "$T/SelectionRulesTest.kt" <<'KT'
package com.x

import org.junit.Assert.assertEquals
import org.junit.Test

class SelectionRulesTest {
    @Test fun nearestWins() { assertEquals(1, SelectionRules.pick(60, 10)) }
}
KT

# 1. scan: the object-only test is found, a skeleton is printed
( cd "$R" && python3 -I "$WP" scan > "$TMP/scan.out" 2> "$TMP/scan.err" ); rc=$?
[ "$rc" = 1 ] && ok "scan exits 1: a pin is needed" || fail "scan exit $rc (want 1): $(cat "$TMP/scan.err")"
[ "${WP_SHOW:-0}" = 1 ] && cat "$TMP/scan.out"
grep -q "SelectionRules" "$TMP/scan.out" && grep -q "SelectionView" "$TMP/scan.out" && ok "scan names the object and the View" || fail "scan output lacks the object / View: $(cat "$TMP/scan.out")"
grep -q "SelectionRulesTest.kt" "$TMP/scan.out" && grep -q "tests that name SelectionView: none" "$TMP/scan.out" \
  && ok "scan says the tests name only the object" || fail "scan does not report the object-only test"
grep -q "save as: app/src/test/java/com/x/SelectionViewWiringPinTest.kt" "$TMP/scan.out" && ok "scan suggests the pin's path next to the module's tests" || fail "no save-as path"
grep -qiE "TODO|FIXME|Logic to check" "$TMP/scan.out" && fail "the skeleton carries a placeholder word" || ok "no placeholder word in the skeleton"
PIN="$TMP/pin.kt"
awk '/^----8<----$/{n++; next} n==1{print}' "$TMP/scan.out" > "$PIN"
grep -q 'view.contains("SelectionRules.")' "$PIN" && ok "pin asserts the View still calls SelectionRules" || fail "pin lacks the call assertion"
grep -q 'assertFalse' "$PIN" && grep -qF 'val chosen = if (startDistance <= endDistance) START else END' "$PIN" \
  && ok "pin asserts the removed branch is not back (the removed line is the marker)" || fail "pin lacks the old-branch assertion"
grep -qF 'Log.d(\"sel\", \"pick \$startDistance\")' "$PIN" && ok "quotes and \$ in a marker are Kotlin-escaped" || fail "marker not escaped for Kotlin: $(grep -n 'Log.d' "$PIN")"
grep -q 'File("src/main/java/com/x/SelectionView.kt")' "$PIN" && ok "the View path is relative to the module (Gradle runs tests with cwd = module dir)" || fail "pin path is not module-relative"
grep -q '^package com.x$' "$PIN" && grep -q '^import org.junit.Test$' "$PIN" && ok "pin has the View's package and its imports" || fail "pin lacks package/imports"
open_b="$(grep -o '{' "$PIN" | wc -l | tr -d ' ')"; close_b="$(grep -o '}' "$PIN" | wc -l | tr -d ' ')"
[ "$open_b" = "$close_b" ] && ok "pin braces balance" || fail "pin braces unbalanced ($open_b vs $close_b)"

# 2. GREEN: saved next to the module's tests, verify holds on the refactored tree
cp "$PIN" "$T/SelectionViewWiringPinTest.kt"
( cd "$R/app" && python3 -I "$WP" verify src/test/java/com/x/SelectionViewWiringPinTest.kt > "$TMP/v1.out" 2>&1 ); rc=$?
[ "$rc" = 0 ] && ok "verify GREEN: the View calls the object and the old branch is gone (exit 0)" || fail "verify exit $rc on the good tree: $(cat "$TMP/v1.out")"

# 3. once pinned, scan is quiet (a test now names the View)
( cd "$R" && python3 -I "$WP" scan > "$TMP/scan2.out" 2>&1 ); rc=$?
[ "$rc" = 0 ] && ok "scan is quiet once the pin exists (exit 0)" || fail "scan after the pin exit $rc: $(cat "$TMP/scan2.out")"

# 4. RED: revert the View's call site (the base version comes back: old branch in, call out)
cp "$V/SelectionView.kt" "$TMP/SelectionView.new.kt"
cp "$TMP/SelectionView.old.kt" "$V/SelectionView.kt"
( cd "$R/app" && python3 -I "$WP" verify src/test/java/com/x/SelectionViewWiringPinTest.kt > "$TMP/v2.out" 2>&1 ); rc=$?
[ "$rc" = 1 ] && ok "verify RED: reverting the View's call site turns the pin red (exit 1)" || fail "verify exit $rc after the revert (want 1): $(cat "$TMP/v2.out")"
grep -q "SelectionRules\." "$TMP/v2.out" && grep -q "old branch" "$TMP/v2.out" && ok "  … and says both: the call is gone and the old branch is back" || fail "verify output: $(cat "$TMP/v2.out")"
# half revert: the call is still there but the old branch was pasted back
{ cat "$TMP/SelectionView.new.kt"; printf '    // val chosen = if (startDistance <= endDistance) START else END\n'; } > "$V/SelectionView.kt"
( cd "$R/app" && python3 -I "$WP" verify src/test/java/com/x/SelectionViewWiringPinTest.kt > "$TMP/v3.out" 2>&1 ); rc=$?
[ "$rc" = 1 ] && ok "verify RED: the old branch pasted back next to the call also fails" || fail "verify exit $rc for the half revert (want 1)"
cp "$TMP/SelectionView.new.kt" "$V/SelectionView.kt"

# 5. unwired: the object exists, no View names it, and the pin file is not there yet
rm -f "$T/SelectionViewWiringPinTest.kt"
cp "$TMP/SelectionView.old.kt" "$V/SelectionView.kt"
( cd "$R" && python3 -I "$WP" scan > "$TMP/scan3.out" 2>&1 ); rc=$?
[ "$rc" = 1 ] && grep -q "UNWIRED" "$TMP/scan3.out" && ok "scan reports an object no View names as UNWIRED (exit 1)" || fail "unwired: exit $rc: $(cat "$TMP/scan3.out")"
cp "$TMP/SelectionView.new.kt" "$V/SelectionView.kt"

# 6. quiet cases: a test that names the View itself; a clean tree; no View next to the object
cat > "$T/SelectionViewTest.kt" <<'KT'
package com.x
class SelectionViewTest { fun t() { SelectionView(null!!) } }
KT
( cd "$R" && python3 -I "$WP" scan > "$TMP/scan4.out" 2>&1 ); rc=$?
[ "$rc" = 0 ] && ok "a test that names the View: nothing to pin (exit 0)" || fail "covered View: exit $rc: $(cat "$TMP/scan4.out")"
rm -f "$T/SelectionViewTest.kt"
mkdir -p "$R/lib/src/main/java/com/y"
printf 'package com.y\n\ninternal object Helpers { fun f() = 1 }\n' > "$R/lib/src/main/java/com/y/Helpers.kt"
printf 'package com.y\n\nclass Plain { fun g() = 2 }\n' > "$R/lib/src/main/java/com/y/Plain.kt"
rm -f "$V/SelectionRules.kt" "$T/SelectionRulesTest.kt"; cp "$TMP/SelectionView.old.kt" "$V/SelectionView.kt"
( cd "$R" && python3 -I "$WP" scan > "$TMP/scan5.out" 2>&1 ); rc=$?
[ "$rc" = 0 ] && ok "a new internal object with no View beside it, and an untouched View: exit 0" || fail "no-view case exit $rc: $(cat "$TMP/scan5.out")"

# 7. usage and fail-closed
python3 -I "$WP" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "no subcommand: exit 2" || fail "no subcommand exit $rc (want 2)"
( cd "$R/app" && python3 -I "$WP" verify "$V/SelectionView.kt" >/dev/null 2>&1 ); rc=$?
[ "$rc" = 2 ] && ok "verify of a file that is not a generated pin: exit 2 (fail closed)" || fail "verify of a non-pin exit $rc (want 2)"
( cd "$TMP" && python3 -I "$WP" scan >/dev/null 2>&1 ); rc=$?
[ "$rc" = 2 ] && ok "scan outside a git repo: exit 2" || fail "scan outside a repo exit $rc (want 2)"
head -12 "$WP" | grep -qi "regex" && ok "the header says regex-based, not a Kotlin parser" || fail "header does not say regex-based"

# 8. the documented rule: android-rules.md section 16 (on-demand block; no MUST-word there) and the linters README name the tool
RULES="$DEVKIT_DIR/profiles/android/rules/android-rules.md"
BLOCK="$(awk '/^<!-- on-demand: §16 /{on=1} on{print} on&&/^<!-- \/on-demand -->/{exit}' "$RULES")"
printf '%s\n' "$BLOCK" | grep -q 'wiring_pin.py scan' && printf '%s\n' "$BLOCK" | grep -q 'wiring_pin.py verify' \
  && printf '%s\n' "$BLOCK" | grep -q 'internal object' && printf '%s\n' "$BLOCK" | grep -qi 'revert' \
  && ok "android-rules.md section 16 documents the rule: extract into an internal object -> scan, save the pin, verify" || fail "android-rules.md section 16 does not document wiring_pin.py scan/verify"
printf '%s\n' "$BLOCK" | grep 'wiring_pin' | grep -qE 'BẮT BUỘC|[Bb]ắt buộc|MUST|CẤM|[Cc]ấm|bất biến|Bất biến|Nghiêm cấm|Tuyệt đối' \
  && fail "the wiring-pin rule line uses a MUST-word (the on-demand split rejects it)" || ok "no MUST-word on the wiring-pin rule lines"
grep -q 'wiring_pin.py' "$DEVKIT_DIR/scripts/linters/README.md" && ok "scripts/linters/README.md lists wiring_pin.py" || fail "scripts/linters/README.md does not list wiring_pin.py"

[ "$FAILS" -eq 0 ] && echo "✅ test_wiring_pin: all passed" || { echo "❌ test_wiring_pin: $FAILS failed"; exit 1; }
