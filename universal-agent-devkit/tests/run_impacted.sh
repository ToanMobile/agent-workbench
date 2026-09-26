#!/usr/bin/env bash
# Runs the DevKit tests that name a changed DevKit code file, every changed test script itself,
# and the fast repo-consistency check. "Changed" = working tree vs HEAD, new files, and commits
# not pushed yet (no upstream: the last 6 hours), so committing inside a turn does not leave the
# gate testing nothing. A helper under tests/ selects the tests that source it by name.
# The full suite (`agent-kit test`) runs far longer than post-fix-gate's 900 s per command,
# so a regression matrix that watches the DevKit (agent-workbench's) uses this instead.
# ponytail: a changed file that no test names gets repo-consistency only, add a test when such a file breaks
# Usage: run_impacted.sh [--list]   (--list prints the selection and runs nothing)
# bash 3.2 compatible.
set -u
DK="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DK" || exit 2

if git rev-parse -q --verify '@{u}' >/dev/null 2>&1; then
  unpushed="$(git log '@{u}..HEAD' --name-only --relative --format= -- . 2>/dev/null)"
else
  unpushed="$(git log --since=6.hours --name-only --relative --format= -- . 2>/dev/null)"
fi
changed="$( { git diff HEAD --name-only --relative -- . ; git ls-files -o --exclude-standard -- . ; printf '%s\n' "$unpushed"; } 2>/dev/null \
  | grep -vE '(^|/)(CHANGELOG|README[^/]*)\.md$' | sort -u)"   # templates and rules are read by tests too
tests="tests/test_repo_consistency.sh"
for f in $changed; do
  case "$f" in
    tests/test_*.sh|hooks/tests/*.sh) tests="$tests $f"; continue ;;
  esac   # a helper under tests/ falls through: every test that sources it names it
  tests="$tests $(grep -l -F -- "$(basename "$f")" tests/test_*.sh hooks/tests/*.sh 2>/dev/null | tr '\n' ' ')"
  # …or its stem as a whole word: tests reach scripts through commands ("agent-kit githooks
  # install" → scripts/githooks.sh; test_githooks went unrun on 2026-09-26).
  stem="$(basename "$f")"; stem="${stem%.*}"
  [ -n "$stem" ] && [ "$stem" != "$(basename "$f")" ] \
    && tests="$tests $(grep -l -w -F -- "$stem" tests/test_*.sh hooks/tests/*.sh 2>/dev/null | tr '\n' ' ')"
done
selected="$(printf '%s\n' $tests | sort -u)"

if [ "${1:-}" = "--list" ]; then
  for t in $selected; do [ -f "$t" ] && echo "$t"; done
  exit 0
fi

# Parallel, DEVKIT_TEST_JOBS at a time (default 4): run one after another the suite took 740 s of
# the gate's 900 s (2026-09-26). Every test works in its own mktemp dir. Timing tests
# (test_budgets, test_session_context's bounded fetch) run alone afterwards, so the others cannot slow them. Output keeps list order.
JOBS="${DEVKIT_TEST_JOBS:-4}"
case "$JOBS" in ''|*[!0-9]*|0) JOBS=4 ;; esac
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
