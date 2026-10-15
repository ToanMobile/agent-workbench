#!/usr/bin/env bash
# Regression test (review of the Stop record, 2026-10-15): a Stop-style run that RE-USED suites from budget_pass.json before it waited for
# test_run.lock wrote those re-used PASSes back after the wait, so a forced run that FAILED the same suite meanwhile (and dropped the record) was
# overwritten back to PASS: the next Stop-style run then skipped a suite that fails. Sequence (the reviewer's probe, made deterministic: the lock is
# held by a stub that lets go when told, nothing depends on timing). An unwatched changed source file (lib/Other.kt) keeps every verdict at exit 2:
#   seed   Stop-style run: REG-1 PASS goes into the record, REG-2 exits with its untested_exit
#   hold   a stub takes test_run.lock (it stands for the forced run B that is still running)
#   A      a Stop-style run: it re-uses REG-1 from the record, then waits for the lock (REG-2 still has to run, and now passes)
#   B      while A waits, the record changes: B's FAIL of REG-1 drops it (file gone), or it is replaced by another run's (size changed with the time
#          kept, or time changed with the size kept: the stamp is both)
#   A      gets the lock, runs REG-2 and must NOT write REG-1 back as PASS (what it re-used no longer stands on the file that vouched for it)
#   C      a Stop-style run with REG-1 failing again: REG-1 must RUN and the run must be exit 1 (before: REG-1 ran 0 times, exit 2)
# Controls with the same shape: nothing touches the record while A waits -> A's record is written and C re-uses everything (0 runs, exit 2).
# And a run that took no lock and started no suite writes nothing (the record file is not even rewritten).
# bash 3.2 and Python 3.9 compatible; STOPRACE_KIT=<kit dir> tests another copy of the kit (a mutant must go red).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S DEVKIT_UNITY_REUSE_MAX_S GATE_TOTAL_BUDGET_S TEST_RUN_LOCK_WAIT_S DEVKIT_IMPACTED_SINCE
export VACUITY_REVERT=0 FLAKY_RETRY=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${STOPRACE_KIT:-$DEVKIT_DIR}"
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
suite() { printf '{"id":"%s","name":"%s","command":"%s"%s}' "$1" "$1" "$2" "${3:-}"; }
make_repo() { # REG-1 passes (and counts), REG-2 exits with its untested_exit unless EXIT2 says otherwise
  rm -rf "$R" "$MARK" && mkdir -p "$R/app/src/main/kotlin/pkg" "$R/tests" "$MARK" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  printf 'package pkg\n\nclass Lonely {\n    fun value() = 4\n}\n' > app/src/main/kotlin/pkg/Lonely.kt
  printf 'echo x >> "$MARK/s1"\nexit "${FAIL1:-0}"\n' > tests/s1.sh
  printf 'echo x >> "$MARK/s2"\nexit "${EXIT2:-0}"\n' > tests/s2.sh
  printf '{"project":"t","rules":[{"component":"App","watch_files":["app/*"],"mandatory_regression_tests":[%s,%s]}]}\n' \
    "$(suite REG-1 'sh tests/s1.sh')" "$(suite REG-2 'sh tests/s2.sh' ',"untested_exit":2')" > matrix.json
  git add -A && git commit -qm init
  echo "// tweak" >> app/src/main/kotlin/pkg/Lonely.kt
  mkdir -p lib && echo "class Other" > lib/Other.kt   # a changed source file no rule watches: the verdict is exit 2 (UNVERIFIED), whatever the suites say
  GD="$(git -C "$R" rev-parse --absolute-git-dir)/postfix-gate"
}
run_gate() { # NAME=value words, then optional flags after "--"
  local envs=() flags=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  flags=("$@")
  OUT="$(CLAUDE_PROJECT_DIR="$R" env GATE_TOTAL_BUDGET_S=900 ${envs[@]+"${envs[@]}"} python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests ${flags[@]+"${flags[@]}"} 2>&1)"; RC=$?
}
runs() { if [ -f "$MARK/$1" ]; then wc -l < "$MARK/$1" | tr -d ' '; else echo 0; fi; }
stamp() { python3 -I -c 'import os,sys
try:
    st = os.stat(sys.argv[1]); print(st.st_ino, st.st_mtime_ns, st.st_size)
except OSError: print("none")' "$1"; }
rec_tests() { python3 -I -c 'import json,sys
try:
    d = json.load(open(sys.argv[1])); print(",".join("%s=%s" % (t["id"], t["status"]) for t in d["tests"]), "untested=" + ",".join(d.get("untested") or []))
except OSError: print("none")' "$GD/budget_pass.json"; }

# A stub that holds test_run.lock until told to let go; it stands for the forced run that is still running
hold_lock() { # $1 = release file
  rm -f "$TMP/lock.held" "$1"
  python3 -I - "$R" "$TMP/lock.held" "$1" <<'PY' &
import fcntl, os, sys, time
d = sys.argv[1] + "/.claude/audit-gate"
os.makedirs(d, exist_ok=True)
with open(d + "/test_run.lock", "a") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    open(sys.argv[2], "w").close()
    for _ in range(900):
        if os.path.exists(sys.argv[3]):
            break
        time.sleep(0.1)
PY
  HOLDER=$!
  local i=0; while [ ! -f "$TMP/lock.held" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
}

# race <what happens to the record while A waits: none | remove | grow | touch>
race() {
  make_repo
  run_gate EXIT2=2; local seed_rc=$RC; local seed_rec; seed_rec="$(rec_tests)"
  hold_lock "$TMP/lock.release"
  rm -f "$TMP/a.out" "$TMP/a.rc"
  ( CLAUDE_PROJECT_DIR="$R" env GATE_TOTAL_BUDGET_S=900 EXIT2=0 python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests > "$TMP/a.out" 2>&1; echo $? > "$TMP/a.rc" ) &
  local apid=$! i=0
  while ! grep -q "waiting for it" "$TMP/a.out" 2>/dev/null && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
  local waiting=no; grep -q "waiting for it" "$TMP/a.out" 2>/dev/null && waiting=yes
  local reused=no; grep -q "reusing the suites that passed" "$TMP/a.out" 2>/dev/null && reused=yes
  case "$1" in
    remove) rm -f "$GD/budget_pass.json" ;;
    grow)   python3 -I -c 'import os,sys
p = sys.argv[1]; st = os.stat(p)
with open(p, "a") as f: f.write(" ")
os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns))' "$GD/budget_pass.json" ;;
    touch)  python3 -I -c 'import os,sys
p = sys.argv[1]; st = os.stat(p)
os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns + 5_000_000_000))' "$GD/budget_pass.json" ;;
  esac
  touch "$TMP/lock.release"; wait "$HOLDER" 2>/dev/null; wait "$apid" 2>/dev/null
  A_RC="$(cat "$TMP/a.rc" 2>/dev/null)"; A_WAIT="$waiting"; A_REUSED="$reused"; SEED_RC="$seed_rc"; SEED_REC="$seed_rec"
  local before; before="$(runs s1)"
  if [ "$1" = none ]; then run_gate EXIT2=0; else run_gate EXIT2=0 FAIL1=1; fi
  C_RC="$RC"; C_S1=$(( $(runs s1) - before ))
}

for how in remove grow touch; do
  race "$how"
  if [ "$SEED_RC" = 2 ] && [ "$SEED_REC" = "REG-1=PASS,REG-2=UNTESTED untested=REG-2" ] && [ "$A_WAIT" = yes ] && [ "$A_REUSED" = yes ] && [ "$A_RC" = 2 ]; then
    ok "F1/$how: the seed recorded REG-1 PASS; A re-used it, waited for the lock and ended exit 2 (REG-2 ran and passed)"
  else
    bad "F1/$how: setup went wrong: seed rc=$SEED_RC record='$SEED_REC' A waited=$A_WAIT re-used=$A_REUSED A rc=$A_RC"; printf '%s\n' "$(tail -5 "$TMP/a.out" 2>/dev/null)"
  fi
  if [ "$C_S1" = 1 ] && [ "$C_RC" = 1 ]; then
    ok "F1/$how: the record changed while A waited: A wrote no re-used PASS back, so C RAN REG-1 and saw it fail (exit 1)"
  else
    bad "F1/$how: REG-1 ran $C_S1 times in C, exit $C_RC (want 1 and 1: a PASS that a concurrent run just replaced was written back)"; printf 'record: %s\n' "$(rec_tests)"
  fi
done

# the control with the same shape: nobody touches the record while A waits
race none
if [ "$A_RC" = 2 ] && [ "$A_WAIT" = yes ] && [ "$A_REUSED" = yes ] && [ "$C_S1" = 0 ] && [ "$C_RC" = 2 ]; then
  ok "F1/control: nothing touched the record while A waited: A's record stands and C re-used everything (0 runs of REG-1, exit 2)"
else
  bad "F1/control: A rc=$A_RC waited=$A_WAIT re-used=$A_REUSED; C ran REG-1 $C_S1 times, exit $C_RC (want 0 runs, exit 2)"; printf 'record: %s\n' "$(rec_tests)"
fi

# a run that took no lock and started no suite writes nothing: not even the same record again. An unwatched changed source file makes the
# verdict exit 2 (UNVERIFIED) with every suite PASS, so run 2 re-uses both suites and has nothing left to run.
make_repo
mkdir -p "$R/lib" && echo "class Other" > "$R/lib/Other.kt"
run_gate EXIT2=0; rc0=$RC; s1="$(stamp "$GD/budget_pass.json")"; n1="$(runs s1)"
run_gate EXIT2=0; rc2=$RC; s2="$(stamp "$GD/budget_pass.json")"; n2="$(runs s1)"
if [ "$rc0" = 2 ] && [ "$rc2" = 2 ] && [ "$n1" = 1 ] && [ "$n2" = 1 ] && [ "$s1" != none ] && [ "$s1" = "$s2" ]; then
  ok "F1/no-run: run 2 re-used every suite, started none and left the record file untouched ($s2)"
else
  bad "F1/no-run: exit $rc0/$rc2, REG-1 runs $n1 -> $n2, record $s1 -> $s2 (want exit 2 twice, 1 run in all, the same file)"
fi
echo "// one more edit" >> "$R/app/src/main/kotlin/pkg/Lonely.kt"
run_gate EXIT2=0; s3="$(stamp "$GD/budget_pass.json")"
[ "$s3" != "$s2" ] && ok "F1/no-run control: a run that did start suites writes the record" || bad "F1/no-run control: the record was not rewritten by a run that ran suites"

echo
[ "$FAILS" -eq 0 ] && echo "gate stop record race: all checks passed" || { echo "gate stop record race: $FAILS FAILED"; exit 1; }
