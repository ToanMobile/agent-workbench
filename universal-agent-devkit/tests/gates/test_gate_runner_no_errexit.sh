#!/usr/bin/env bash
# bin/post-fix-gate.py, a suite runner script WITHOUT `set -e` (2026-10-09 follow-up, plan docs/plans/audit-2026-10-09-followup.md
# step 3 item 3; policy decided by the user: yes, only for runners without set -e). A shell runner's exit status is its LAST command's
# unless `set -e` stops it at the first failure, so one command appended at the end (`echo done`) made a runner exit 0 over a
# failing check before it, and the gate counted it a pure append (only `exit 0`, `true`, `|| true`, `set +e` were caught). Now:
#   - a shell runner (.sh / .bash / .zsh, or an extensionless #! sh script) whose BASE version has no `set -e` / `set -o errexit` /
#     `#!… -e` counts as an edited existing test when any code line is appended (comments and blank lines stay free);
#   - a runner with `set -e` still accepts pure appends, and so does a runner in another language.
# The existing approval path (--auto-approve-tests) lifts it like any edited test.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# mk <name> <runner file content>: a repo whose suite command runs scripts/check.sh
mk() {
  local d="$TMP/$1"
  mkdir -p "$d/src" "$d/scripts" && cd "$d" || exit 1
  git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false
  printf 'def f():\n    return 1\n' > src/core.py
  printf '%s' "$2" > scripts/check.sh
  cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","scripts/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"sh scripts/check.sh"}]}]}
JSON
  git add -A && git commit -qm init
}
gate() {
  OUT="$(CLAUDE_PROJECT_DIR="$PWD" POSTFIX_GATE_FORCE_FULL=1 FLAKY_RETRY_MAX_S=60 python3 "$GATE" --matrix "$PWD/matrix.json" \
         --lang en --json "$@" 2>&1)"; RC=$?
  JSON="$(printf '%s\n' "$OUT" | grep '^{' | tail -1)"
}
j() { printf '%s' "$JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1" 2>/dev/null; }
touched() { [ "$(j '"scripts/check.sh" in d["tests_touched"]')" = "True" ]; }
# case <label> <want: flagged|free> <runner base> <text appended>
case_() {
  mk "c$((++N))" "$3"
  printf '%s' "$4" >> scripts/check.sh
  gate --dry-run
  if [ "$2" = flagged ]; then touched && ok "$1" || bad "$1: not reported as an edited runner (tests_touched: $(j 'd["tests_touched"]'))"
  else touched && bad "$1: reported as an edited runner" || ok "$1"; fi
}
N=0
NOSETE='#!/bin/sh
grep -q "return 1" src/core.py
'

# a runner without set -e: any appended command can hide an earlier failure
case_ "no set -e: an appended 'echo done' is an edit"           flagged "$NOSETE" 'echo done
'
case_ "no set -e: an appended check is an edit too"             flagged "$NOSETE" 'grep -q def src/core.py
'
case_ "no set -e: an appended call of another script"           flagged "$NOSETE" 'sh scripts/more.sh
'
# still free: nothing that runs
case_ "no set -e: an appended comment is free"                  free    "$NOSETE" '# one more check below, later
'
case_ "no set -e: appended blank lines are free"                free    "$NOSETE" '

'
# a runner that stops at the first failure keeps accepting pure appends
case_ "set -e: an appended command stays a pure append"         free    '#!/bin/sh
set -e
grep -q "return 1" src/core.py
' 'echo done
'
case_ "set -eu: an appended command stays a pure append"        free    '#!/bin/sh
set -eu
grep -q "return 1" src/core.py
' 'grep -q def src/core.py
'
case_ "set -o errexit: an appended command stays a pure append" free    '#!/bin/bash
set -o errexit
grep -q "return 1" src/core.py
' 'echo done
'
case_ "#!/bin/sh -e alone is no errexit (bash run.sh ignores it)" flagged '#!/bin/sh -e
grep -q "return 1" src/core.py
' 'echo done
'
case_ "set -o pipefail -e: an appended command stays a pure append" free    '#!/bin/bash
set -o pipefail -e
grep -q "return 1" src/core.py
' 'echo done
'
case_ "set +o pipefail -e: an appended command stays a pure append" free    '#!/bin/bash
set +o pipefail -e
grep -q "return 1" src/core.py
' 'echo done
'
# the neutralisers the gate already caught are still caught under set -e
case_ "set -e: an appended 'exit 0' is still an edit"           flagged '#!/bin/sh
set -e
grep -q "return 1" src/core.py
' 'exit 0
'

# a change of src/ with an appended command in a no-set -e runner: not a PASS until approved; the approval path lifts it
mk approve "$NOSETE"
printf 'echo done\n' >> scripts/check.sh
printf 'def f():\n    return 1\n# note\n' > src/core.py
gate --run-tests --full
[ "$RC" = 2 ] && ok "no set -e + appended command + passing change: exit 2 (UNVERIFIED), not a PASS" || { bad "exit $RC, want 2"; printf '%s\n' "$OUT" | grep -v '^{' | grep -E '✖|VERDICT' | head -5; }
gate --run-tests --full --auto-approve-tests
[ "$RC" = 0 ] && ok "  … and --auto-approve-tests lifts it (exit 0)" || bad "approved: exit $RC, want 0"

# a runner in another language: unchanged (the rule is about shell's last-command status)
mk pyrunner 'x
'
printf '#!/usr/bin/env python3\nimport subprocess, sys\nsys.exit(subprocess.call(["grep", "-q", "return 1", "src/core.py"]))\n' > scripts/run.py
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*","scripts/*"],
 "mandatory_regression_tests":[{"id":"REG-1","name":"core","command":"python3 scripts/run.py"}]}]}
JSON
git add -A && git commit -qm py
printf 'print("one more")\n' >> scripts/run.py
gate --dry-run
[ "$(j '"scripts/run.py" in d["tests_touched"]')" = "True" ] && bad "python runner: an appended line was reported as an edit" || ok "a runner in another language is not judged by the shell rule"

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_runner_no_errexit: all passed" || { echo "❌ test_gate_runner_no_errexit: $FAILS failed"; exit 1; }
