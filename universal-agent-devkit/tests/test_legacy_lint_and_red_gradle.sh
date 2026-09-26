#!/usr/bin/env bash
# Regression test (GeelyEx2 report 2026-09-26):
#  1. test_evidence_gate RED_GRADLE missed a real red run when the Gradle test name is long
#     ("QuickInstallCapNhatQuaAliasTest > goi alias … khong so duoc FAILED", > 80 chars
#     between the class and FAILED) → the hook said "never red" after a real red.
#  2. post-fix-gate's Compose / Unity AST linters blocked findings that were already in the
#     base version of a touched file, unlike every regex layer (split_new: legacy lines
#     must not block). A NEW finding must still block.
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
HOOK="$DEVKIT_DIR/hooks/test_evidence_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# ── 1. RED_GRADLE, read from the hook itself ────────────────────────────────────
HOOK="$HOOK" python3 - <<'PY' || FAILS=$((FAILS + 1))
import os, re, sys
src = open(os.environ["HOOK"], encoding="utf-8").read()
line = next(l for l in src.splitlines() if l.startswith("RED_GRADLE = "))
RED_GRADLE = eval(line.split("=", 1)[1].strip(), {"re": re})
cases = [
    ("QuickInstallCapNhatQuaAliasTest > goi alias da cai thi khong bao can cap nhat - versionCode hai app khong so duoc FAILED",
     "QuickInstallCapNhatQuaAliasTest"),
    ("com.example.FooTest > `tên hàm rất dài có dấu cách và backtick để vượt quá tám mươi ký tự trong một dòng Gradle` FAILED",
     "com.example.FooTest"),
    ("OtherFeatureTest FAILED", "OtherFeatureTest"),
    ("FooTest > bar() FAILED", "FooTest"),
]
bad = 0
for text, want in cases:
    got = [m.group(1) for m in RED_GRADLE.finditer(text)]
    ok_ = want in got
    print(("✔ " if ok_ else "✖ ") + f"RED_GRADLE finds {want} in a {len(text)}-char line" + ("" if ok_ else f" (got {got})"))
    bad += not ok_
# Never across lines: the class on one line, FAILED on the next is not a red run of it.
got = [m.group(1) for m in RED_GRADLE.finditer("BarTest > x PASSED\nsomething else FAILED")]
print(("✔ " if "BarTest" not in got else "✖ ") + "RED_GRADLE does not cross a newline")
bad += "BarTest" in got
sys.exit(1 if bad else 0)
PY

# ── 2. AST linters: legacy findings in a touched file do not block ──────────────
mkdir -p "$TMP/repo/src" && cd "$TMP/repo" || exit 1
git init -q . && git config user.email t@t && git config user.name t
cat > src/Screen.kt <<'KT'
@Composable
fun OldList(items: List<String>) {
    Text("old")
}
KT
printf '{"project":"t","rules":[{"component":"C","watch_files":["src/Screen.kt"],"mandatory_regression_tests":[{"id":"REG-1","name":"c","command":"true"}]}]}\n' > matrix.json
git add -A && git commit -qm init
gate() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --run-tests > "$TMP/out" 2>&1; }

printf '\n// touched: unrelated comment\n' >> src/Screen.kt
gate; rc=$?
[ "$rc" = 0 ] && ok "legacy unstable-List composable in a touched file does not block (exit 0)" \
  || fail "legacy finding blocked (exit $rc): $(grep -m2 'Compose' "$TMP/out")"

cat >> src/Screen.kt <<'KT'
@Composable
fun NewList(rows: List<Int>) {
    Text("new")
}
KT
gate; rc=$?
[ "$rc" = 1 ] && grep -q 'NewList' "$TMP/out" && ok "a NEW unstable-List composable still blocks, named" \
  || fail "new finding not blocked (exit $rc)"
grep -q 'OldList' "$TMP/out" && grep 'OldList' "$TMP/out" | grep -qv '⚠\|có sẵn\|already' \
  && fail "legacy OldList reported as a blocking finding" || ok "legacy OldList is not a blocking finding"

[ "$FAILS" -eq 0 ] && echo "✅ test_legacy_lint_and_red_gradle: all passed" \
  || { echo "❌ test_legacy_lint_and_red_gradle: $FAILS failed"; exit 1; }
