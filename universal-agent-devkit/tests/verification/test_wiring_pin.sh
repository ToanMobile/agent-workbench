#!/usr/bin/env bash
# When logic is pulled out of an Android View into a new `internal object`, a test of the object alone
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
grep -q "SelectionRulesTest.kt" "$TMP/scan.out" && grep -q "tests that name both SelectionRules and SelectionView: none" "$TMP/scan.out" \
  && ok "scan says the tests name only the object, none names the pair" || fail "scan does not report the object-only test"
grep -q "save as: app/src/test/java/com/x/SelectionViewSelectionRulesWiringPinTest.kt" "$TMP/scan.out" && ok "scan suggests the pin's path next to the module's tests" || fail "no save-as path"
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
cp "$PIN" "$T/SelectionViewSelectionRulesWiringPinTest.kt"
( cd "$R/app" && python3 -I "$WP" verify src/test/java/com/x/SelectionViewSelectionRulesWiringPinTest.kt > "$TMP/v1.out" 2>&1 ); rc=$?
[ "$rc" = 0 ] && ok "verify GREEN: the View calls the object and the old branch is gone (exit 0)" || fail "verify exit $rc on the good tree: $(cat "$TMP/v1.out")"
# the 'then:' line scan printed is a command that runs AS PRINTED from the repo root it names (the old hint put a repo-root path next to a
# module-dir cwd: run from the module dir it said BROKEN on a correct pin, run from the root it held)
HINT="$(sed -n 's/^  then: //p' "$TMP/scan.out" | head -1)"
grep -q 'run that from the repo root' "$TMP/scan.out" && ok "scan says which directory the 'then:' command runs from" || fail "scan does not say where to run the 'then:' command: $(grep -n 'then' "$TMP/scan.out")"
( cd "$R" && bash -c "$HINT" > "$TMP/hint.out" 2>&1 ); rc=$?
[ -n "$HINT" ] && [ "$rc" = 0 ] && grep -q 'wiring pin holds' "$TMP/hint.out" && ok "the printed 'then:' command, run as printed from the repo root, says the pin holds" || fail "printed 'then:' command: rc=$rc hint='$HINT' $(cat "$TMP/hint.out")"

# 3. once pinned, scan is quiet (a test now names the View)
( cd "$R" && python3 -I "$WP" scan > "$TMP/scan2.out" 2>&1 ); rc=$?
[ "$rc" = 0 ] && ok "scan is quiet once the pin exists (exit 0)" || fail "scan after the pin exit $rc: $(cat "$TMP/scan2.out")"

# 4. RED: revert the View's call site (the base version comes back: old branch in, call out)
cp "$V/SelectionView.kt" "$TMP/SelectionView.new.kt"
cp "$TMP/SelectionView.old.kt" "$V/SelectionView.kt"
( cd "$R/app" && python3 -I "$WP" verify src/test/java/com/x/SelectionViewSelectionRulesWiringPinTest.kt > "$TMP/v2.out" 2>&1 ); rc=$?
[ "$rc" = 1 ] && ok "verify RED: reverting the View's call site turns the pin red (exit 1)" || fail "verify exit $rc after the revert (want 1): $(cat "$TMP/v2.out")"
grep -q "SelectionRules\." "$TMP/v2.out" && grep -q "old branch" "$TMP/v2.out" && ok "  … and says both: the call is gone and the old branch is back" || fail "verify output: $(cat "$TMP/v2.out")"
# half revert: the call is still there but the old branch was pasted back
{ cat "$TMP/SelectionView.new.kt"; printf '    // val chosen = if (startDistance <= endDistance) START else END\n'; } > "$V/SelectionView.kt"
( cd "$R/app" && python3 -I "$WP" verify src/test/java/com/x/SelectionViewSelectionRulesWiringPinTest.kt > "$TMP/v3.out" 2>&1 ); rc=$?
[ "$rc" = 1 ] && ok "verify RED: the old branch pasted back next to the call also fails" || fail "verify exit $rc for the half revert (want 1)"
cp "$TMP/SelectionView.new.kt" "$V/SelectionView.kt"

# 5. unwired: the object exists, no View names it, and the pin file is not there yet
rm -f "$T/SelectionViewSelectionRulesWiringPinTest.kt"
cp "$TMP/SelectionView.old.kt" "$V/SelectionView.kt"
( cd "$R" && python3 -I "$WP" scan > "$TMP/scan3.out" 2>&1 ); rc=$?
[ "$rc" = 1 ] && grep -q "UNWIRED" "$TMP/scan3.out" && ok "scan reports an object no View names as UNWIRED (exit 1)" || fail "unwired: exit $rc: $(cat "$TMP/scan3.out")"
cp "$TMP/SelectionView.new.kt" "$V/SelectionView.kt"

# 6. a test that names the View AND the object covers the pair; a test that names only the View does not (review of lane A11: the View-only
#    test, like the saved pin of ANOTHER object, said nothing about this object's wiring). A clean tree and a View-less object stay quiet.
cat > "$T/SelectionViewTest.kt" <<'KT'
package com.x
class SelectionViewTest { fun t() { SelectionView(null!!) } }
KT
( cd "$R" && python3 -I "$WP" scan > "$TMP/scan4.out" 2>&1 ); rc=$?
[ "$rc" = 1 ] && grep -q 'PIN NEEDED' "$TMP/scan4.out" && ok "a test that names only the View does not cover the object's wiring: PIN NEEDED (exit 1)" || fail "View-only test: exit $rc: $(cat "$TMP/scan4.out")"
cat > "$T/SelectionViewTest.kt" <<'KT'
package com.x
class SelectionViewTest { fun t() { SelectionView(null!!); SelectionRules.pick(1, 2) } }
KT
( cd "$R" && python3 -I "$WP" scan > "$TMP/scan4.out" 2>&1 ); rc=$?
[ "$rc" = 0 ] && ok "a test that names both the View and the object: nothing to pin (exit 0)" || fail "covered pair: exit $rc: $(cat "$TMP/scan4.out")"
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
# the rule says what scan now decides (review of lane A11): the pair, per-pair pins, the printed verify command, UNPINNABLE, comments are no call
for pin in 'cả `View` lẫn object đó' 'từng cặp (View, object)' 'đúng lệnh `wiring_pin.py verify' 'từ gốc repo' 'UNPINNABLE' 'comment, KDoc hay chuỗi ký tự không tính' 'thoát 2'; do
  printf '%s\n' "$BLOCK" | grep -qF -- "$pin" && ok "android-rules.md section 16 says: $pin" || fail "android-rules.md section 16 lacks: $pin"
done
grep -q 'UNPINNABLE' "$DEVKIT_DIR/scripts/linters/README.md" && grep -q 'cả `View` lẫn object' "$DEVKIT_DIR/scripts/linters/README.md" && ok "scripts/linters/README.md says the pair rule and UNPINNABLE" || fail "scripts/linters/README.md is out of date with scan"

# ── review of lane A11: verify must not say "holds" for a pin it cannot fully read, or one that proves nothing ────────────────────────────
# `verify` runs against a plain directory (no git): VR holds the View under test; the pins below are written by hand with known literals.
VR="$TMP/vroot"; mkdir -p "$VR/src/main/java/com/x"; VIEWF="$VR/src/main/java/com/x/SelectionView.kt"
vrf() { python3 -I "$WP" verify "$1" --root "${2:-$VR}" > "$TMP/vrf.out" 2>&1; VRC=$?; }
pin_head() { printf 'package com.x\n\nimport java.io.File\nimport org.junit.Assert.assertFalse\nimport org.junit.Assert.assertTrue\nimport org.junit.Test\n\nclass %s {\n    private val view = File("%s").readText()\n\n' "$1" "${2:-src/main/java/com/x/SelectionView.kt}"; }
OLDBR='val chosen = if (startDistance <= endDistance) START else END'
cp "$TMP/SelectionView.new.kt" "$VIEWF"
# a View whose call site was reverted WITHOUT the old branch coming back: only the call assertion can catch it
sed 's/SelectionRules\./Other./' "$TMP/SelectionView.new.kt" > "$TMP/SelectionView.nocall.kt"

# V1. a formatter (ktlint / Spotless) wrapped the call assertion and added a trailing comma: it used to be dropped silently, so the pin said
#     "holds" for a View that no longer calls the object. Now it is read (and the plain old-branch assertion is still read).
{ pin_head WrappedPinTest
  printf '    @Test\n    fun viewStillCallsSelectionRules() {\n        assertTrue(\n            "SelectionView must call SelectionRules",\n            view.contains("SelectionRules."),\n        )\n    }\n\n'
  printf '    @Test\n    fun viewNoLongerHoldsTheOldBranch() {\n        assertFalse("old branch is back in SelectionView: %s", view.contains("%s"))\n    }\n}\n' "$OLDBR" "$OLDBR"; } > "$TMP/wrapped.pin.kt"
vrf "$TMP/wrapped.pin.kt"
[ "$VRC" = 0 ] && ok "a formatter-wrapped call assertion (trailing comma, line breaks) is read: good View holds" || fail "wrapped pin on the good View: rc=$VRC $(cat "$TMP/vrf.out")"
cp "$TMP/SelectionView.nocall.kt" "$VIEWF"; vrf "$TMP/wrapped.pin.kt"
[ "$VRC" = 1 ] && grep -q 'SelectionRules\.' "$TMP/vrf.out" && ok "  … and it turns RED when the View no longer calls the object (it used to be dropped: exit 0)" || fail "wrapped pin, call reverted: rc=$VRC (want 1) $(cat "$TMP/vrf.out")"
# a shape verify cannot evaluate (the pin has more view.contains( calls than assertions it reads): fail closed, exit 2
{ pin_head OddPinTest
  printf '    @Test\n    fun viewStillCalls() {\n        assertTrue("m", view.contains("SelectionRules.") || view.contains("Other."))\n    }\n\n'
  printf '    @Test\n    fun viewNoLongerHoldsTheOldBranch() {\n        assertFalse("old", view.contains("%s"))\n    }\n}\n' "$OLDBR"; } > "$TMP/odd.pin.kt"
cp "$TMP/SelectionView.nocall.kt" "$VIEWF"; vrf "$TMP/odd.pin.kt"
[ "$VRC" = 2 ] && grep -qi 'view.contains' "$TMP/vrf.out" && ok "a pin with a view.contains( it cannot read as an assertion: exit 2, fail closed (the call is gone, yet it must not say holds)" || fail "unreadable assertion shape: rc=$VRC $(cat "$TMP/vrf.out")"
# the count is of CODE: a marker (a removed View line) that itself contains view.contains(...) inside a string or a comment does not trip it
{ pin_head QuotePinTest
  printf '    // note: assertFalse("x", view.contains("never evaluated"))\n    @Test\n    fun viewStillCalls() {\n        assertTrue("m", view.contains("SelectionRules."))\n    }\n\n'
  printf '    @Test\n    fun viewNoLongerHoldsTheOldBranch() {\n        assertFalse("old branch is back: val ok = view.contains(\\"zzz\\")", view.contains("val ok = view.contains(\\"zzz\\")"))\n    }\n}\n'; } > "$TMP/quote.pin.kt"
cp "$TMP/SelectionView.new.kt" "$VIEWF"; vrf "$TMP/quote.pin.kt"
[ "$VRC" = 0 ] && ok "view.contains( inside a string literal or a comment of the pin is not counted as an assertion (good View holds)" || fail "view.contains( in a string/comment: rc=$VRC $(cat "$TMP/vrf.out")"

# V2. the File("...") path of a pin is confined to --root: a ../ path used to be read and "hold"
printf 'SelectionRules.\n' > "$TMP/outside.txt"
{ pin_head EscapePinTest "../../outside.txt"
  printf '    @Test\n    fun viewStillCalls() {\n        assertTrue("m", view.contains("SelectionRules."))\n    }\n\n'
  printf '    @Test\n    fun viewNoLongerHoldsTheOldBranch() {\n        assertFalse("old", view.contains("%s"))\n    }\n}\n' "$OLDBR"; } > "$TMP/escape.pin.kt"
mkdir -p "$TMP/sub1/sub2"; vrf "$TMP/escape.pin.kt" "$TMP/sub1/sub2"
[ "$VRC" = 2 ] && grep -qi 'outside' "$TMP/vrf.out" && ok "a pin whose File(...) path leaves --root is refused (exit 2); it used to read the outside file and hold" || fail "escaping path: rc=$VRC (want 2) $(cat "$TMP/vrf.out")"
sed 's#File("[^"]*")#File("/etc/hosts")#' "$TMP/escape.pin.kt" > "$TMP/abs.pin.kt"; vrf "$TMP/abs.pin.kt"
[ "$VRC" = 2 ] && ok "an absolute File(...) path is refused too (exit 2)" || fail "absolute path: rc=$VRC (want 2)"

# V3. a call that exists only in a comment or KDoc is not a call (the old-branch assertions stay on the raw text: step 4 pastes it as a comment)
{ cat <<'KT'
package com.x

import android.content.Context
import android.view.View

/** Delegates to SelectionRules.pick (see the rules file). */
class SelectionView(context: Context) : View(context) {
    // val chosen = SelectionRules.pick(startDistance, endDistance)
    fun pick(startDistance: Int, endDistance: Int): Int = 0
}
KT
} > "$VIEWF"
vrf "$TMP/wrapped.pin.kt"
[ "$VRC" = 1 ] && grep -q 'SelectionRules\.' "$TMP/vrf.out" && ok "a call mentioned only in a KDoc / line comment does not satisfy the call assertion (exit 1)" || fail "comment-only call: rc=$VRC (want 1) $(cat "$TMP/vrf.out")"

# V4. a pin whose old-branch half is EMPTY (an older scan emitted it when no removed line qualified) proves nothing: not a complete pin
{ pin_head EmptyPinTest
  printf '    @Test\n    fun viewStillCalls() {\n        assertTrue("m", view.contains("SelectionRules."))\n    }\n\n'
  printf '    @Test\n    fun viewNoLongerHoldsTheOldBranch() {\n        // no removed line qualified as a marker\n    }\n}\n'; } > "$TMP/empty.pin.kt"
cp "$TMP/SelectionView.new.kt" "$VIEWF"; vrf "$TMP/empty.pin.kt"
[ "$VRC" = 2 ] && grep -qi 'old-branch\|old branch' "$TMP/vrf.out" && ok "a pin with no old-branch assertion is refused (exit 2): it used to say holds" || fail "empty old-branch half: rc=$VRC (want 2) $(cat "$TMP/vrf.out")"

# V5. the formatter shape with a trailing comma INSIDE view.contains( ... ) too (ktlint puts one after a wrapped last argument)
{ pin_head InnerCommaPinTest
  printf '    @Test\n    fun viewStillCalls() {\n        assertTrue(\n            "SelectionView must call SelectionRules",\n            view.contains(\n                "SelectionRules.",\n            ),\n        )\n    }\n\n'
  printf '    @Test\n    fun viewNoLongerHoldsTheOldBranch() {\n        assertFalse("old branch is back", view.contains("%s"))\n    }\n}\n' "$OLDBR"; } > "$TMP/innercomma.pin.kt"
cp "$TMP/SelectionView.new.kt" "$VIEWF"; vrf "$TMP/innercomma.pin.kt"
[ "$VRC" = 0 ] && ok "a trailing comma inside view.contains( ... ) is read: good View holds" || fail "inner trailing comma on the good View: rc=$VRC (want 0) $(cat "$TMP/vrf.out")"
cp "$TMP/SelectionView.nocall.kt" "$VIEWF"; vrf "$TMP/innercomma.pin.kt"
[ "$VRC" = 1 ] && ok "  … and it turns RED when the call is gone" || fail "inner trailing comma, call reverted: rc=$VRC (want 1) $(cat "$TMP/vrf.out")"

# V6. a decoy: an assertion-shaped text inside a raw string of the pin is not an assertion. With ONE real call verify cannot read next to it, the
#     counts matched (decoy read, real one skipped) and verify said holds; the decoy no longer counts, so the counts differ: exit 2.
{ pin_head DecoyPinTest
  printf '    private val decoy = """assertTrue("m", view.contains("SelectionRules."))"""\n\n'
  printf '    @Test\n    fun viewStillCalls() {\n        assertTrue("m", cond && view.contains("Missing."))\n    }\n\n'
  printf '    @Test\n    fun viewNoLongerHoldsTheOldBranch() {\n        assertFalse("old", view.contains("%s"))\n    }\n}\n' "$OLDBR"; } > "$TMP/decoy.pin.kt"
cp "$TMP/SelectionView.new.kt" "$VIEWF"; vrf "$TMP/decoy.pin.kt"
[ "$VRC" = 2 ] && ok "an assertion-shaped raw string in the pin is a decoy, not an assertion: the unreadable real one still fails closed (exit 2)" || fail "decoy raw string: rc=$VRC (want 2) $(cat "$TMP/vrf.out")"

# V7. a call named only in a STRING literal (a log message or tag) is not a call either; the price is that a call inside a "${...}" template
#     reads as gone (BROKEN, fail closed)
{ cat <<'KT'
package com.x

import android.content.Context
import android.view.View
import android.util.Log

class SelectionView(context: Context) : View(context) {
    fun pick(startDistance: Int, endDistance: Int): Int {
        Log.d("sel", "SelectionRules.pick was replaced")
        return 0
    }
}
KT
} > "$VIEWF"
vrf "$TMP/wrapped.pin.kt"
[ "$VRC" = 1 ] && grep -q 'SelectionRules\.' "$TMP/vrf.out" && ok "a call named only inside a string literal does not satisfy the call assertion (exit 1)" || fail "string-only call: rc=$VRC (want 1) $(cat "$TMP/vrf.out")"
sed 's/Log.d("sel", "SelectionRules.pick was replaced")/Log.d("sel", "${SelectionRules.pick(1, 2)}")/' "$VIEWF" > "$TMP/tmpl.view" && cp "$TMP/tmpl.view" "$VIEWF"
vrf "$TMP/wrapped.pin.kt"
[ "$VRC" = 1 ] && ok "  … and a call inside a \${...} template reads as gone too (BROKEN: the stated, fail-closed price)" || fail "template call: rc=$VRC (want 1: documented fail-closed)"

# ── review of lane A11: scan must read every file the repo has, never hang, and never turn an error into "pin needed" ─────────────────────────
mkfix() {  # mkfix <root> [old View file] [new View file]: base commit = the View with its old branch; then the refactor, uncommitted: a new internal object, the View calls it
  local r="$1" v="$1/app/src/main/java/com/x"
  mkdir -p "$v" "$r/app/src/test/java/com/x"
  git -C "$r" init -q . && git -C "$r" config user.email t@t && git -C "$r" config user.name t && git -C "$r" config commit.gpgsign false
  printf 'plugins { id("com.android.application") }\n' > "$r/app/build.gradle.kts"
  cp "${2:-$TMP/SelectionView.old.kt}" "$v/SelectionView.kt"
  git -C "$r" add -A && git -C "$r" commit -q -m base
  printf 'package com.x\n\ninternal object SelectionRules {\n    fun pick(startDistance: Int, endDistance: Int): Int = if (startDistance <= endDistance) 0 else 1\n}\n' > "$v/SelectionRules.kt"
  cp "${3:-$TMP/SelectionView.new.kt}" "$v/SelectionView.kt"
}
scanin() {  # scanin <root> [seconds]: scan with a wall-clock cap (no `timeout` on macOS); exit code in $SRC (124 = still running), output in $TMP/scan.o
  python3 -I - "$WP" "$1" "${2:-60}" > "$TMP/scan.o" 2>&1 <<'PY'
import subprocess, sys
wp, root, secs = sys.argv[1], sys.argv[2], float(sys.argv[3])
try:
    r = subprocess.run([sys.executable, "-I", wp, "scan"], cwd=root, capture_output=True, text=True, errors="replace", timeout=secs)
    sys.stdout.write(r.stdout + r.stderr)
    sys.exit(r.returncode)
except subprocess.TimeoutExpired:
    print("TIMEOUT")
    sys.exit(124)
PY
  SRC=$?
}

# S1. a byte that is not UTF-8 in a removed line (a Latin-1 file) made scan raise: a traceback exits 1, which means "pin needed"
LATIN="$TMP/SelectionView.latin.kt"
awk '{print} /fun pick/{print "        val label = \"caf\351 au lait\""}' "$TMP/SelectionView.old.kt" > "$LATIN"
F5="$TMP/f5"; mkfix "$F5" "$LATIN"; scanin "$F5"
[ "$SRC" = 1 ] && ! grep -q 'Traceback' "$TMP/scan.o" && grep -q 'PIN NEEDED' "$TMP/scan.o" && ok "a Latin-1 byte in a removed View line: scan still reports PIN NEEDED, no traceback" || fail "latin-1 byte: rc=$SRC $(head -3 "$TMP/scan.o")"
# any other unexpected error is exit 2 with a message, not a traceback with exit 1
# (the script under test is loaded from $WP, so a mutant handed in through WP_SCRIPT is the one that runs)
python3 -I - "$WP" > "$TMP/boom.out" 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("wiring_pin_under_test", sys.argv[1])
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)
def boom(*a, **k):
    raise RuntimeError("boom")
w.scan = boom
sys.exit(w.main(["scan"]))
PY
rc=$?
[ "$rc" = 2 ] && grep -qi 'internal error' "$TMP/boom.out" && ! grep -q 'Traceback' "$TMP/boom.out" && ok "an unexpected exception is exit 2 with 'internal error', never exit 1 (= pin needed)" || fail "unexpected exception: rc=$rc $(head -3 "$TMP/boom.out")"

# S2. git C-quotes non-ASCII paths ("SelectionRulesV\303\271ng.kt"): the file was silently skipped, scan said exit 0
F6="$TMP/f6"; mkfix "$F6"; mv "$F6/app/src/main/java/com/x/SelectionRules.kt" "$F6/app/src/main/java/com/x/SelectionRulesVùng.kt"; scanin "$F6"
[ "$SRC" = 1 ] && grep -q 'PIN NEEDED' "$TMP/scan.o" && ok "an untracked object file with a non-ASCII name is scanned (exit 1)" || fail "non-ASCII untracked file: rc=$SRC (want 1) $(head -3 "$TMP/scan.o")"
F7="$TMP/f7"; mkdir -p "$F7/app/src/main/java/com/x"
git -C "$F7" init -q . && git -C "$F7" config user.email t@t && git -C "$F7" config user.name t && git -C "$F7" config commit.gpgsign false
printf 'plugins { id("com.android.application") }\n' > "$F7/app/build.gradle.kts"
cp "$TMP/SelectionView.old.kt" "$F7/app/src/main/java/com/x/SelectionView.kt"
printf 'package com.x\n\ninternal object Existing { fun f() = 1 }\n' > "$F7/app/src/main/java/com/x/RulesVùng.kt"
git -C "$F7" add -A && git -C "$F7" commit -q -m base
printf 'package com.x\n\ninternal object Existing { fun f() = 1 }\n\ninternal object SelectionRules {\n    fun pick(a: Int, b: Int): Int = if (a <= b) 0 else 1\n}\n' > "$F7/app/src/main/java/com/x/RulesVùng.kt"
cp "$TMP/SelectionView.new.kt" "$F7/app/src/main/java/com/x/SelectionView.kt"; scanin "$F7"
[ "$SRC" = 1 ] && grep -q 'PIN NEEDED - internal object SelectionRules' "$TMP/scan.o" && ok "a tracked, modified file with a non-ASCII name that gained an internal object is scanned (exit 1)" || fail "non-ASCII tracked file: rc=$SRC (want 1) $(head -3 "$TMP/scan.o")"

# S3. a FIFO named *.kt (nothing of ours: INSTINCT-040) made scan block in open() forever; anything that is not a regular file is skipped
F8="$TMP/f8"; mkfix "$F8"; mkfifo "$F8/app/src/main/java/com/x/Hang.kt" "$F8/app/src/test/java/com/x/HangTest.kt"; scanin "$F8" 20
[ "$SRC" = 1 ] && grep -q 'PIN NEEDED' "$TMP/scan.o" && ok "a FIFO named *.kt next to the object does not hang scan (it still reports PIN NEEDED)" || fail "FIFO: rc=$SRC (124 = hung) $(head -3 "$TMP/scan.o")"

# S4. a file that was only RENAMED (git mv) is not a new object: git shows the new name, base has no such path, so every object in it counted as new
F9="$TMP/f9"; mkfix "$F9"; git -C "$F9" add -A && git -C "$F9" commit -q -m "refactor, wired, no test names the View"
git -C "$F9" mv app/src/main/java/com/x/SelectionRules.kt app/src/main/java/com/x/MovedRules.kt; scanin "$F9"
[ "$SRC" = 0 ] && ok "a committed object whose file was only renamed (git mv) is not reported as new (exit 0)" || fail "renamed file: rc=$SRC (want 0) $(head -3 "$TMP/scan.o")"
# ... but an object ADDED to a renamed file still is
printf '\ninternal object Another { fun g() = 2 }\n' >> "$F9/app/src/main/java/com/x/MovedRules.kt"; scanin "$F9"
grep -q 'UNWIRED - internal object Another' "$TMP/scan.o" && ok "  … while a new object added to the renamed file is (UNWIRED: no View names it)" || fail "object added to a renamed file: rc=$SRC $(head -3 "$TMP/scan.o")"

# ── review of lane A11: what scan decides ────────────────────────────────────────────────────────────────────────────────────────────────────
pin_of() { awk '/^----8<----$/{n++; next} n==1{print}' "$TMP/scan.o"; }   # the first skeleton of the last scanin output
save_of() { sed -n 's/^  save as: //p' "$TMP/scan.o" | head -1; }

# D1. a pin names ONE (View, object) pair. The saved pin of the first object used to silence the View for ever, so a SECOND object extracted into
#     the same View was never flagged; and the pin's file and class were named after the View alone, so a second pin would overwrite the first.
F10="$TMP/f10"; mkfix "$F10"; scanin "$F10"; P1="$(save_of)"; pin_of > "$TMP/pin1.kt"; cp "$TMP/pin1.kt" "$F10/$P1"
[ "$SRC" = 1 ] && printf '%s' "$P1" | grep -q 'SelectionViewSelectionRulesWiringPinTest.kt$' && grep -q '^class SelectionViewSelectionRulesWiringPinTest {$' "$TMP/pin1.kt" \
  && ok "the pin's file and class are named after the View AND the object" || fail "pin naming: rc=$SRC save-as='$P1' $(grep -n '^class' "$TMP/pin1.kt")"
scanin "$F10"; [ "$SRC" = 0 ] && ok "  … and once saved it silences that pair (exit 0)" || fail "after saving pin 1: rc=$SRC $(head -2 "$TMP/scan.o")"
V10="$F10/app/src/main/java/com/x"
printf 'package com.x\n\ninternal object SelectionGeometry {\n    fun area(w: Int, h: Int): Int = w * h\n}\n' > "$V10/SelectionGeometry.kt"
awk '/^        return chosen/{print "        val area = SelectionGeometry.area(startDistance, endDistance)"; print "        return chosen + area"; next} {print}' "$V10/SelectionView.kt" > "$TMP/f10.view" && cp "$TMP/f10.view" "$V10/SelectionView.kt"
scanin "$F10"; P2="$(save_of)"
[ "$SRC" = 1 ] && grep -q 'PIN NEEDED - internal object SelectionGeometry' "$TMP/scan.o" && ok "a SECOND object extracted into the same View is flagged although a pin for the first one exists (exit 1)" || fail "second object: rc=$SRC (want 1) $(head -3 "$TMP/scan.o")"
[ -n "$P2" ] && [ "$P2" != "$P1" ] && printf '%s' "$P2" | grep -q 'SelectionViewSelectionGeometryWiringPinTest.kt$' && ok "  … and its pin goes to a different file than the first pin ($P2)" || fail "second pin path '$P2' vs first '$P1'"
pin_of > "$TMP/pin2.kt"; cp "$TMP/pin2.kt" "$F10/$P2"; scanin "$F10"
[ "$SRC" = 0 ] && ok "  … and saving the second pin silences it (exit 0)" || fail "after saving pin 2: rc=$SRC $(head -2 "$TMP/scan.o")"

# D1b. a COMMENT or KDoc in a test that names the View is no test of the wiring either (the same hole as a comment that "calls" the object)
F15="$TMP/f15"; mkfix "$F15"
printf 'package com.x\n\n// extracted from SelectionView\n/** SelectionView calls this object. */\nclass SelectionRulesTest { fun t() { SelectionRules.pick(1, 2) } }\n' > "$F15/app/src/test/java/com/x/SelectionRulesTest.kt"
scanin "$F15"
[ "$SRC" = 1 ] && grep -q 'PIN NEEDED - internal object SelectionRules' "$TMP/scan.o" && ok "a comment / KDoc naming the View in the object's own test does not count as a test of the pair (exit 1)" || fail "comment-only View mention in a test: rc=$SRC (want 1) $(head -2 "$TMP/scan.o")"
printf 'package com.x\n\nclass SelectionRulesTest { fun t() { SelectionRules.pick(1, 2); println(SelectionView::class) } }\n' > "$F15/app/src/test/java/com/x/SelectionRulesTest.kt"
scanin "$F15"
[ "$SRC" = 0 ] && ok "  … while the same test naming the View in code does (exit 0)" || fail "code mention of the View in the object's test: rc=$SRC (want 0) $(head -2 "$TMP/scan.o")"

# D2. an object declared in the SAME file as its View was never considered (siblings only)
F11="$TMP/f11"; V11="$F11/app/src/main/java/com/x"; mkdir -p "$V11" "$F11/app/src/test/java/com/x"
git -C "$F11" init -q . && git -C "$F11" config user.email t@t && git -C "$F11" config user.name t && git -C "$F11" config commit.gpgsign false
printf 'plugins { id("com.android.application") }\n' > "$F11/app/build.gradle.kts"
cat > "$V11/Combo.kt" <<'KT'
package com.x

import android.content.Context
import android.view.View

class ComboView(context: Context) : View(context) {
    fun pick(startDistance: Int, endDistance: Int): Int {
        val chosen = if (startDistance <= endDistance) 0 else 1
        return chosen
    }
}
KT
git -C "$F11" add -A && git -C "$F11" commit -q -m base
cat > "$V11/Combo.kt" <<'KT'
package com.x

import android.content.Context
import android.view.View

class ComboView(context: Context) : View(context) {
    fun pick(startDistance: Int, endDistance: Int): Int {
        val chosen = ComboRules.pick(startDistance, endDistance)
        return chosen
    }
}

internal object ComboRules {
    fun pick(startDistance: Int, endDistance: Int): Int = if (startDistance <= endDistance) 0 else 1
}
KT
scanin "$F11"
[ "$SRC" = 1 ] && grep -q 'PIN NEEDED - internal object ComboRules' "$TMP/scan.o" && grep -q 'called by View ComboView' "$TMP/scan.o" && ok "an internal object declared in the same file as the View that calls it needs a pin (exit 1)" || fail "same-file object: rc=$SRC (want 1) $(head -3 "$TMP/scan.o")"
pin_of > "$TMP/pin11.kt"; grep -q 'File("src/main/java/com/x/Combo.kt")' "$TMP/pin11.kt" && grep -q 'view.contains("ComboRules.")' "$TMP/pin11.kt" && ok "  … and the pin reads that same file" || fail "same-file pin: $(head -12 "$TMP/pin11.kt")"
sed -i.bak 's/val chosen = ComboRules.pick(startDistance, endDistance)/val chosen = if (startDistance <= endDistance) 0 else 1/' "$V11/Combo.kt"; rm -f "$V11/Combo.kt.bak"
scanin "$F11"
[ "$SRC" = 1 ] && grep -q 'UNWIRED - internal object ComboRules' "$TMP/scan.o" && ok "  … and one the same-file View does not call is UNWIRED (the declaration is not a call)" || fail "same-file unwired: rc=$SRC $(head -3 "$TMP/scan.o")"

# D3. a bodiless `data class` before a View was classified as the View itself: its 600-char head ran on to the real `: View(`
F12="$TMP/f12"; V12="$F12/app/src/main/java/com/x"; mkdir -p "$V12"
git -C "$F12" init -q . && git -C "$F12" config user.email t@t && git -C "$F12" config user.name t && git -C "$F12" config commit.gpgsign false
printf 'plugins { id("com.android.application") }\n' > "$F12/app/build.gradle.kts"
printf 'package com.x\n\nimport android.content.Context\nimport android.view.View\n\ndata class Marker(val a: Int)\n\nclass RealView(context: Context) : View(context) {\n    fun f() = 1\n}\n' > "$V12/Views.kt"
git -C "$F12" add -A && git -C "$F12" commit -q -m base
printf 'package com.x\n\nimport android.content.Context\nimport android.view.View\n\ndata class Marker(val a: Int)\n\nclass RealView(context: Context) : View(context) {\n    fun f() = SelectionRules.pick(1, 2)\n}\n' > "$V12/Views.kt"
printf 'package com.x\n\ninternal object SelectionRules { fun pick(a: Int, b: Int) = if (a < b) a else b }\n' > "$V12/SelectionRules.kt"
scanin "$F12"
[ "$SRC" = 1 ] && grep -q 'called by View RealView' "$TMP/scan.o" && ! grep -q 'View Marker' "$TMP/scan.o" && ok "a bodiless data class before a View is not taken for the View (only RealView is named)" || fail "data class before a View: rc=$SRC $(grep -n 'View' "$TMP/scan.o" | head -4)"
# a real View header that spans lines still is one
printf 'package com.x\n\nimport android.content.Context\nimport android.view.View\n\nclass WrapView(\n    context: Context,\n)\n    : View(context) {\n    fun f() = SelectionRules.pick(1, 2)\n}\n' > "$V12/Wrap.kt"
scanin "$F12"
grep -q 'called by View WrapView' "$TMP/scan.o" && ok "  … while a View whose header spans several lines (constructor on its own lines, supertype on the next) is still found" || fail "multi-line View header: $(grep -n 'View' "$TMP/scan.o" | head -4)"

# D4. an object named only in a comment or KDoc of the View is not wired (UNWIRED, not PIN NEEDED)
F13="$TMP/f13"; mkfix "$F13"
printf 'package com.x\n\nimport android.content.Context\nimport android.view.View\n\n/** Delegates to SelectionRules.pick, see the rules file. */\nclass SelectionView(context: Context) : View(context) {\n    // val chosen = SelectionRules.pick(startDistance, endDistance)\n    fun pick(startDistance: Int, endDistance: Int): Int = 0\n}\n' > "$F13/app/src/main/java/com/x/SelectionView.kt"
scanin "$F13"
[ "$SRC" = 1 ] && grep -q 'UNWIRED - internal object SelectionRules' "$TMP/scan.o" && ! grep -q 'PIN NEEDED' "$TMP/scan.o" && ok "an object a View names only in a KDoc / line comment is UNWIRED, not 'PIN NEEDED'" || fail "comment-only mention: rc=$SRC $(head -3 "$TMP/scan.o")"
# ... and the same for a name that only a string literal (a log message) carries
printf 'package com.x\n\nimport android.content.Context\nimport android.view.View\nimport android.util.Log\n\nclass SelectionView(context: Context) : View(context) {\n    fun pick(startDistance: Int, endDistance: Int): Int {\n        Log.d("sel", "SelectionRules.pick was replaced")\n        return 0\n    }\n}\n' > "$F13/app/src/main/java/com/x/SelectionView.kt"
scanin "$F13"
[ "$SRC" = 1 ] && grep -q 'UNWIRED - internal object SelectionRules' "$TMP/scan.o" && ! grep -q 'PIN NEEDED' "$TMP/scan.o" && ok "an object a View names only inside a string literal is UNWIRED too" || fail "string-only mention: rc=$SRC $(head -3 "$TMP/scan.o")"

# D5. when no removed line qualifies as a marker the skeleton used to carry an EMPTY old-branch test (verify said holds): now UNPINNABLE, no skeleton
OLDSHORT="$TMP/SelectionView.short.kt"; NEWSHORT="$TMP/SelectionView.shortnew.kt"
printf 'package com.x\n\nimport android.content.Context\nimport android.view.View\n\nclass SelectionView(context: Context) : View(context) {\n    fun pick(a: Int, b: Int): Int {\n        val x = a\n        val y = b\n        return x\n    }\n}\n' > "$OLDSHORT"
printf 'package com.x\n\nimport android.content.Context\nimport android.view.View\n\nclass SelectionView(context: Context) : View(context) {\n    fun pick(a: Int, b: Int): Int {\n        return SelectionRules.pick(a, b)\n    }\n}\n' > "$NEWSHORT"
F14="$TMP/f14"; mkfix "$F14" "$OLDSHORT" "$NEWSHORT"; scanin "$F14"
[ "$SRC" = 1 ] && grep -q 'UNPINNABLE' "$TMP/scan.o" && ! grep -q -- '----8<----' "$TMP/scan.o" && grep -q 'PIN NEEDED' "$TMP/scan.o" \
  && ok "no removed line qualifies as a marker: UNPINNABLE (add the assertion by hand), no empty-bodied skeleton, still exit 1" || fail "unpinnable: rc=$SRC $(head -5 "$TMP/scan.o")"

[ "$FAILS" -eq 0 ] && echo "✅ test_wiring_pin: all passed" || { echo "❌ test_wiring_pin: $FAILS failed"; exit 1; }
