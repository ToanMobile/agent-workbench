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

# 2026-10-09: the trailer counts only with antigravity-pm's audit pass record for that task of this repository (kept outside
# the repo, as bin/push_gate.py checks it); a line the agent writes itself is not an audit.
export ANTIGRAVITY_PM_STATE_HOME="$TMP/pm"
export DEVKIT_PM_HOME_TEST=1   # #605: test-only switch, a fixture pm home under the temp dir counts for push_gate.approved
pm_pass() { # <task-id> [auditedHead, default HEAD]: an audit pass recorded for the repo in $PWD
  # Audit T0066 (#605): the PM verdict names the audited head (`auditedHead: <sha>` in notes); a trailer counts only on that tree.
  mkdir -p "$TMP/pm/projects/$(basename "$PWD")/tasks/$1"
  printf '{"id":"%s","project":"%s","verdicts":{"audit":{"verdict":"pass","round":1,"notes":"auditedHead: %s"}}}\n' "$1" "$PWD" \
    "${2:-$(git rev-parse HEAD)}" > "$TMP/pm/projects/$(basename "$PWD")/tasks/$1/task.json"
}

# Audit T0066 (#605): an old task's audit pass (auditedHead = the base) reused in the trailer of a NEW weakening is no audit
mk replayed_trailer; base="$(git rev-parse HEAD)"
pm_pass T0002-old "$base"
printf '#!/bin/sh\ntrue\n' > tests/test_old.sh; echo "fun ok() = 2" > src/Core.kt
git commit -qam "weaken test + fix" -m "Test-approved-by: antigravity T0002-old"
expect "a trailer reusing an old task whose auditedHead tree differs is still flagged" yes 2 "$base"

mk self_approved; base="$(git rev-parse HEAD)"
printf '#!/bin/sh\ntrue\n' > tests/test_old.sh; echo "fun ok() = 2" > src/Core.kt
git commit -qam "weaken test + fix" -m "Test-approved-by: antigravity T0001-audit"
expect "a Test-approved-by line with no antigravity-pm audit record is still flagged" yes 2 "$base"

mk approved; base="$(git rev-parse HEAD)"
printf '#!/bin/sh\ntrue\n' > tests/test_old.sh; echo "fun ok() = 2" > src/Core.kt
git commit -qam "weaken test + fix" -m "Test-approved-by: antigravity T0001-audit"
pm_pass T0001-audit
expect "weakened test in a Test-approved-by commit is not flagged" no 0 "$base"

# #630: the trailer sits on an EMPTY commit after the audited tree (the #605 flow): no `-- <path>` pathspec may hide it
mk empty_trailer; base="$(git rev-parse HEAD)"
printf '#!/bin/sh\ntrue\n' > tests/test_old.sh; echo "fun ok() = 2" > src/Core.kt
git commit -qam "weaken test + fix"
pm_pass T0630-empty
git commit -q --allow-empty -m "audit" -m "Test-approved-by: antigravity T0630-empty"
# the cross-review path can rescue the exit code, so judge since_test_weakened itself: it must not call the audited test weakened
sw="$(CLAUDE_PROJECT_DIR="$PWD" python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("pfg", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.since_test_weakened(sys.argv[2], "tests/test_old.sh"))' "$GATE" "$base" 2>&1 | tail -1)"
if [ "$sw" = False ]; then echo "✔ since_test_weakened sees the trailer on an empty commit"
else echo "✖ since_test_weakened ignored the trailer on an empty commit: $sw"; FAILS=$((FAILS + 1)); fi

mk approved_then_weakened; base="$(git rev-parse HEAD)"
printf '#!/bin/sh\ntrue\n' > tests/test_old.sh
git commit -qam "weaken test" -m "Test-approved-by: antigravity T0001-audit"
pm_pass T0001-audit
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
