#!/usr/bin/env bash
# Regression (DevKit speed, GeelyEx2): REG-CAR-VOICE runs 9 voice test classes with `--tests ...` AFTER REG-CAR-01 has
# run the whole CarConnect unit-test task, which already contains them: 30 of 30 runs where both executed, median 90 s,
# 44 min in 2.2 days. A matrix suite may now say "covered_by": "<id of another suite>". The gate then does not run it
# when that suite ran its FULL command earlier in the same run and passed; the covered suite shows PASS with the label
# COVERED. In every other case it runs as before.
#   1. covering suite passes: the covered one does not run, shows PASS (COVERED), exit 0
#   2. covering suite fails: the covered one runs (its own result is reported), exit 1
#   3. the covered suite listed BEFORE its cover runs (order matters: nothing has run yet)
#   4. an unknown id covers nothing
#   5. a cover that is UNTESTED (cannot run here) covers nothing
#   6. both flagged parallel_safe: the covered one is not started next to its cover, it waits and is covered
#   7. a suite never covers itself
#   8. covering is not transitive: C covered_by B, B covered_by A: C still runs (B did not run its own command)
#   9. the field counts only from the base-ref matrix: adding it in the working copy changes nothing
#  10. without the field nothing changes (two suites, both run)
#  11. a covered PASS is part of the full-PASS receipt: the next run on the same content is REUSED with no suite run
#  12. a cover that only "passed" without running its tests (SKIP compile, because a Unity test suite runs) covers nothing:
#      the covered suite still runs and its failure fails the gate
#  14. the checklist row of a covered suite carries the exit code of its cover (never "exit None") and the cover's log
#  13. a covered suite that would run IMPACTED (it has an impacted_command and this is not --full) is not covered: its impacted
#      run is also where the vacuity revert checks its tests; under --full it is covered
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export VACUITY_REVERT=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"
export MARK="$TMP/mark"
OUT=""; RC=0

make_repo() { # $1 = JSON list of suites
  rm -rf "$R" "$MARK" && mkdir -p "$R/src" "$R/tests" "$MARK" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  printf 'touch "$MARK/ran_a"\nsleep 1\n' > tests/a.sh                 # the cover: passes after 1 s
  printf 'touch "$MARK/ran_a"\nexit 1\n' > tests/a_fail.sh             # the cover: fails
  printf 'touch "$MARK/ran_a"\nexit 77\n' > tests/a_untested.sh        # the cover: cannot run here
  printf 'touch "$MARK/ran_b"\n' > tests/b.sh                          # the covered suite
  printf 'touch "$MARK/ran_c"\n' > tests/c.sh
  printf 'touch "$MARK/ran_b"\nexit 1\n' > tests/b_fail.sh                 # the covered suite, failing
  printf 'exit 0\n' > tests/u.sh
  printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[%s]}]}\n' "$1" > matrix.json
  git add -A && git commit -qm init
  echo "fun ok() = 2" > src/Core.kt
}
suite() { # id command [extra json fields]
  printf '{"id":"%s","name":"%s","command":"%s"%s}' "$1" "$1" "$2" "${3:-}"
}
run_gate() { OUT="$(CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests 2>&1)"; RC=$?; }
ran() { [ -f "$MARK/ran_$1" ]; }
covered_line() { printf '%s\n' "$OUT" | grep -E "\[x\] COVERED.*$1" >/dev/null; }

# 1. cover passes -> covered suite does not run
make_repo "$(suite REG-A 'sh tests/a.sh'),$(suite REG-B 'sh tests/b.sh' ',"covered_by":"REG-A"')"
run_gate
if [ "$RC" = 0 ] && ran a && ! ran b && covered_line REG-B; then ok "1: the cover passed, the covered suite did not run and shows PASS (COVERED), exit 0"
else bad "1: covered suite ran or was not marked (exit $RC, ran_b=$(ran b && echo yes || echo no))"; printf '%s\n' "$OUT" | tail -12; fi

# 2. cover fails -> covered suite runs
make_repo "$(suite REG-A 'sh tests/a_fail.sh'),$(suite REG-B 'sh tests/b.sh' ',"covered_by":"REG-A"')"
run_gate
if [ "$RC" = 1 ] && ran a && ran b && ! covered_line REG-B; then ok "2: the cover failed, the covered suite ran on its own, exit 1"
else bad "2: failing cover (exit $RC, ran_b=$(ran b && echo yes || echo no))"; printf '%s\n' "$OUT" | tail -12; fi

# 3. covered suite before its cover
make_repo "$(suite REG-B 'sh tests/b.sh' ',"covered_by":"REG-A"'),$(suite REG-A 'sh tests/a.sh')"
run_gate
if [ "$RC" = 0 ] && ran a && ran b && ! covered_line REG-B; then ok "3: the covered suite listed before its cover ran normally"
else bad "3: order ignored (exit $RC, ran_b=$(ran b && echo yes || echo no))"; printf '%s\n' "$OUT" | tail -12; fi

# 4. unknown id
make_repo "$(suite REG-A 'sh tests/a.sh'),$(suite REG-B 'sh tests/b.sh' ',"covered_by":"REG-NOPE"')"
run_gate
if [ "$RC" = 0 ] && ran b && ! covered_line REG-B; then ok "4: an unknown covered_by id covers nothing"
else bad "4: unknown id covered the suite (exit $RC)"; printf '%s\n' "$OUT" | tail -12; fi

# 5. cover UNTESTED
make_repo "$(suite REG-A 'sh tests/a_untested.sh' ',"untested_exit":77'),$(suite REG-B 'sh tests/b.sh' ',"covered_by":"REG-A"')"
run_gate
if ran a && ran b && ! covered_line REG-B; then ok "5: a cover that cannot run here (UNTESTED) covers nothing"
else bad "5: an UNTESTED cover covered the suite (exit $RC)"; printf '%s\n' "$OUT" | tail -12; fi

# 6. both flagged parallel_safe: B must wait for A and be covered
make_repo "$(suite REG-A 'sh tests/a.sh' ',"parallel_safe":true'),$(suite REG-B 'sh tests/b.sh' ',"parallel_safe":true,"covered_by":"REG-A"')"
run_gate
if [ "$RC" = 0 ] && ran a && ! ran b && covered_line REG-B; then ok "6: both flagged parallel_safe: the covered one did not start next to its cover and is covered"
else bad "6: grouped covered suite ran (exit $RC, ran_b=$(ran b && echo yes || echo no))"; printf '%s\n' "$OUT" | tail -12; fi

# 7. self reference
make_repo "$(suite REG-B 'sh tests/b.sh' ',"covered_by":"REG-B"')"
run_gate
if [ "$RC" = 0 ] && ran b && ! covered_line REG-B; then ok "7: a suite never covers itself"
else bad "7: self-cover skipped the suite (exit $RC)"; printf '%s\n' "$OUT" | tail -12; fi

# 8. not transitive
make_repo "$(suite REG-A 'sh tests/a.sh'),$(suite REG-B 'sh tests/b.sh' ',"covered_by":"REG-A"'),$(suite REG-C 'sh tests/c.sh' ',"covered_by":"REG-B"')"
run_gate
if [ "$RC" = 0 ] && ! ran b && ran c && covered_line REG-B && ! covered_line REG-C; then ok "8: covering is not transitive: B is covered by A, C still runs"
else bad "8: chain (exit $RC, ran_b=$(ran b && echo yes || echo no) ran_c=$(ran c && echo yes || echo no))"; printf '%s\n' "$OUT" | tail -12; fi

# 9. field added only in the working copy
make_repo "$(suite REG-A 'sh tests/a.sh'),$(suite REG-B 'sh tests/b.sh')"
printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[%s,%s]}]}\n' \
  "$(suite REG-A 'sh tests/a.sh')" "$(suite REG-B 'sh tests/b.sh' ',"covered_by":"REG-A"')" > matrix.json   # uncommitted: the change under audit adds the field
run_gate   # an edited matrix is UNVERIFIED (exit 2) but the gate still runs HEAD's suites
if ran a && ran b && ! covered_line REG-B; then ok "9: covered_by added only in the working copy is ignored (the base-ref matrix decides)"
else bad "9: a working-copy edit skipped a suite (exit $RC)"; printf '%s\n' "$OUT" | tail -12; fi

# 10. no field, no change
make_repo "$(suite REG-A 'sh tests/a.sh'),$(suite REG-B 'sh tests/b.sh')"
run_gate
if [ "$RC" = 0 ] && ran a && ran b && ! covered_line REG-B; then ok "10: without the field both suites run"
else bad "10: baseline changed (exit $RC)"; printf '%s\n' "$OUT" | tail -12; fi

# 11. the covered PASS is in the receipt: the second run on the same content reuses it and runs nothing
make_repo "$(suite REG-A 'sh tests/a.sh'),$(suite REG-B 'sh tests/b.sh' ',"covered_by":"REG-A"')"
full_gate() { OUT="$(CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests --full --force-full 2>&1)"; RC=$?; }
full_gate
first_ok=0; [ "$RC" = 0 ] && ran a && ! ran b && first_ok=1
rm -f "$MARK/ran_a" "$MARK/ran_b"
full_gate
if [ "$first_ok" = 1 ] && [ "$RC" = 0 ] && ! ran a && ! ran b; then ok "11: the next full run on the same content reuses the receipt (the covered PASS is part of it)"
else bad "11: receipt not reused (exit $RC, ran_a=$(ran a && echo yes || echo no) ran_b=$(ran b && echo yes || echo no))"; printf '%s\n' "$OUT" | tail -12; fi

# 12. cover without a real run
make_repo "$(suite REG-U 'sh tests/u.sh editmode'),$(suite REG-A 'echo compile-only'),$(suite REG-B 'sh tests/b_fail.sh' ',"covered_by":"REG-A"')"
run_gate
if [ "$RC" = 1 ] && ran b && printf '%s\n' "$OUT" | grep -q "SKIP compile" && ! covered_line REG-B; then ok "12: a cover that ran nothing (SKIP compile) covers nothing; the covered suite ran and failed the gate"
else bad "12: a no-run cover covered a failing suite (exit $RC, ran_b=$(ran b && echo yes || echo no))"; printf '%s\n' "$OUT" | tail -14; fi

# 13. a suite that would run impacted is not covered, a --full run covers it
make_repo "$(suite REG-A 'sh tests/a.sh'),$(suite REG-B 'sh tests/b.sh' ',"impacted_command":"sh tests/b.sh {pytest_nodes}","covered_by":"REG-A"')"
run_gate
if [ "$RC" = 0 ] && ran b && ! covered_line REG-B; then ok "13a: without --full a suite with an impacted_command is not covered (it runs impacted, vacuity stays checked)"
else bad "13a: an impacted-mode suite was covered (exit $RC, ran_b=$(ran b && echo yes || echo no))"; printf '%s\n' "$OUT" | tail -12; fi
make_repo "$(suite REG-A 'sh tests/a.sh'),$(suite REG-B 'sh tests/b.sh' ',"impacted_command":"sh tests/b.sh {pytest_nodes}","covered_by":"REG-A"')"
OUT="$(CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests --full --force-full 2>&1)"; RC=$?
if [ "$RC" = 0 ] && ran a && ! ran b && covered_line REG-B; then ok "13b: under --full the same suite is covered"
else bad "13b: --full did not cover it (exit $RC, ran_b=$(ran b && echo yes || echo no))"; printf '%s\n' "$OUT" | tail -12; fi

# 14. the recorded row of a covered suite
make_repo "$(suite REG-A 'sh tests/a.sh'),$(suite REG-B 'sh tests/b.sh' ',"covered_by":"REG-A"')"
run_gate
row="$(python3 -c 'import json,sys
d = json.load(open(sys.argv[1])); b = d["items"]["REG-B"]["last"]; a = d["items"]["REG-A"]["last"]
print(b.get("status"), b.get("exit_code"), "samelog" if b.get("log") == a.get("log") and b.get("log") else "nolog")' "$R/.agents/regression_status.json" 2>&1)"
if [ "$row" = "PASS 0 samelog" ] && ! grep -q "exit None" "$R/.agents/CHECKLIST.md"; then ok "14: the covered suite's checklist row has exit 0 and its cover's log (no 'exit None')"
else bad "14: covered row = '$row'"; grep -n "REG-B" "$R/.agents/CHECKLIST.md" | head -3; fi

cd "$TMP" || exit 1
if [ "$FAILS" -ne 0 ]; then echo "covered_by: $FAILS FAILED"; exit 1; fi
echo "covered_by: all checks passed"
