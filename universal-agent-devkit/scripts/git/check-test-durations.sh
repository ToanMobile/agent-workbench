#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# check-test-durations.sh — called by git-pre-commit.sh. WARNS (stderr, exit 0, #365) about a commit that ADDS a
# tests/*/test_*.sh of the DevKit which tests/lib/test_durations.txt does not list, and prints the line to
# add. The list is only a start-order hint (a test it does not list starts first), so a gap never blocks a
# commit. Same list, same line format `<seconds> <path>` as run_impacted.sh; the list is read
# from the INDEX, so a line staged in the same commit counts and one left in the working tree does not.
# Nothing to compare (kit outside the repo, no staged list, no added test, any git error): exit 0.
# DEVKIT_ROOT overrides the kit folder (tests). bash 3.2 compatible.
# ─────────────────────────────────────────────────────────────────────────────
set -u
DEVKIT_ROOT="${DEVKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
ROOT="$(cd "$ROOT" && pwd -P)"; DEVKIT_ROOT="$(cd "$DEVKIT_ROOT" 2>/dev/null && pwd -P)" || exit 0
case "$DEVKIT_ROOT/" in "$ROOT"/*) ;; *) exit 0 ;; esac            # the kit is not part of this repo
P="${DEVKIT_ROOT#"$ROOT"}"; P="${P#/}"; [ -n "$P" ] && P="$P/"     # kit folder relative to the repo root, with a trailing /
DUR="${P}tests/lib/test_durations.txt"
list="$(git show ":$DUR" 2>/dev/null)" || exit 0                   # no staged list: nothing to compare against
added="$(git diff --cached --no-renames --name-only --diff-filter=A 2>/dev/null)" || exit 0   # a rename is a new path too

missing=""
while IFS= read -r f; do
  case "$f" in "${P}tests/"*/test_*.sh) ;; *) continue ;; esac
  rel="${f#"$P"}"
  d="${rel#tests/}"; case "${d#*/}" in */*) continue ;; esac       # only tests/<dir>/test_*.sh, as the order test globs
  # same parse as tests/run_impacted.sh: split on [ \t]+, a number first, the path second, extra fields ignored
  printf '%s\n' "$list" | awk -v p="$rel" '{ n = split($0, a, /[ \t]+/); if (n >= 2 && a[1] ~ /^[0-9]+(\.[0-9]+)?$/ && a[2] == p) f = 1 } END { exit !f }' || missing="$missing $rel"
done <<EOF
$added
EOF
[ -z "$missing" ] && exit 0

{
  echo "warning: tests/lib/test_durations.txt does not list the new test(s); they start first (default duration), nothing is blocked."
  echo "Add to ${DUR} and stage it (seconds = a rough measured duration; only the start order uses it):"
  for rel in $missing; do printf '    5 %s\n' "$rel"; done
} >&2
exit 0
