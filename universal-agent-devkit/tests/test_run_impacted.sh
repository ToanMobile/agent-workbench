#!/usr/bin/env bash
# Regression test: tests/run_impacted.sh picks the tests that name a changed file — from the
# working tree, new files, AND commits not pushed yet (a commit made inside the turn must not
# leave the gate testing nothing), plus helpers under tests/ through the tests that source them.
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

K="$TMP/kit"; mkdir -p "$K/tests" "$K/scripts"
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$K/tests/"
echo 'echo ok' > "$K/tests/test_repo_consistency.sh"
echo 'x = 1' > "$K/scripts/foo.py"
echo 'y = 1' > "$K/scripts/bar.py"
printf '. tests/lib_helper.sh\npython3 scripts/foo.py\n' > "$K/tests/test_foo.sh"
echo 'python3 scripts/bar.py' > "$K/tests/test_bar.sh"
echo 'helper() { :; }' > "$K/tests/lib_helper.sh"
( cd "$K" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -qm init
  git clone -q --bare . "$TMP/origin.git" && git remote add origin "$TMP/origin.git" && git fetch -q origin && git branch -q -u origin/main 2>/dev/null || git branch -q -u origin/master )
list() { (cd "$K" && bash tests/run_impacted.sh --list); }

[ "$(list)" = "tests/test_repo_consistency.sh" ] && ok "nothing changed: repo consistency only" || fail "clean: $(list | tr '\n' ' ')"

echo 'x = 2' > "$K/scripts/foo.py"
list | grep -qx "tests/test_foo.sh" && ! list | grep -qx "tests/test_bar.sh" && ok "working-tree change selects the test that names it" || fail "worktree: $(list | tr '\n' ' ')"

(cd "$K" && git commit -qam "fix inside the turn")
list | grep -qx "tests/test_foo.sh" && ok "committed but not pushed: still selected" || fail "unpushed commit lost: $(list | tr '\n' ' ')"

(cd "$K" && git push -q origin HEAD 2>/dev/null)
[ "$(list)" = "tests/test_repo_consistency.sh" ] && ok "pushed: no longer selected" || fail "pushed still selected: $(list | tr '\n' ' ')"

mkdir -p "$K/templates"; echo 'block' > "$K/templates/block.md"; echo 'cat templates/block.md' > "$K/tests/test_block.sh"
(cd "$K" && git add -A && git commit -qm tpl && git push -q origin HEAD 2>/dev/null)
echo 'block v2' > "$K/templates/block.md"
list | grep -qx "tests/test_block.sh" && ok "a changed template (not code) selects the test that reads it" || fail "template: $(list | tr '\n' ' ')"
echo 'block' > "$K/templates/block.md"

echo 'helper() { true; }' > "$K/tests/lib_helper.sh"
list | grep -qx "tests/test_foo.sh" && ok "changed helper under tests/ selects the tests that source it" || fail "helper: $(list | tr '\n' ' ')"

if [ "$FAILS" -ne 0 ]; then echo "run_impacted: $FAILS FAILED"; exit 1; fi
echo "run_impacted: all checks passed"
