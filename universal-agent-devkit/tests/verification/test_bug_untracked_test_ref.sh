#!/usr/bin/env bash
# bin/regression_checklist.py, a bug linked to a test file git does not track yet (2026-10-12 audit of OfficeReader: all 11 rows the
# checklist counted as "no regression test guards it" had a real test that a matrix suite runs, and the JUnit XML of 11 of them was
# green). `bugs add --test FooTest` resolves the class with `git ls-files`, which lists TRACKED files only: a test written in the
# same turn and not yet `git add`-ed fell into test_refs (NOT_IN_MATRIX), and nothing resolved it again once it was committed.
# Fix: ref_paths also lists untracked, not ignored files; sync_project (every gate run and every `bugs` command) moves a fixed bug's
# test_refs that resolve now into tests / runs_in_suite, the way link_bug does. A ref that still resolves to nothing stays outside.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="$DEVKIT_DIR/bin/agent-kit"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
P="$TMP/p"; mkdir -p "$P/src" "$P/tests" "$P/.agents"
cd "$P" && git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
echo "def ok(): return 1" > src/core.py
printf 'build/\n' > .gitignore
cat > .agents/regression_matrix.active.json <<'JSON'
{"rules":[{"component":"Core","watch_files":["src/*.py","tests/*.py","build/*.py"],
 "mandatory_regression_tests":[{"id":"REG-PY","name":"py","command":"python3 -m pytest tests"}]}]}
JSON
git add -A && git commit -qm init
export CLAUDE_PROJECT_DIR="$P"
st() { python3 -c "import sys; sys.path.insert(0,'$DEVKIT_DIR/bin'); import regression_checklist as r; d=r.load(__import__('pathlib').Path('$P')); print(r.effective_status(d, d['items']['$1']))"; }
field() { python3 -c "import json; print(json.load(open('.agents/regression_status.json'))['items']['$1'].get('$2'))"; }
add() { bash "$KIT" bugs add "$1" --fixed --module core --severity low --test "$2" 2>/dev/null | grep -o 'BUG-[A-Za-z0-9-]*' | head -1; }

# 1. the test file exists but is not tracked yet when the bug is linked
echo "def test_a(): pass" > tests/FooTest.py
B1="$(add "first bug" FooTest)"
[ -n "$B1" ] || { fail "bugs add printed no id"; exit 1; }
s="$(st "$B1")"
[ "$s" != NOT_IN_MATRIX ] && [ "$s" != NEEDS_TEST ] && ok "untracked test file at link time: linked to the suite ($s)" || fail "untracked test file: $s (tests=$(field "$B1" tests) refs=$(field "$B1" test_refs))"

# 2. linked while the file did not exist at all, then written and committed: the next sync resolves it
B2="$(add "second bug" BarTest)"
[ "$(st "$B2")" = NOT_IN_MATRIX ] && ok "no such test yet: NOT_IN_MATRIX" || fail "B2 before: $(st "$B2")"
echo "def test_b(): pass" > tests/BarTest.py && git add tests/BarTest.py && git commit -qm bar
add "unrelated bug" REG-PY >/dev/null     # any bugs command syncs the checklist, as every gate run does
s="$(st "$B2")"
[ "$s" != NOT_IN_MATRIX ] && [ "$(field "$B2" tests)" = "['REG-PY']" ] && ok "committed later: the next sync links it to REG-PY ($s)" || fail "B2 after sync: $s (tests=$(field "$B2" tests) refs=$(field "$B2" test_refs))"
[ "$(field "$B2" test_refs)" = "[]" ] && ok "the resolved ref left test_refs" || fail "test_refs still: $(field "$B2" test_refs)"
[ "$(field "$B2" runs_in_suite)" = "['BarTest']" ] && ok "the ref is kept in runs_in_suite, as link_bug keeps it" || fail "runs_in_suite: $(field "$B2" runs_in_suite)"

# 3. guards: a ref to nothing, and a test in a git-ignored folder, stay outside the matrix
B3="$(add "third bug" NoSuchTest)"
mkdir -p build && echo "def test_c(): pass" > build/BazTest.py
B4="$(add "fourth bug" BazTest)"
add "another unrelated bug" REG-PY >/dev/null
[ "$(st "$B3")" = NOT_IN_MATRIX ] && ok "ref to no file: still NOT_IN_MATRIX after a sync" || fail "B3: $(st "$B3")"
[ "$(st "$B4")" = NOT_IN_MATRIX ] && ok "test in a git-ignored folder: not linked" || fail "B4: $(st "$B4")"

[ "$FAILS" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS=$FAILS"; exit 1; }
