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

# A test that reaches a script through a command names only its stem ("agent-kit githooks
# install" for scripts/githooks.sh): 2026-09-26 test_githooks went red on a githooks.sh change
# and the gate did not run it.
echo 'echo tool' > "$K/scripts/tool.sh"; echo 'bash bin/kit tool install' > "$K/tests/test_tool_cmd.sh"
echo 'echo toolbox' > "$K/tests/test_toolbox.sh"
(cd "$K" && git add -A && git commit -qm "tool" && git push -q origin HEAD 2>/dev/null)
echo 'echo tool v2' > "$K/scripts/tool.sh"
list | grep -qx "tests/test_tool_cmd.sh" && ok "a test naming only the script's stem (kit tool install) is selected" \
  || fail "stem: $(list | tr '\n' ' ')"
! list | grep -qx "tests/test_toolbox.sh" && ok "  … as a whole word only (toolbox is not tool)" || fail "stem matched inside a word"
(cd "$K" && git checkout -q -- scripts/tool.sh)

# The run is parallel (DEVKIT_TEST_JOBS, default 4): the DevKit suite took 740 s of the 900 s
# gate limit on 2026-09-26. Output stays in list order; one failing test still fails the run;
# test_budgets (timings) runs alone after the others.
R="$TMP/par"; mkdir -p "$R/tests"; cp "$DEVKIT_DIR/tests/run_impacted.sh" "$R/tests/"
echo 'echo ok' > "$R/tests/test_repo_consistency.sh"
for n in a b c; do printf 'sleep 2; echo %s-done\n' "$n" > "$R/tests/test_slow_$n.sh"; done
printf 'echo broken; exit 3\n' > "$R/tests/test_broken.sh"
printf 'for f in tests/test_slow_*.sh; do [ -e "$f" ]; done; [ -z "$(pgrep -f "tests/test_slow_" | head -1)" ] && echo alone || { echo "not alone"; exit 1; }\n' > "$R/tests/test_budgets.sh"
( cd "$R" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -qm init )
( cd "$R" && echo "# x" >> tests/test_slow_a.sh && echo "# x" >> tests/test_slow_b.sh && echo "# x" >> tests/test_slow_c.sh \
  && echo "# x" >> tests/test_broken.sh && echo "# x" >> tests/test_budgets.sh )
t0=$(date +%s); out="$(cd "$R" && DEVKIT_TEST_JOBS=4 bash tests/run_impacted.sh 2>&1)"; rc=$?; t1=$(date +%s)
[ $((t1 - t0)) -lt 5 ] && ok "3 × 2 s tests run in parallel ($((t1 - t0)) s < 5 s)" || fail "not parallel: $((t1 - t0)) s"
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q "✖ tests/test_broken.sh" && ok "a failing test still fails the run, named" || fail "rc=$rc: $out"
printf '%s' "$out" | grep -q "✔ tests/test_budgets.sh" && ok "test_budgets runs alone, after the others" || fail "budgets not alone: $out"
[ "$(printf '%s\n' "$out" | grep -E '^[✔✖] ' | sed 's/^. //' | tr '\n' ' ')" = "$(printf '%s\n' "$out" | grep -E '^[✔✖] ' | sed 's/^. //' | sort | tr '\n' ' ')" ] \
  && ok "results are printed in list order" || fail "order: $out"

if [ "$FAILS" -ne 0 ]; then echo "run_impacted: $FAILS FAILED"; exit 1; fi
echo "run_impacted: all checks passed"
