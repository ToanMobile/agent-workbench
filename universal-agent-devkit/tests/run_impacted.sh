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
done
selected="$(printf '%s\n' $tests | sort -u)"

if [ "${1:-}" = "--list" ]; then
  for t in $selected; do [ -f "$t" ] && echo "$t"; done
  exit 0
fi

rc=0
log="$(mktemp)"
for t in $selected; do
  [ -f "$t" ] || continue
  if bash "$t" >"$log" 2>&1; then
    echo "✔ $t"
  else
    echo "✖ $t"; tail -n 20 "$log" | sed 's/^/    /'; rc=1
  fi
done
rm -f "$log"
exit "$rc"
