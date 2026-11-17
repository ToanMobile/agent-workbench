#!/usr/bin/env bash
# #1255: soft guidance "about 400 changed lines per PR, short, no repeats, split by AC or say why" in
# worker-preamble, super-build and super-review. Not a gate: auto_max_lines stays 0, nothing blocks a merge.
set -u
export LC_ALL=C LANG=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SB="$ROOT/.claude/skills"
PRE="$SB/super-build/references/worker-preamble.md"
BUILD="$SB/super-build/SKILL.md"
REVIEW="$SB/super-review/SKILL.md"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
has() { grep -q "$2" "$1" && ok "$3" || fail "$3"; }

for f in "$PRE" "$BUILD"; do
  n=$(basename "$(dirname "$f")")/$(basename "$f")
  has "$f" "PR size (#1255)" "$n: has the PR size paragraph"
  has "$f" "about 400 changed lines" "$n: states the ~400-line target"
  has "$f" "not a gate" "$n: says it is not a gate"
  has "$f" "auto_max_lines" "$n: names auto_max_lines"
  has "$f" "no repeated idea" "$n: no repeated ideas"
  has "$f" "split" "$n: split by AC or give a reason"
done
has "$BUILD" "One card, one PR if it fits" "super-build: reconciles with one-PR-per-card"
has "$REVIEW" "PR size (#1255)" "super-review: has the PR size rule"
has "$REVIEW" "Scope drift" "super-review: classes it as Scope drift/Over-engineering"
has "$REVIEW" "never blocks a merge" "super-review: never blocks a merge"

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
