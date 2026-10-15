#!/usr/bin/env bash
# Regression test (review of the Stop record, 2026-10-15): the record trusted a suite of mode "full" by its id and the content alone, but what such
# a suite RUNS can depend on inputs outside that key. The kit's own suite REG-DK-ALL-01 is tests/run_impacted.sh: it has no impacted_command, so it is
# recorded as a full PASS, yet which tests it starts depends on DEVKIT_IMPACTED_SINCE (0 = a RED-proof sandbox: no commit counts as a change), on
# the upstream and on the last hours of commits. A run with the narrow selection recorded a PASS that a session with the default window then trusted
# although it should have run more tests. And suites were matched by id only: another --diff or --matrix with a byte-equal matrix file reused the
# PASS of another command.
# Now the record names the selection-affecting environment (DEVKIT_IMPACTED_SINCE) and the matrix command each suite PASSED under (`full_command`),
# both compared on read; a record without either field is not read (fail closed).
#   I1 DEVKIT_IMPACTED_SINCE=0 then unset (and the other way round, and two different windows): every suite runs again; the same value twice: re-used
#   I2 a record whose suite names another command, or no command, or no `env`: nothing is re-used; the untouched record is (control)
# An unwatched changed source file (lib/Other.kt) keeps the verdict at exit 2 with every suite PASS, which is what writes the record.
# bash 3.2 and Python 3.9 compatible; STOPIN_KIT=<kit dir> tests another copy of the kit (a mutant must go red).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_UNITY_REUSE_MAX_S GATE_TOTAL_BUDGET_S DEVKIT_IMPACTED_SINCE
export VACUITY_REVERT=0 FLAKY_RETRY=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${STOPIN_KIT:-$DEVKIT_DIR}"
GATE="$KIT/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"
export MARK="$TMP/mark"
OUT=""; RC=0
suite() { printf '{"id":"%s","name":"%s","command":"%s"}' "$1" "$1" "$2"; }
make_repo() {
  rm -rf "$R" "$MARK" && mkdir -p "$R/app/src/main/kotlin/pkg" "$R/tests" "$R/lib" "$MARK" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  printf 'package pkg\n\nclass Lonely {\n    fun value() = 4\n}\n' > app/src/main/kotlin/pkg/Lonely.kt
  printf 'echo x >> "$MARK/s1"\nexit 0\n' > tests/s1.sh
  printf 'echo x >> "$MARK/s2"\nexit 0\n' > tests/s2.sh
  printf '{"project":"t","rules":[{"component":"App","watch_files":["app/*"],"mandatory_regression_tests":[%s,%s]}]}\n' \
    "$(suite REG-1 'sh tests/s1.sh')" "$(suite REG-2 'sh tests/s2.sh')" > matrix.json
  git add -A && git commit -qm init
  echo "// tweak" >> app/src/main/kotlin/pkg/Lonely.kt
  echo "class Other" > lib/Other.kt   # no rule watches it: exit 2 (UNVERIFIED), every suite PASS
  GD="$(git -C "$R" rev-parse --absolute-git-dir)/postfix-gate"
}
run_gate() { # NAME=value words
  OUT="$(CLAUDE_PROJECT_DIR="$R" env GATE_TOTAL_BUDGET_S=900 "$@" python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests 2>&1)"; RC=$?
}
runs() { if [ -f "$MARK/$1" ]; then wc -l < "$MARK/$1" | tr -d ' '; else echo 0; fi; }
LAST="0:0"; D=""
delta() { local now; now="$(runs s1):$(runs s2)"
  D="$(python3 -I -c 'import sys; a=[int(x) for x in sys.argv[1].split(":")]; b=[int(x) for x in sys.argv[2].split(":")]; print(":".join(str(x-y) for x,y in zip(a,b)))' "$now" "$LAST")"
  LAST="$now"; }
fresh() { make_repo; LAST="0:0"; }
tamper() { # python expression body acting on the record dict `d`
  python3 -I -c 'import json,sys
p = sys.argv[1]; d = json.load(open(p))
exec(sys.argv[2])
json.dump(d, open(p, "w"))' "$GD/budget_pass.json" "$1"
}

# I1 the selection environment
fresh; run_gate DEVKIT_IMPACTED_SINCE=0; delta; d1="$D"; rc1=$RC
run_gate; delta; d2="$D"
[ "$rc1" = 2 ] && [ "$d1" = "1:1" ] && ok "I1 setup: run 1 (DEVKIT_IMPACTED_SINCE=0) ran both suites, exit 2 (runs $d1)" || { bad "I1 setup: exit $rc1 runs $d1"; printf '%s\n' "$OUT" | tail -5; }
[ "$d2" = "1:1" ] && ok "I1a: the narrow selection (=0) then the default: both suites run again (runs $d2)" || bad "I1a: runs $d2 (want 1:1: a PASS taken under another selection was trusted)"
run_gate; delta; d="$D"
[ "$d" = "0:0" ] && ok "I1a control: the default again, the same selection as run 2: re-used (runs $d)" || bad "I1a control: runs $d (want 0:0)"
run_gate DEVKIT_IMPACTED_SINCE=0; delta; d="$D"
[ "$d" = "1:1" ] && ok "I1b: the default then the narrow selection: both suites run again (runs $d)" || bad "I1b: runs $d (want 1:1)"
run_gate DEVKIT_IMPACTED_SINCE=0; delta; d="$D"
[ "$d" = "0:0" ] && ok "I1b control: =0 twice: re-used (runs $d)" || bad "I1b control: runs $d (want 0:0)"
run_gate DEVKIT_IMPACTED_SINCE=2.hours; delta; d="$D"
[ "$d" = "1:1" ] && ok "I1c: another window (2.hours): both suites run again (runs $d)" || bad "I1c: runs $d (want 1:1)"
run_gate DEVKIT_IMPACTED_SINCE=2.hours; delta; d="$D"
[ "$d" = "0:0" ] && ok "I1c control: the same window twice: re-used (runs $d)" || bad "I1c control: runs $d (want 0:0)"

# I2 the command each suite passed under, and records that lack the new fields
fresh; run_gate; delta
tamper 'd["tests"][0]["full_command"] = "sh tests/other.sh"'
run_gate; delta; d="$D"
[ "$d" = "1:1" ] && ok "I2a: the record says REG-1 passed another command: nothing is re-used, both suites run (runs $d)" || bad "I2a: runs $d (want 1:1: matched by id only)"
run_gate; delta; d="$D"
[ "$d" = "0:0" ] && ok "I2a control: the record that run wrote (the right commands) is re-used (runs $d)" || bad "I2a control: runs $d (want 0:0)"
tamper 'del d["tests"][0]["full_command"]'
run_gate; delta; d="$D"
[ "$d" = "1:1" ] && ok "I2b: a record whose suite names no command is not read (runs $d)" || bad "I2b: runs $d (want 1:1)"
run_gate; delta
tamper 'del d["env"]'
run_gate; delta; d="$D"
[ "$d" = "1:1" ] && ok "I2c: a record without the selection environment (an older record) is not read (runs $d)" || bad "I2c: runs $d (want 1:1)"
run_gate; delta; d="$D"
[ "$d" = "0:0" ] && ok "I2c control: the record written after it is read again (runs $d)" || bad "I2c control: runs $d (want 0:0)"

echo
[ "$FAILS" -eq 0 ] && echo "gate stop record inputs: all checks passed" || { echo "gate stop record inputs: $FAILS FAILED"; exit 1; }
