#!/usr/bin/env bash
# #838: post-fix-gate.py --since only measured the NET change <since>..HEAD. A branch that merges origin/main (main adds an
# assertion to a test) and then a LOCAL commit removes exactly that assertion leaves the test byte-equal to <since>: the diff
# is empty, the gate said "nothing to check" and an approved assertion vanished unreviewed. Now a test a local commit touched
# is also compared with the newest landed (upstream) version in the range.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
mk() {  # fresh repo + bare remote + teammate clone; test_b holds one assertion
  local d="$TMP/$1"; mkdir -p "$d/src" "$d/tests" && cd "$d" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  printf '#!/bin/sh\n[ 1 = 1 ]\ntrue\n' > tests/test_b.sh
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/test_b.sh; true"}]}]}
JSON
  git add -A && git commit -qm init
  git init -q --bare -b main "$TMP/$1.git"; git remote add origin "$TMP/$1.git"
  git push -q -u origin main
  git clone -q "$TMP/$1.git" "$TMP/$1-mate"
  git -C "$TMP/$1-mate" config user.email m@m; git -C "$TMP/$1-mate" config user.name m
}
mate_adds_assertion() {
  printf '[ 2 = 2 ]\n' >> "$TMP/$1-mate/tests/test_b.sh"
  git -C "$TMP/$1-mate" commit -qam "main adds assertion"; git -C "$TMP/$1-mate" push -q origin main
}
gate() { CLAUDE_PROJECT_DIR="$PWD" python3 "$GATE" --matrix "$PWD/matrix.json" --lang en --run-tests --since "$1" 2>&1; }
expect() {  # <name> <flagged yes|no> <rc> <base>
  local out rc hit=no; out="$(gate "$4")"; rc=$?
  printf '%s' "$out" | grep -q "Existing test edited" && hit=yes
  if [ "$hit" = "$2" ] && [ "$rc" = "$3" ]; then echo "✔ $1 (flagged=$hit, exit $rc)"
  else echo "✖ $1: flagged=$hit want $2, exit $rc want $3"; printf '%s\n' "$out" | tail -15; FAILS=$((FAILS + 1)); fi
}

mk removed; since="$(git rev-parse HEAD)"; mate_adds_assertion removed
git pull -q --no-rebase --no-edit origin main
printf '#!/bin/sh\n[ 1 = 1 ]\ntrue\n' > tests/test_b.sh; git commit -qam "local: drop the assertion main added"
[ -z "$(git diff "$since" HEAD -- tests/test_b.sh)" ] || { echo "✖ fixture: test_b should equal <since>"; exit 1; }
expect "merge origin/main then a local commit removes main's assertion is flagged" yes 2 "$since"

mk pure; since="$(git rev-parse HEAD)"; mate_adds_assertion pure
git pull -q --no-rebase --no-edit origin main
echo "fun ok() = 2" > src/Core.kt; git commit -qam "local code change only"
expect "control: a pure merge of origin/main with no local test commit is not flagged" no 0 "$since"

[ "$FAILS" -eq 0 ] && echo "gate --since landed base: all checks passed" || { echo "gate --since landed base: $FAILS FAILED"; exit 1; }
