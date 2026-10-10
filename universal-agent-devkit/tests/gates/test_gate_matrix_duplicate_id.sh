#!/usr/bin/env bash
# Regression test (fresh-context audit 2026-10-10, GeelyEx2) for bin/post-fix-gate.py: the kit never checked suite ids. GeelyEx2 shipped two
# DIFFERENT commands under REG-OPS-11 (two rules): they share one status row (the history alternated 0.05 s / 1.53 s) and one evidence folder,
# so a pass of one hides a failure of the other. The gate still runs both. Now it warns (not blocking: a repo that has it keeps its exit code)
# once per conflicting id. One suite id under two rules with the SAME command is a shared suite, not a conflict, and stays silent.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${GATE_UNDER_TEST:-$DEVKIT_DIR/bin/post-fix-gate.py}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }

# mk <dir> <id of rule A's suite> <command of A> <id of rule B's suite> <command of B>: a repo whose matrix has two rules; sets BASE
mk() {
  mkdir -p "$1/src" "$1/tests" "$1/.agents"
  ( cd "$1" && git init -q . && git config user.email t@t && git config user.name t
    echo "x = 1" > src/a.py
    printf '#!/bin/sh\nexit 0\n' > tests/t1.sh; printf '#!/bin/sh\nexit 0\n' > tests/t2.sh
    python3 - "$2" "$3" "$4" "$5" <<'PY'
import json, sys
ida, cmda, idb, cmdb = sys.argv[1:5]
rule = lambda comp, i, c: {"component": comp, "watch_files": ["src/*", "tests/*"], "mandatory_regression_tests": [{"id": i, "name": comp, "command": c}]}
json.dump({"project": "t", "rules": [rule("A", ida, cmda), rule("B", idb, cmdb)]}, open("matrix.json", "w"))
PY
    cp matrix.json .agents/regression_matrix.active.json
    git add -A && git commit -qm init )
  BASE="$(git -C "$1" rev-parse HEAD)"
  echo "x = 2" > "$1/src/a.py"
}
gate() {   # gate <dir> → $TMP/out, $RC
  ( cd "$1" && CLAUDE_PROJECT_DIR="$1" python3 "$GATE" --matrix "$1/matrix.json" --lang en --run-tests --diff "$BASE" ) >"$TMP/out" 2>&1
  RC=$?
}

mk "$TMP/a" REG-D "sh tests/t1.sh" REG-D "sh tests/t2.sh"; gate "$TMP/a"; rca=$RC
grep -q 'REG-D.*different commands' "$TMP/out" && ok "same id, different commands: the conflict is named" || fail "no warning for a duplicate suite id: $(tail -5 "$TMP/out" | tr '\n' ' ')"
[ "$(grep -c 'REG-D.*different commands' "$TMP/out")" = 1 ] && ok "warned once for the id" || fail "warned $(grep -c 'REG-D.*different commands' "$TMP/out") times"

# the standard command is `--brief`: it keeps only ✖ lines, the failing rows and the verdict, so a plain ⚠ warning would never be seen there
( cd "$TMP/a" && CLAUDE_PROJECT_DIR="$TMP/a" python3 "$GATE" --matrix "$TMP/a/matrix.json" --lang en --run-tests --brief --diff "$BASE" ) >"$TMP/out_brief" 2>&1
grep -q 'REG-D.*different commands' "$TMP/out_brief" && ok "the conflict survives --brief" || fail "--brief hides the duplicate-id warning: $(tail -5 "$TMP/out_brief" | tr '\n' ' ')"
grep -q 'not blocking' "$TMP/out_brief" && ok "the line says it does not block" || fail "no 'not blocking' in the line"

mk "$TMP/b" REG-S "sh tests/t1.sh" REG-S "sh tests/t1.sh"; gate "$TMP/b"
grep -q 'different commands' "$TMP/out" && fail "one shared suite (same id, same command) reported as a conflict" || ok "same id, same command: a shared suite, silent"

mk "$TMP/c" REG-X "sh tests/t1.sh" REG-Y "sh tests/t2.sh"; gate "$TMP/c"; rcc=$RC
grep -q 'different commands' "$TMP/out" && fail "distinct ids reported as a conflict" || ok "distinct ids: silent"
[ "$rca" = "$rcc" ] && ok "the warning does not change the exit code ($rca)" || fail "exit code changed by the warning: conflict=$rca, clean=$rcc"

[ "$FAILS" -eq 0 ] && echo "✅ test_gate_matrix_duplicate_id: all passed" || { echo "❌ test_gate_matrix_duplicate_id: $FAILS failed"; exit 1; }
