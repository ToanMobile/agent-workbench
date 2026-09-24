#!/usr/bin/env bash
# Regression test: `agent-kit bugs import` puts past bugs into the regression checklist
# and never reports one as PASS on import: no test → NEEDS_TEST, a test the gate never
# runs → NOT_IN_MATRIX, a matrix test → NOT_RUN until a real gate run after the import,
# not fixed → OPEN. The view counts the bugs no regression test guards.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"; GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P/src" "$P/.agents"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
cat > .agents/regression_matrix.active.json <<'JSON'
{"rules":[{"component":"Core","watch_files":["src/*.kt"],
 "mandatory_regression_tests":[{"id":"REG-CORE","name":"core","command":"true"}]}]}
JSON
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$P"
st() { python3 -c "import json,sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r; d=r.load(__import__('pathlib').Path('$P')); print(r.effective_status(d, d['items']['$1']))"; }

printf 'bug_id\ttitle\tseverity\tfixed?\tmodule\ttest_id_or_NONE\tevidence\n' > "$TMP/bugs.tsv"
printf 'B1\tCrash on resume\tP0\tyes\tapp\tREG-CORE\tcommit abc\n' >> "$TMP/bugs.tsv"
printf 'B2\tLost setting\tP1\tyes\tsettings\tNONE\tissue 12\n' >> "$TMP/bugs.tsv"
printf 'B3\tSlow list\tP2\tyes\tui\tListPerfTest#scroll\t-\n' >> "$TMP/bugs.tsv"
printf '| B4 | Wrong total | P1 | no | cart | NONE | report |\n' > "$TMP/bugs.md"

out="$(bash "$KIT" bugs import "$TMP/bugs.tsv" --dry-run 2>&1)"
[ ! -f .agents/regression_status.json ] && printf '%s' "$out" | grep -q "dry-run" && ok "--dry-run reports, writes nothing" || fail "dry-run wrote: $out"
bash "$KIT" bugs import "$TMP/bugs.tsv" >/dev/null 2>&1 || fail "import failed"
bash "$KIT" bugs import "$TMP/bugs.md" >/dev/null 2>&1 || fail "|-table import failed"
[ "$(st BUG-B1)" = NOT_RUN ] && ok "bug linked to a matrix test: NOT_RUN (not re-run), never PASS on import" || fail "B1: $(st BUG-B1)"
[ "$(st BUG-B2)" = NEEDS_TEST ] && ok "bug without a test: NEEDS_TEST" || fail "B2: $(st BUG-B2)"
[ "$(st BUG-B3)" = NOT_IN_MATRIX ] && ok "bug with a test the gate never runs: NOT_IN_MATRIX" || fail "B3: $(st BUG-B3)"
[ "$(st BUG-B4)" = OPEN ] && ok "|-separated table read; unfixed bug: OPEN" || fail "B4: $(st BUG-B4)"
grep -q "Bug không có test hồi quy nào chặn tái phát: 2" .agents/regression_checklist.md \
  && ok "view counts the bugs no regression test guards (2)" || fail "gap count: $(grep 'Bug không' .agents/regression_checklist.md)"

echo "fun ok() = 2" > src/Core.kt
python3 "$GATE" --run-tests >/dev/null 2>&1
[ "$(st BUG-B1)" = PASS ] && ok "after a real gate run of its test: PASS" || fail "B1 after run: $(st BUG-B1)"
bash "$KIT" bugs import "$TMP/bugs.tsv" >/dev/null 2>&1
[ "$(st BUG-B1)" = PASS ] && [ "$(python3 -c "import json;print(len([k for k in json.load(open('.agents/regression_status.json'))['items'] if k.startswith('BUG-')]))")" = 4 ] \
  && ok "re-import: no duplicate rows, the real result is kept" || fail "re-import changed B1 or duplicated"
bash "$KIT" bugs bogus >/dev/null 2>&1; [ $? = 2 ] && ok "unknown bugs action → exit 2" || fail "bad action accepted"

# Test names that are classes or files resolve to the matrix suite that runs them.
Q="$TMP/q"; mkdir -p "$Q/core/src/test/java/a" "$Q/core/src/androidTest/java/a" "$Q/Assets/Tests/EditMode" "$Q/Assets/Tests/PlayMode" "$Q/.agents"
( cd "$Q" && git init -q . && git config user.email t@t && git config user.name t
  echo "class BookmarkDaoTest" > core/src/test/java/a/BookmarkDaoTest.kt
  echo "class DbMigrationTest" > core/src/androidTest/java/a/DbMigrationTest.kt
  echo "class ShelfScreenshotTest" > core/src/test/java/a/ShelfScreenshotTest.kt
  echo "class WalletMergeTests {}" > Assets/Tests/EditMode/WalletMergeTests.cs
  echo "class BotRunTests {}" > Assets/Tests/PlayMode/BotRunTests.cs
  touch core/build.gradle.kts && mkdir -p app && touch app/build.gradle.kts
  cat > .agents/regression_matrix.active.json <<'JSON'
{"rules":[{"component":"App","watch_files":["app/*.kt","core/*.kt"],"mandatory_regression_tests":[{"id":"REG-APP","name":"app unit","command":"./gradlew :app:testReleaseUnitTest"}]},
 {"component":"Core","watch_files":["core/*.kt"],"mandatory_regression_tests":[{"id":"REG-CORE","name":"core unit","command":"./gradlew :core:testDebugUnitTest -PexcludeScreenshotTests"}]},
 {"component":"Game","watch_files":["Assets/*.cs"],"mandatory_regression_tests":[{"id":"REG-EDIT","name":"editmode","command":"bash unity-batch.sh editmode"}]}]}
JSON
  git add -A && git commit -qm init )
qst() { python3 -c "import json,sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r; d=r.load(__import__('pathlib').Path('$Q')); print(r.effective_status(d, d['items']['$1']), ','.join(d['items']['$1'].get('tests',[])))"; }
{ printf 'C1\tpath\tP1\tyes\tcore\tcore/src/test/java/a/BookmarkDaoTest.kt\t-\n'
  printf 'C2\tfqn\tP1\tyes\tcore\tcom.a.BookmarkDaoTest#insert\t-\n'
  printf 'C3\tinstrumented\tP1\tyes\tcore\tDbMigrationTest\t-\n'
  printf 'C4\tunity edit\tP1\tyes\tgame\tCozyGoods.Tests.EditMode.WalletMergeTests\t-\n'
  printf 'C5\tunity play\tP1\tyes\tgame\tBotRunTests\t-\n'
  printf 'C6\tscreenshot\tP1\tyes\tcore\tShelfScreenshotTest\t-\n'; } > "$TMP/refs.tsv"
CLAUDE_PROJECT_DIR="$Q" bash "$KIT" bugs import "$TMP/refs.tsv" >/dev/null 2>&1
[ "$(qst BUG-C1)" = "NOT_RUN REG-CORE" ] && ok "unit test file path → the module suite that runs it (REG-CORE)" || fail "C1: $(qst BUG-C1)"
[ "$(qst BUG-C2)" = "NOT_RUN REG-CORE" ] && ok "class name (FQN#method) found with git ls-files → REG-CORE" || fail "C2: $(qst BUG-C2)"
[ "$(qst BUG-C3)" = "NOT_IN_MATRIX " ] && ok "androidTest under a unit-test suite → NOT_IN_MATRIX (the gate never runs it)" || fail "C3: $(qst BUG-C3)"
[ "$(qst BUG-C4)" = "NOT_RUN REG-EDIT" ] && ok "Unity EditMode test → the editmode suite" || fail "C4: $(qst BUG-C4)"
[ "$(qst BUG-C5)" = "NOT_IN_MATRIX " ] && ok "Unity PlayMode test with only an editmode suite → NOT_IN_MATRIX" || fail "C5: $(qst BUG-C5)"
[ "$(qst BUG-C6)" = "NOT_IN_MATRIX " ] && ok "screenshot test excluded by the suite → NOT_IN_MATRIX" || fail "C6: $(qst BUG-C6)"
[ "$(qst BUG-C1)" = "NOT_RUN REG-CORE" ] && ok "a suite that watches core/ but runs only :app: tasks is not linked (C1 → REG-CORE only)" \
  || fail "C1 linked to :app suite: $(qst BUG-C1)"
grep -q "BookmarkDaoTest.kt (trong suite)" "$Q/.agents/regression_checklist.md" && ok "view shows the class/file next to the suite it runs in" || fail "test ref not shown"

if [ "$FAILS" -ne 0 ]; then echo "bug import: $FAILS FAILED"; exit 1; fi
echo "bug import: all checks passed"
