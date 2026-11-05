#!/usr/bin/env bash
# Regression (#729, GeelyEx2#118): a matrix suite flagged "manual": true (real hardware, e.g. REG-QC-05 exits 2 always) is
#   1. skipped by an automatic gate run: reported MANUAL, not UNTESTED, exit 0
#   2. run when asked for by id (--suite REG-M)
#   3. flagging an EXISTING rule's suite in the working-copy matrix is no matrix_problem (exit 0, not 2)
#   4. a change that also alters a command is still untrusted: the gate runs the BASE command, the flag is not honoured
#   5. without the flag the suite runs as before (its failure fails the gate)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
export VACUITY_REVERT=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="${GATE_UNDER_TEST:-$DEVKIT_DIR/bin/post-fix-gate.py}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
R="$TMP/repo"
export MARK="$TMP/mark"
OUT=""; RC=0

make_repo() { # $1 = extra json fields of REG-M committed at base
  rm -rf "$R" "$MARK" && mkdir -p "$R/src" "$R/tests" "$MARK" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "x=1" > src/Core.kt
  printf 'touch "$MARK/ran_ok"\n' > tests/ok.sh
  printf 'touch "$MARK/ran_m"\nexit 2\n' > tests/m.sh
  printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-OK","name":"ok","command":"sh tests/ok.sh"},{"id":"REG-M","name":"m","command":"sh tests/m.sh"%s}]}]}\n' "$1" > matrix.json
  git add -A && git commit -qm init
  echo "x=2" > src/Core.kt
}
run_gate() { OUT="$(CLAUDE_PROJECT_DIR="$R" python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests "$@" 2>&1)"; RC=$?; }
ran() { [ -f "$MARK/ran_$1" ]; }

make_repo ',"manual":true'
run_gate
if [ "$RC" = 0 ] && ran ok && ! ran m && printf '%s\n' "$OUT" | grep -q 'MANUAL.*REG-M'; then ok "1: manual suite skipped, reported MANUAL, exit 0"
else bad "1: manual suite (exit $RC, ran_m=$(ran m && echo yes || echo no))"; printf '%s\n' "$OUT" | tail -12; fi

rm -f "$MARK"/ran_*; run_gate --suite REG-M
if ran m && [ "$RC" != 0 ]; then ok "2: --suite REG-M runs the manual suite"
else bad "2: --suite (exit $RC)"; printf '%s\n' "$OUT" | tail -12; fi

make_repo ''
sed -i.bak 's/"command":"sh tests\/m.sh"/"command":"sh tests\/m.sh","manual":true/' matrix.json && rm -f matrix.json.bak
run_gate
if [ "$RC" = 0 ] && ! ran m && ! printf '%s\n' "$OUT" | grep -qi 'modified relative\|bị sửa'; then ok "3: adding the flag to an existing suite is no matrix_problem"
else bad "3: flag edit (exit $RC)"; printf '%s\n' "$OUT" | tail -12; fi

make_repo ''
sed -i.bak 's/"command":"sh tests\/m.sh"/"command":"true","manual":true/' matrix.json && rm -f matrix.json.bak
run_gate
if [ "$RC" != 0 ] && ran m; then ok "4: flag plus a changed command is not trusted (base command ran, gate red)"
else bad "4: command edit hidden by the flag (exit $RC)"; printf '%s\n' "$OUT" | tail -12; fi

make_repo ''
run_gate
if [ "$RC" != 0 ] && ran m; then ok "5: without the flag the suite runs and fails the gate"
else bad "5: unflagged (exit $RC)"; printf '%s\n' "$OUT" | tail -12; fi

[ "$FAILS" = 0 ] && echo "PASS" || { echo "FAILED: $FAILS"; exit 1; }
