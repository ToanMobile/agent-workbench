#!/usr/bin/env bash
# bin/post-fix-gate.py, the redefinition check for JS/TS tests (2026-10-09 follow-up, plan
# docs/plans/audit-2026-10-09-followup.md step 3 item 3). An appended `it('title', …)` / `test('title', …)` that repeats a title the
# base file already has counts as an edit (it can shadow the real test). Titles were counted for the WHOLE file, so a title that
# sits in two different `describe` blocks — the normal way to test two things the same way — flagged a pure append as an edited
# test. Titles are now counted per enclosing describe path; the same title in the SAME describe is still a redefinition, and a file
# the scanner cannot read (unbalanced braces) keeps the whole-file count.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# mk <name> <base content of tests/a.test.js>
mk() {
  local d="$TMP/$1"
  mkdir -p "$d/src" "$d/tests" && cd "$d" || exit 1
  git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf 'export const f = () => 1;\n' > src/core.js
  printf '%s' "$2" > tests/a.test.js
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"true"}]}]}
JSON
  git add -A && git commit -qm init
}
gate() {
  OUT="$(CLAUDE_PROJECT_DIR="$PWD" POSTFIX_GATE_FORCE_FULL=1 FLAKY_RETRY_MAX_S=60 python3 "$GATE" --matrix "$PWD/matrix.json" \
         --lang en --json "$@" 2>&1)"; RC=$?
  JSON="$(printf '%s\n' "$OUT" | grep '^{' | tail -1)"
}
j() { printf '%s' "$JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1" 2>/dev/null; }
touched() { [ "$(j '"tests/a.test.js" in d["tests_touched"]')" = "True" ]; }
# case_ <label> <flagged|free> <base> <appended text>
case_() {
  mk "c$((++N))" "$3"
  printf '%s' "$4" >> tests/a.test.js
  gate --dry-run
  if [ "$2" = flagged ]; then touched && ok "$1" || bad "$1: not reported as an edited test (tests_touched: $(j 'd["tests_touched"]'))"
  else touched && bad "$1: reported as an edited test" || ok "$1"; fi
}
N=0
BASE="describe('alpha', () => {
  it('works', () => { expect(1).toBe(1); });
});
"

case_ "the same title in ANOTHER describe is a new test, not a redefinition"   free    "$BASE" "describe('beta', () => {
  it('works', () => { expect(2).toBe(2); });
});
"
case_ "the same title at the top level does not shadow the one in a describe"   free    "$BASE" "it('works', () => { expect(3).toBe(3); });
"
case_ "a new title in the same describe path is a new test"                     free    "$BASE" "describe('alpha', () => {
  it('also works', () => { expect(4).toBe(4); });
});
"
case_ "the same title in the SAME describe still shadows the real test"         flagged "$BASE" "describe('alpha', () => {
  it('works', () => { expect(true).toBe(true); });
});
"
case_ "nested: the same title under the same outer + inner describe"            flagged "describe('alpha', () => {
  describe('inner', () => {
    it('works', () => { expect(1).toBe(1); });
  });
});
" "describe('alpha', () => {
  describe('inner', () => {
    it('works', () => { expect(2).toBe(2); });
  });
});
"
case_ "nested: the same title under a different inner describe"                 free    "describe('alpha', () => {
  describe('inner', () => {
    it('works', () => { expect(1).toBe(1); });
  });
});
" "describe('alpha', () => {
  describe('other', () => {
    it('works', () => { expect(2).toBe(2); });
  });
});
"
case_ "two top-level tests with one title are still a redefinition"             flagged "it('works', () => { expect(1).toBe(1); });
" "it('works', () => { expect(2).toBe(2); });
"
# a braces-in-strings file is read right; an unbalanced one falls back to the whole-file count (flagged: the safe side)
case_ "braces inside strings and comments do not break the scan"                free    "describe('alpha {', () => {
  it('works', () => { expect('}').toBe('}'); }); // }
});
" "describe('beta }', () => {
  it('works', () => { expect(2).toBe(2); });
});
"
case_ "an unbalanced file falls back to the whole-file count"                   flagged "describe('alpha', () => {
  it('works', () => { expect(1).toBe(1); });
" "describe('beta', () => {
  it('works', () => { expect(2).toBe(2); });
});
"

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_js_describe_scope: all passed" || { echo "❌ test_gate_js_describe_scope: $FAILS failed"; exit 1; }
