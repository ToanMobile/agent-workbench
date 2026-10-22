#!/usr/bin/env bash
# Regression test (issue #223): the pre-commit check scripts/git/check-test-durations.sh rejects a STAGED new
# tests/*/test_*.sh that tests/lib/test_durations.txt does not list, and prints the line to add.
# Before: the gap only surfaced in test_run_impacted_order.sh at the QA gate --full (15-25 min per round; #155, #157).
# Every case runs in a scratch repo that holds a fake kit (never the real one). bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$DEVKIT_DIR/scripts/git/check-test-durations.sh"
HOOK="$DEVKIT_DIR/scripts/git/git-pre-commit.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export DEVKIT_LANG=en
FAILS=0; ok() { echo "✔ $1"; }; fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

[ -f "$CHECK" ] || { fail "scripts/git/check-test-durations.sh does not exist"; echo "precommit_test_durations: $FAILS FAILED"; exit 1; }

# a repo whose kit sits in a sub folder (like agent-workbench/universal-agent-devkit) or at the root (the kit's own repo)
mk_repo() { # <dir> <kit sub folder or "."> : one listed test, committed
  local r="$1" k="$2" kd
  rm -rf "$r"; mkdir -p "$r"; ( cd "$r" && git init -q . && git config user.email t@t && git config user.name t )
  kd="$r/$k"; mkdir -p "$kd/tests/lib" "$kd/tests/gates"
  printf '# header\n3 tests/gates/test_old.sh\n' > "$kd/tests/lib/test_durations.txt"
  echo 'exit 0' > "$kd/tests/gates/test_old.sh"
  ( cd "$r" && git add -A && git commit -qm init )
}
run_check() { # <repo> <kit sub folder or "."> -> OUT, RC
  local kd="$1/$2"; kd="$(cd "$kd" && pwd -P)"
  OUT="$(cd "$1" && DEVKIT_ROOT="$kd" bash "$CHECK" 2>&1)"; RC=$?
}

for K in kit .; do
  R="$TMP/r_$([ "$K" = . ] && echo root || echo sub)"; mk_repo "$R" "$K"; P="${K#.}"; P="${P:+$P/}"
  # 1) a new unlisted test is rejected and the line to add is printed
  echo 'exit 0' > "$R/${P}tests/gates/test_new.sh"; ( cd "$R" && git add "${P}tests/gates/test_new.sh" )
  run_check "$R" "$K"
  [ "$RC" != 0 ] && printf '%s' "$OUT" | grep -q 'tests/lib/test_durations.txt' && printf '%s' "$OUT" | grep -qE '^ +[0-9]+ tests/gates/test_new\.sh$' \
    && ok "[$K] staged unlisted test: exit $RC and the line '<seconds> tests/gates/test_new.sh' is printed" || fail "[$K] unlisted test not rejected (rc=$RC): $OUT"
  # 2) listing it (staged in the same commit) lets it through
  printf '4 tests/gates/test_new.sh\n' >> "$R/${P}tests/lib/test_durations.txt"; ( cd "$R" && git add "${P}tests/lib/test_durations.txt" )
  run_check "$R" "$K"
  [ "$RC" = 0 ] && ok "[$K] listed in the same commit: passes" || fail "[$K] listed test rejected (rc=$RC): $OUT"
  # 3) the check reads the STAGED list: a line only in the working tree does not count
  ( cd "$R" && git reset -q "${P}tests/lib/test_durations.txt" && git checkout -q -- "${P}tests/lib/test_durations.txt" && printf '4 tests/gates/test_new.sh\n' >> "${P}tests/lib/test_durations.txt" )
  run_check "$R" "$K"
  [ "$RC" != 0 ] && ok "[$K] a line left unstaged in the working tree does not count" || fail "[$K] unstaged line accepted"
  ( cd "$R" && git checkout -q -- "${P}tests/lib/test_durations.txt" )
done

# 4) tests already listed, edits to them, non-test files and tests outside tests/*/ are not affected
R="$TMP/r_other"; mk_repo "$R" kit
echo '# edit' >> "$R/kit/tests/gates/test_old.sh"; echo hi > "$R/kit/README.md"; mkdir -p "$R/kit/tests/lib" "$R/kit/tests/fixtures/deep"
echo 'exit 0' > "$R/kit/tests/fixtures/deep/test_nested.sh"; echo 'x' > "$R/kit/tests/lib/helper.sh"; echo 'exit 0' > "$R/other_test.sh"
( cd "$R" && git add -A )
run_check "$R" kit
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "listed test edited, docs, helper, nested fixture and a test outside the kit: no complaint" || fail "false positive (rc=$RC): $OUT"

# 5) a kit that is not inside the repo, or no durations file at all: nothing to compare against, never blocks
R="$TMP/r_none"; mk_repo "$R" kit; rm -f "$R/kit/tests/lib/test_durations.txt"; ( cd "$R" && git add -A && git commit -qm drop )
echo 'exit 0' > "$R/kit/tests/gates/test_new.sh"; ( cd "$R" && git add -A )
run_check "$R" kit
[ "$RC" = 0 ] && ok "no durations file: no verdict to give, commit not blocked" || fail "blocked without a durations file (rc=$RC): $OUT"
mk_repo "$R" kit; echo 'exit 0' > "$R/kit/tests/gates/test_new.sh"; ( cd "$R" && git add -A )
OUT="$(cd "$R" && DEVKIT_ROOT="$TMP" bash "$CHECK" 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "kit outside the repo: not blocked" || fail "kit outside the repo blocked (rc=$RC): $OUT"

# 6) the hook runs the check (wiring)
grep -q 'check-test-durations.sh' "$HOOK" && ok "git-pre-commit.sh calls check-test-durations.sh" || fail "git-pre-commit.sh does not call check-test-durations.sh"

if [ "$FAILS" -ne 0 ]; then echo "precommit_test_durations: $FAILS FAILED"; exit 1; fi
echo "precommit_test_durations: all checks passed"
