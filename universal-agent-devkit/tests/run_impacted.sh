#!/usr/bin/env bash
# Runs the DevKit tests that name a changed DevKit code file, every changed test script itself,
# and the fast repo-consistency check. "Changed" = working tree vs HEAD, new files, and commits
# not pushed yet (no upstream: the last 6 hours), so committing inside a turn does not leave the
# gate testing nothing. A helper under tests/ selects the tests that source it by name.
# The full suite (`agent-kit test`) runs far longer than post-fix-gate's 900 s per command,
# so a regression matrix that watches the DevKit (agent-workbench's) uses this instead.
# ponytail: a changed file that no test names gets repo-consistency only, add a test when such a file breaks
# Usage: run_impacted.sh [--list | --all | --jobs]   (--list prints the selection and runs nothing; --all runs the whole
# suite, whatever changed: what `agent-kit test` calls, in parallel — one test after another took ~19 min;
# --jobs prints how many tests a run starts at once and exits)
# bash 3.2 compatible.
set -u
DK="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DK" || exit 2

# Tests started at once: DEVKIT_TEST_JOBS when it is a positive integer, else min(cores - 2, 10) with a floor of 4, the old default, so a small machine runs as before (cores from
# nproc, sysctl hw.ncpu or python3; none answers: 4, the old default). 2026-10-04: `--all` took 301 s for 102 tests at 4 jobs on 12 cores (bound by the job count: about 20 min of tests / 4).
# DEVKIT_TEST_CORES pretends a core count (tests only). `--jobs` prints the number a run would use.
pint() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; [ $((10#$1)) -gt 0 ]; }   # 10# so 08 is eight, 00 is not "unlimited"
default_jobs() {
  local c="${DEVKIT_TEST_CORES:-}"
  pint "$c" || c="$(nproc 2>/dev/null)"
  pint "$c" || c="$(sysctl -n hw.ncpu 2>/dev/null)"
  pint "$c" || c="$(python3 -c 'import os; print(os.cpu_count() or 0)' 2>/dev/null)"
  pint "$c" || { echo 4; return; }
  c=$((10#$c - 2)); [ "$c" -gt 10 ] && c=10; [ "$c" -lt 4 ] && c=4
  echo "$c"
}
jobs_now() { # what a run uses: the override when valid, else the default
  if pint "${DEVKIT_TEST_JOBS:-}"; then echo $((10#$DEVKIT_TEST_JOBS)); else default_jobs; fi
}
[ "${1:-}" = "--jobs" ] && { jobs_now; exit 0; }

if git rev-parse -q --verify '@{u}' >/dev/null 2>&1; then
  unpushed="$(git log '@{u}..HEAD' --name-only --relative --format= -- . 2>/dev/null)"
else
  unpushed="$(git log --since=6.hours --name-only --relative --format= -- . 2>/dev/null)"
fi
changed="$( { git diff HEAD --name-only --relative -- . ; git ls-files -o --exclude-standard -- . ; printf '%s\n' "$unpushed"; } 2>/dev/null \
  | grep -vE '(^|/)(CHANGELOG|README[^/]*)\.md$' | sort -u)"   # templates and rules are read by tests too
# Only tests/verification/test_impact_map.sh sets this, and only for --list (which runs nothing): it pretends these
# files changed (newline separated). A run that executes tests ignores it, so nobody can shrink the gate's selection.
[ "${1:-}" = "--list" ] && [ -n "${DEVKIT_IMPACT_TEST_CHANGED:-}" ] && changed="$DEVKIT_IMPACT_TEST_CHANGED"
tests="tests/verification/test_repo_consistency.sh"
for f in $changed; do
  case "$f" in
    tests/*/test_*.sh|hooks/tests/*.sh) tests="$tests $f"; continue ;;
  esac   # a helper under tests/ falls through: every test that sources it names it
  tests="$tests $(grep -l -F -- "$(basename "$f")" tests/*/test_*.sh hooks/tests/*.sh 2>/dev/null | tr '\n' ' ')"
  # …or its stem as a whole word: tests reach scripts through commands ("agent-kit githooks
  # install" → scripts/githooks.sh; test_githooks went unrun on 2026-09-26).
  stem="$(basename "$f")"; stem="${stem%.*}"
  [ -n "$stem" ] && [ "$stem" != "$(basename "$f")" ] \
    && tests="$tests $(grep -l -w -F -- "$stem" tests/*/test_*.sh hooks/tests/*.sh 2>/dev/null | tr '\n' ' ')"
  # …and the tests tests/impact_map.txt declares for a file they exercise without naming it.
  while read -r glob rest; do
    case "$glob" in ''|'#'*) continue ;; esac
    case "$f" in $glob) tests="$tests $rest" ;; esac
  done < tests/impact_map.txt
done
selected="$(printf '%s\n' $tests | sort -u)"
# --all: every test. Finding none is an error — a glob that matches nothing must not pass.
if [ "${1:-}" = "--all" ]; then
  selected="$(ls tests/*/test_*.sh 2>/dev/null)"
  [ -n "$selected" ] || { echo "run_impacted --all: no tests found under tests/*/test_*.sh" >&2; exit 2; }
fi
# post-fix-gate lists the test scripts it already ran in this gate (O2): not run twice.
if [ -n "${DEVKIT_GATE_DONE:-}" ]; then
  DKP="$(pwd -P)"; keep=""
  for t in $selected; do
    printf '%s\n' "$DEVKIT_GATE_DONE" | grep -qxF "$DKP/$t" && continue
    keep="$keep $t"
  done
  selected="$keep"
fi

if [ "${1:-}" = "--list" ]; then
  for t in $selected; do [ -f "$t" ] && echo "$t"; done
  exit 0
fi

# Parallel, $JOBS at a time (jobs_now above): run one after another the suite took 740 s of
# the gate's 900 s (2026-09-26). Every test works in its own mktemp dir. Timing tests
# (test_budgets, test_session_context's bounded fetch) run alone afterwards, so the others cannot slow them. Output keeps list order.
JOBS="$(jobs_now)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
run_one() { # <test> <out dir>
  local o
  o="$2/$(printf '%s' "$1" | tr '/' '_')"
  if bash "$1" >"$o.log" 2>&1; then echo 0 >"$o.rc"; else echo 1 >"$o.rc"; fi
}
export -f run_one
parallel="" alone=""
for t in $selected; do
  [ -f "$t" ] || continue
  case "$t" in */test_budgets.sh|*/test_session_context.sh) alone="$alone $t" ;; *) parallel="$parallel $t" ;; esac
done
# Start the longest tests first (tests/lib/test_durations.txt: `<seconds> <path>`; a test it does not list starts first, as it
# may be slow): a 137 s test that starts last becomes the tail of the whole run. ONLY the start order of $parallel changes: $selected
# (what runs, what is printed, in which order) is untouched, and the reordered list is used only if it holds exactly the same tests.
dur="tests/lib/test_durations.txt"
if [ -n "$parallel" ] && [ -r "$dur" ]; then
  ordered="$(printf '%s\n' $parallel | LC_ALL=C awk -v F="$dur" '
    BEGIN { while ((getline l < F) > 0) { n = split(l, a, /[ \t]+/); if (n >= 2 && a[1] ~ /^[0-9]+(\.[0-9]+)?$/) d[a[2]] = a[1] + 0 } }
    { print (($0 in d) ? d[$0] : 1000000000), NR, $0 }' 2>/dev/null | LC_ALL=C sort -k1,1nr -k2,2n 2>/dev/null | cut -d' ' -f3- 2>/dev/null)"
  [ "$(printf '%s\n' $ordered | LC_ALL=C sort)" = "$(printf '%s\n' $parallel | LC_ALL=C sort)" ] && parallel="$ordered"
fi
[ -n "$parallel" ] && printf '%s\n' $parallel | xargs -P "$JOBS" -I{} bash -c 'run_one "$1" "$2"' _ {} "$out"
for t in $alone; do run_one "$t" "$out"; done
rc=0
for t in $selected; do
  [ -f "$t" ] || continue
  o="$out/$(printf '%s' "$t" | tr '/' '_')"
  if [ "$(cat "$o.rc" 2>/dev/null)" = 0 ]; then
    echo "✔ $t"
  else
    echo "✖ $t"; tail -n 20 "$o.log" 2>/dev/null | sed 's/^/    /'; rc=1
  fi
done
exit "$rc"
