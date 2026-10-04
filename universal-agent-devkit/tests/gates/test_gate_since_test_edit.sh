#!/usr/bin/env bash
# Regression test: bin/post-fix-gate.py --since <ref> (hooks/regression_gate.sh gates the commits
# after the last verified HEAD) must flag an EXISTING test weakened and COMMITTED in <ref>..HEAD.
# 2026-09-28: the edited-test check compared against HEAD only, so a weakened test committed after
# <ref> equalled HEAD and passed silently. Escapes: an append-only change, a commit in the range
# touching the file with `Test-approved-by:`, and (control) a test ADDED in the range.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0

# Fresh repo per scenario; prints the base commit. tests/test_old.sh holds an assertion line.
mk() {
  local d="$TMP/$1"
  mkdir -p "$d/src" "$d/tests" && cd "$d" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  printf '#!/bin/sh\n[ 1 = 1 ]\ntrue\n' > tests/test_old.sh
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","tests/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh tests/test_old.sh && for f in tests/test_n*.sh; do [ -f \"$f\" ] && sh \"$f\"; done; true"}]}]}
JSON
  git add -A && git commit -qm init
}
run_gate() { CLAUDE_PROJECT_DIR="$PWD" python3 "$GATE" --matrix "$PWD/matrix.json" --lang en --run-tests --since "$1" 2>&1; }
expect() {  # expect <name> <flagged:yes|no> <want_rc> <base>
  local out rc hit=no
  out="$(run_gate "$4")"; rc=$?
  printf '%s' "$out" | grep -q "Existing test edited" && hit=yes
  if [ "$hit" = "$2" ] && [ "$rc" = "$3" ]; then echo "✔ $1 (flagged=$hit, exit $rc)"
  else echo "✖ $1: flagged=$hit want $2, exit $rc want $3"; printf '%s\n' "$out" | tail -15; FAILS=$((FAILS + 1)); fi
}

mk weaken; base="$(git rev-parse HEAD)"
printf '#!/bin/sh\ntrue\n' > tests/test_old.sh; echo "fun ok() = 2" > src/Core.kt
git commit -qam "weaken test + fix"
expect "weakened existing test committed in --since range is flagged" yes 2 "$base"

mk append; base="$(git rev-parse HEAD)"
printf '[ 3 = 3 ]\n' >> tests/test_old.sh; echo "fun ok() = 2" > src/Core.kt
git commit -qam "append a test + fix"
expect "append-only change committed in the range is not flagged" no 0 "$base"

mk approved; base="$(git rev-parse HEAD)"
printf '#!/bin/sh\ntrue\n' > tests/test_old.sh; echo "fun ok() = 2" > src/Core.kt
git commit -qam "weaken test + fix" -m "Test-approved-by: antigravity T1"
expect "weakened test in a Test-approved-by commit is not flagged" no 0 "$base"

mk approved_then_weakened; base="$(git rev-parse HEAD)"
printf '#!/bin/sh\ntrue\n' > tests/test_old.sh
git commit -qam "weaken test" -m "Test-approved-by: antigravity T1"
printf '#!/bin/sh\n' > tests/test_old.sh; echo "fun ok() = 2" > src/Core.kt
git commit -qam "weaken again, no approval"
expect "a later unapproved weakening after an approved commit is flagged" yes 2 "$base"

mk deleted; base="$(git rev-parse HEAD)"
git rm -q tests/test_old.sh; echo "fun ok() = 2" > src/Core.kt
sed -i.bak 's#sh tests/test_old.sh && ##' matrix.json && rm -f matrix.json.bak
git commit -qam "delete test + fix"
expect "existing test deleted in a --since commit is flagged" yes 2 "$base"

mk newtest; base="$(git rev-parse HEAD)"
printf '#!/bin/sh\n[ 2 = 2 ]\n' > tests/test_new.sh; echo "fun ok() = 2" > src/Core.kt
git add -A && git commit -qm "new test + fix"
expect "control: a test added in the range is not flagged" no 0 "$base"

mk uncommitted; base="$(git rev-parse HEAD)"
echo "fun ok() = 2" > src/Core.kt; git commit -qam fix
printf '#!/bin/sh\ntrue\n' > tests/test_old.sh
expect "control: an uncommitted weakening still blocks under --since" yes 2 "$base"

# A teammate's weakening already on the upstream, brought in by this session's `git pull`, is
# not this session's to gate (it passed their own push gate); the same kind of edit local-only is.
mk upstream; base="$(git rev-parse HEAD)"
git init -q --bare -b main "$TMP/remote.git"
git remote add origin "$TMP/remote.git"
git push -q -u origin HEAD:main
git clone -q "$TMP/remote.git" "$TMP/mate"
git -C "$TMP/mate" config user.email m@m; git -C "$TMP/mate" config user.name m
printf '#!/bin/sh\ntrue\n' > "$TMP/mate/tests/test_old.sh"
git -C "$TMP/mate" commit -qam "teammate weakens"
git -C "$TMP/mate" push -q origin HEAD:main
git pull -q --no-rebase origin main
git branch -q --set-upstream-to=origin/main
expect "a weakening already on the upstream (pulled) is not flagged" no 0 "$base"
echo "fun ok() = 2" > src/Core.kt; printf '#!/bin/sh\n' > tests/test_old.sh
git commit -qam "local-only weakening + fix"
expect "the same kind of weakening as a local-only commit (upstream set) is flagged" yes 2 "$base"
out="$(run_gate "$base")"
if printf '%s' "$out" | grep -q "or commit it"; then
  echo "✖ --since verdict still offers 'or commit it'"; FAILS=$((FAILS + 1))
else echo "✔ --since verdict does not offer a plain commit as the cure"; fi
if printf '%s' "$out" | grep -q "Test-approved-by:"; then echo "✔ --since verdict names Test-approved-by:"
else echo "✖ --since verdict does not name Test-approved-by:"; FAILS=$((FAILS + 1)); fi

[ "$FAILS" -eq 0 ] && echo "gate --since edited test: all checks passed" || { echo "gate --since edited test: $FAILS FAILED"; exit 1; }
