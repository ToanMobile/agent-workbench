#!/usr/bin/env bash
# Regression (agent-workbench #302): every new test appends a line to the tail of tests/lib/test_durations.txt (INSTINCT-036), so two PRs
# that each add a test conflicted on the last lines (merge gate exit 5, PR #259, 22-23/10). The repo's own .gitattributes routes the file
# to git's built-in `union` merge.
#   1. two branches append a different line each: merge is clean and keeps both lines (and no conflict marker)
#   2. both branches append the SAME line: it stays once
#   3. the tracked .gitattributes of this repo declares merge=union for the file (the merge itself is proved on a copy of that line)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
F="universal-agent-devkit/tests/lib/test_durations.txt"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0; ok() { echo "✔ $1"; }; bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
G() { git -C "$TMP/r" -c user.email=t@t -c user.name=t "$@"; }
grep -qxF "$F merge=union" "$ROOT/.gitattributes" && ok "3 .gitattributes routes the durations file to merge=union" || bad "3 .gitattributes lacks '$F merge=union'"
git init -q -b main "$TMP/r"; mkdir -p "$TMP/r/$(dirname "$F")"
grep -F "$F merge=" "$ROOT/.gitattributes" > "$TMP/r/.gitattributes"
printf '# header\n3 tests/a.sh\n' > "$TMP/r/$F"; G add -A; G commit -qm base
G checkout -q -b one; printf '4 tests/one.sh\n' >> "$TMP/r/$F"; G commit -qam one
G checkout -q main; G checkout -q -b two; printf '5 tests/two.sh\n' >> "$TMP/r/$F"; G commit -qam two
G checkout -q main; G checkout -q -b three; printf '4 tests/one.sh\n' >> "$TMP/r/$F"; G commit -qam three
G checkout -q one; G merge -q --no-edit two >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q 'tests/one.sh' "$TMP/r/$F" && grep -q 'tests/two.sh' "$TMP/r/$F" && ! grep -q '^<<<<<<<' "$TMP/r/$F" \
  && ok "1 two different appended lines merge cleanly, both kept" || { bad "1 appended lines conflicted (rc=$rc)"; G merge --abort >/dev/null 2>&1; }
G merge -q --no-edit three >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(grep -c 'tests/one.sh' "$TMP/r/$F")" = 1 ] && ok "2 an identical appended line stays once" || bad "2 identical line (rc=$rc, count=$(grep -c 'tests/one.sh' "$TMP/r/$F"))"
[ "$FAILS" = 0 ] && echo "ALL PASS" || { echo "$FAILS FAILED"; exit 1; }
