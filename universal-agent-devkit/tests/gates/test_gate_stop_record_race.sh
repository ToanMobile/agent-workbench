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
HOLDER=""   # the stub that holds test_run.lock (hold_lock): it polls up to 90 s, so an early exit must kill it, not only remove $TMP
trap '[ -n "$HOLDER" ] && kill "$HOLDER" 2>/dev/null; rm -rf "$TMP"' EXIT
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

# What can happen to the file that supplied the re-used suites (python, shared by this script and the launcher below, so each change is one thing).
# A run that finds the stamp of that file moved looks at what is on disk NOW (round 2): a file that still says PASS for the suites it re-used keeps them
# ("-same": the same bytes, another inode / ctime / mtime / size by whitespace: another run PASSED and wrote the same result), a file that does not does not.
# The plain variants therefore change the CONTENT too: REG-1 "PASS" -> "FAIL", the same length, so that rewrite and rename still keep size and mtime_ns and
# only the stamp's inode and ctime can tell (what this test pinned before: each part of the stamp is a mutant that must go red).
#   remove  gone (a forced run's FAIL drops it)            grow    one byte longer, mtime put back (size differs)
#   touch   mtime 5 s later                                  rewrite written in place, mtime put back (only ctime differs)
#   rename  written to a new file moved over it, mtime put back (new inode; size and mtime_ns the same)
cat > "$TMP/change.py" <<'PY'
import os, sys

def apply(how, p):
    if how == "none" or not os.path.exists(p):
        return
    same = how.endswith("-same")
    how = how[:-5] if same else how
    st = os.stat(p)
    data = open(p, "rb").read()
    if not same:
        data = data.replace(b'"status": "PASS"', b'"status": "FAIL"', 1)   # the first suite of the file is REG-1; same length
    if how == "remove":
        os.remove(p)
    elif how == "grow":
        with open(p, "wb") as f:
            f.write(data + b" ")
        os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns))
    elif how == "touch":
        with open(p, "r+b") as f:
            f.write(data)
        os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns + 5_000_000_000))
    elif how == "rewrite":
        with open(p, "r+b") as f:
            f.write(data)
        os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns))
    elif how == "rename":
        tmp = p + ".moved"
        with open(tmp, "wb") as f:
            f.write(data)
        os.utime(tmp, ns=(st.st_atime_ns, st.st_mtime_ns))
        os.replace(tmp, p)

if __name__ == "__main__":
    apply(sys.argv[1], sys.argv[2])
PY
# A launcher around the gate's own main(): the FIRST local_state_sha call, which cached_full_pass makes AFTER it has read the file and before it
# returns (the 0.7-6.4 s window), changes the supplying file. A stamp taken after the read cannot see that change.
cat > "$TMP/launcher_read.py" <<'PY'
import importlib.util, os, sys
gate = sys.argv[1]
sys.argv = [gate] + sys.argv[2:]
sys.path.insert(0, os.environ["RACE_DIR"])
import change
spec = importlib.util.spec_from_file_location("pfg_race", gate)
m = importlib.util.module_from_spec(spec)
sys.modules["pfg_race"] = m
spec.loader.exec_module(m)
real, fired = m.local_state_sha, []
def hooked(d):
    if not fired:
        fired.append(1)
        change.apply(os.environ["RACE_HOW"], os.environ["RACE_FILE"])
    return real(d)
m.local_state_sha = hooked
sys.exit(m.main())
PY
src_file() { if [ "$1" = receipt ]; then echo "$GD/full_pass.json"; else echo "$GD/budget_pass.json"; fi; }
src_tests() { python3 -I -c 'import json,sys
try:
    d = json.load(open(sys.argv[1])); print(",".join("%s=%s" % (t["id"], t["status"]) for t in d["tests"]), "untested=" + ",".join(d.get("untested") or []))
except OSError: print("none")' "$1"; }

# race <source of the re-used suites: record | receipt> <when it changes: lock = while A waits for the lock, read = while A is still reading it> <how: none | remove | ...>
race() {
  make_repo
  if [ "$1" = receipt ]; then run_gate EXIT2=2 -- --full; else run_gate EXIT2=2; fi
  SEED_RC=$RC; SEED_REC="$(src_tests "$(src_file "$1")")"
  rm -f "$TMP/a.out" "$TMP/a.rc"
  if [ "$2" = lock ]; then
    hold_lock "$TMP/lock.release"
    ( CLAUDE_PROJECT_DIR="$R" env GATE_TOTAL_BUDGET_S=900 EXIT2=0 python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests > "$TMP/a.out" 2>&1; echo $? > "$TMP/a.rc" ) &
    local apid=$! i=0
    while ! grep -q "waiting for it" "$TMP/a.out" 2>/dev/null && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
    A_WAIT=no; grep -q "waiting for it" "$TMP/a.out" 2>/dev/null && A_WAIT=yes
    python3 -I "$TMP/change.py" "$3" "$(src_file "$1")"
    touch "$TMP/lock.release"; wait "$HOLDER" 2>/dev/null; HOLDER=""; wait "$apid" 2>/dev/null
  else
    A_WAIT=yes   # no lock is involved: the change happens inside A's own read
    CLAUDE_PROJECT_DIR="$R" env GATE_TOTAL_BUDGET_S=900 EXIT2=0 RACE_DIR="$TMP" RACE_HOW="$3" RACE_FILE="$(src_file "$1")" \
      python3 "$TMP/launcher_read.py" "$GATE" --matrix "$R/matrix.json" --lang en --run-tests > "$TMP/a.out" 2>&1; echo $? > "$TMP/a.rc"
  fi
  A_RC="$(cat "$TMP/a.rc" 2>/dev/null)"
  A_REUSED=no; grep -q "reusing the" "$TMP/a.out" 2>/dev/null && A_REUSED=yes
  local before; before="$(runs s1)"
  if [ "$3" = none ]; then run_gate EXIT2=0; else run_gate EXIT2=0 FAIL1=1; fi
  C_RC="$RC"; C_S1=$(( $(runs s1) - before ))
}

# check <label> <source> <trigger> <how>: A re-used REG-1, the supplying file changed, A must not write it back, C must run REG-1 and see it fail
check() {
  race "$2" "$3" "$4"
  if [ "$SEED_RC" = 2 ] && [ "$SEED_REC" = "REG-1=PASS,REG-2=UNTESTED untested=REG-2" ] && [ "$A_WAIT" = yes ] && [ "$A_REUSED" = yes ] && [ "$A_RC" = 2 ]; then
    ok "$1: the seed ($2) held REG-1 PASS; A re-used it and ended exit 2 (REG-2 ran and passed)"
  else
    bad "$1: setup went wrong: seed rc=$SEED_RC $2='$SEED_REC' A waited=$A_WAIT re-used=$A_REUSED A rc=$A_RC"; printf '%s\n' "$(tail -5 "$TMP/a.out" 2>/dev/null)"
  fi
  if [ "$C_S1" = 1 ] && [ "$C_RC" = 1 ]; then
    ok "$1: the $2 changed ($4, $3): A wrote no re-used PASS back, so C RAN REG-1 and saw it fail (exit 1)"
  else
    bad "$1: REG-1 ran $C_S1 times in C, exit $C_RC (want 1 and 1: a PASS that a concurrent run just replaced was written back)"; printf 'record: %s\n' "$(src_tests "$GD/budget_pass.json")"
  fi
}
# stands <label> <source> <trigger> <how>-same: another run PASSED and wrote the same result (another inode / ctime / mtime / size): the file still says PASS for
# REG-1, so A keeps it (no false STALE: exit 2 as before) and its record keeps REG-1 PASS, which C re-uses (0 runs, exit 2)
stands() {
  race "$2" "$3" "$4"
  if [ "$SEED_RC" = 2 ] && [ "$SEED_REC" = "REG-1=PASS,REG-2=UNTESTED untested=REG-2" ] && [ "$A_WAIT" = yes ] && [ "$A_REUSED" = yes ] && [ "$A_RC" = 2 ] && [ "$C_S1" = 0 ] && [ "$C_RC" = 2 ]; then
    ok "$1: the $2 was replaced by the same result ($4, $3): A kept its PASS (exit 2), its record kept REG-1 PASS and C re-used it (0 runs, exit 2)"
  else
    bad "$1: seed rc=$SEED_RC '$SEED_REC' A waited=$A_WAIT re-used=$A_REUSED rc=$A_RC; C ran REG-1 $C_S1 times, exit $C_RC (want rc 2, 0 runs, exit 2)"; printf 'record: %s\n' "$(src_tests "$GD/budget_pass.json")"
  fi
}
# the control of each shape: the same flow, nothing changes the file: A's record stands and C re-uses everything
control() {
  race "$2" "$3" none
  if [ "$A_RC" = 2 ] && [ "$A_WAIT" = yes ] && [ "$A_REUSED" = yes ] && [ "$C_S1" = 0 ] && [ "$C_RC" = 2 ]; then
    ok "$1: nothing touched the $2 ($3): A's record stands and C re-used everything (0 runs of REG-1, exit 2)"
  else
    bad "$1: A rc=$A_RC waited=$A_WAIT re-used=$A_REUSED; C ran REG-1 $C_S1 times, exit $C_RC (want 0 runs, exit 2)"; printf 'record: %s\n' "$(src_tests "$GD/budget_pass.json")"
  fi
}

# F1: the file changes while A waits for the lock. The stamp holds (mtime_ns, size, inode, ctime_ns): rewrite keeps size, mtime and inode (only ctime moves),
# rename keeps size and mtime_ns (inode and ctime move), grow moves size, touch moves mtime.
for how in remove grow touch rewrite rename; do check "F1/record/$how" record lock "$how"; done
for how in grow-same touch-same rewrite-same rename-same; do stands "F1/record/$how" record lock "$how"; done
control "F1/record/control" record lock
# the receipt is the other source of re-used suites, with the same race
# (only remove: a receipt that is merely touched is still a valid PASS of an earlier --full run, and C re-uses it by design)
check "F1/receipt/remove" receipt lock remove
control "F1/receipt/control" receipt lock
# n5: the file changes DURING A's read of it (after it was loaded, before the read returns). The stamp has to be taken before the read.
for src in record receipt; do
  check "F1/$src/read-remove" "$src" read remove
  control "F1/$src/read-control" "$src" read
done
# the same change by rename while A reads: only the record (a renamed receipt with the same bytes is still a valid PASS, and C re-uses it by design)
check "F1/record/read-rename" record read rename
stands "F1/record/read-rename-same" record read rename-same

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
