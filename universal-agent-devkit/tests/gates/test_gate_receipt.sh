#!/usr/bin/env bash
# Regression test: bin/post-fix-gate.py writes the full-pass receipt (bin/tree_fp.py,
# .git/postfix-gate/full_pass.json — what hooks/proof_gate.sh and the O1 reuse trust) only for a
# real full run of the code that is in the tree, and bin/regression_checklist.py records a PASS
# row only for a suite that ran its full command. Audit 2026-09-28:
#   - a run without --full (RESOURCE: nothing ran; PACKAGE: a subset) wrote the receipt and
#     recorded the row PASS — a later --full reused that subset as a full PASS;
#   - the fingerprint was taken after the suites, so code changed during the run was stamped
#     as tested.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
export VACUITY_REVERT=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
# BEFORE the trap: an empty $TMP (mktemp failed) would make its `pkill -f -- "$TMP/"` a `pkill -f -- /`, SIGTERM for nearly every process
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
# The background runs further down (pa, pb, pz) are started with SIGINT ignored (bash does that for every `&` job): after a ^C they ran on for
# minutes with their folder gone (hold.py alarm 300 s, a gate run). Their command lines hold $TMP/, so they are found by it.
trap 'pkill -f -- "$TMP/" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

make_repo() { # $1 = impacted_command, $2 = full command
  rm -rf "$TMP/repo" && mkdir -p "$TMP/repo/app/src/main/kotlin/pkg" "$TMP/repo/app/src/test/kotlin/pkg"
  cd "$TMP/repo" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  printf 'include(":app")\n' > settings.gradle.kts
  printf 'plugins { id("com.example.app") }\n' > app/build.gradle.kts
  printf 'package pkg\n\nclass Lonely {\n    fun value() = 4\n}\n' > app/src/main/kotlin/pkg/Lonely.kt
  printf 'package pkg\n\nimport org.junit.Test\n\nclass OtherTest {\n    @Test fun works() { }\n}\n' > app/src/test/kotlin/pkg/OtherTest.kt
  printf '#!/bin/sh\nexit 0\n' > gradlew && chmod +x gradlew
  cat > matrix.json <<JSON
{"project":"t","rules":[{"component":"App","watch_files":["app/*"],
 "mandatory_regression_tests":[{"id":"REG-APP","name":"app unit tests","command":"$2","impacted_command":"$1"}]}]}
JSON
  git add -A && git commit -qm init
}
run_gate() { CLAUDE_PROJECT_DIR="$TMP/repo" python3 "$GATE" --matrix "$TMP/repo/matrix.json" --lang en "$@" 2>&1; }
receipt() { [ -f "$(git rev-parse --absolute-git-dir)/postfix-gate/full_pass.json" ]; }
row() { python3 -c 'import json; print((json.load(open(".agents/regression_status.json"))["items"]["REG-APP"].get("last") or {}).get("status"))' 2>/dev/null; }

MOD='./gradlew {gradle_module_tests:testDebugUnitTest}'
FULL='./gradlew :app:testDebugUnitTest'

make_repo "$MOD" "$FULL"
mkdir -p app/src/main/res/values && printf '<resources></resources>\n' > app/src/main/res/values/strings.xml
out="$(run_gate --run-tests)"; rc=$?
printf '%s' "$out" | grep -q "mode RESOURCE" && [ "$rc" = 0 ] && ok "setup: resource XML runs in RESOURCE mode" || bad "setup resource: exit $rc"
receipt && bad "a RESOURCE run (nothing ran) wrote the full-pass receipt" || ok "a RESOURCE run writes no full-pass receipt"
[ "$(row)" != PASS ] && ok "a RESOURCE run records no PASS row ($(row))" || bad "a RESOURCE run recorded the row PASS"

make_repo "$MOD" "$FULL"
echo "// tweak" >> app/src/main/kotlin/pkg/Lonely.kt
out="$(run_gate --run-tests)"; rc=$?
printf '%s' "$out" | grep -q "mode PACKAGE" && [ "$rc" = 0 ] && ok "setup: an unnamed class runs in PACKAGE mode" || bad "setup package: exit $rc"
receipt && bad "a PACKAGE run (a subset) wrote the full-pass receipt" || ok "a PACKAGE run writes no full-pass receipt"
[ "$(row)" != PASS ] && ok "a PACKAGE run records no PASS row ($(row))" || bad "a PACKAGE run recorded the row PASS"

make_repo "$MOD" "$FULL"
echo "// tweak" >> app/src/main/kotlin/pkg/Lonely.kt
out="$(run_gate --run-tests --full)"; rc=$?
[ "$rc" = 0 ] && receipt && ok "control: a --full PASS writes the receipt" || bad "control: --full exit $rc, receipt $(receipt && echo yes || echo no)"

make_repo "$MOD" "./gradlew :app:testDebugUnitTest && echo '// edited mid-run' >> app/src/main/kotlin/pkg/Lonely.kt"
echo "// tweak" >> app/src/main/kotlin/pkg/Lonely.kt
out="$(run_gate --run-tests --full)"; rc=$?
receipt && bad "code changed during the run was stamped as tested (receipt written, exit $rc)" \
  || ok "code changed during the run: no full-pass receipt (exit $rc)"

# A --full that WAITED for the test-run lock of another run of the same content re-uses the
# PASS that run just recorded instead of running the suites again (audit 2026-09-29: two
# sessions / a background gate + a foreground gate on one checkout paid every suite twice).
# No fixed time window (a `sleep 4` in the fake suite made the check depend on how long the second run took to start, and ~10 tests run
# beside this one): run A's fake suite stays inside the lock until GO exists, which the test creates once B has said it is WAITING for
# the lock. Every wait is bounded (45-70 s, so a broken lock fails the check in a couple of minutes, not at the outer timeout): a run that
# never comes is a failed check, not a hang.
GO="$TMP/go"
wait_suite_started() { i=0; while [ ! -s .runs ] && [ $i -lt 600 ]; do sleep 0.1; i=$((i + 1)); done; }   # A holds the test-run lock and has taken its fingerprint once its suite started
wait_for() { i=0; while ! grep -q -- "$2" "$1" 2>/dev/null && { [ -z "${3:-}" ] || kill -0 "$3" 2>/dev/null; } && [ $i -lt 450 ]; do sleep 0.1; i=$((i + 1)); done; }   # <file> <text> [pid: stop when it has ended]
held_gradlew() { printf '#!/bin/sh\necho run >> .runs\ni=0; while [ ! -e "%s" ] && [ -d "%s" ] && [ $i -lt 700 ]; do sleep 0.1; i=$((i + 1)); done\nexit 0\n' "$GO" "$TMP" > gradlew && git commit -qam slow-gradlew; }
# The gate closes its test-run lock a moment BEFORE it writes the receipt (a gap of ~0.1 s, far more under load), and a waiting run polls the
# lock every 0.5 s: one that wins the lock inside the gap sees no receipt and runs the suites again, a cost only, and the thing this check
# is not about (it flaked on that alone, ~1 run in 4). hold.py stands in the gap: it waits for the lock beside B, takes it the moment A
# lets go and keeps it until A's receipt exists, so B can only get the lock after the receipt (30 s at most, then it lets go regardless). An
# optional 4th argument is a file it also waits for (the control run below edits the tree in that window).
cat > "$TMP/hold.py" <<'PY'
import fcntl, os, signal, sys, time
lock, rcpt, ready = sys.argv[1:4]
extra = sys.argv[4] if len(sys.argv) > 4 else ""
signal.alarm(150)
def stamp():
    try:
        st = os.stat(rcpt)
        return (st.st_mtime_ns, st.st_size)
    except OSError:
        return None
before = stamp()
end = time.time() + 45
while not os.path.exists(lock) and time.time() < end:
    time.sleep(0.02)
fh = open(lock, "a")
with open(ready, "w") as f:
    f.write("ready")
fcntl.flock(fh, fcntl.LOCK_EX)          # blocks while A holds it, wakes the moment A lets go
end = time.time() + 30
while stamp() == before and time.time() < end:
    time.sleep(0.01)
end = time.time() + 30
while extra and not os.path.exists(extra) and time.time() < end:
    time.sleep(0.01)
PY
rm -f "$GO" "$TMP/zready"
make_repo "$MOD" "./gradlew :app:testDebugUnitTest"
held_gradlew
printf '.runs\n' >> .git/info/exclude
echo "// tweak" >> app/src/main/kotlin/pkg/Lonely.kt
run_gate --run-tests --full > "$TMP/a.out" & pa=$!
wait_suite_started
python3 -I "$TMP/hold.py" "$(pwd)/.claude/audit-gate/test_run.lock" "$(git rev-parse --absolute-git-dir)/postfix-gate/full_pass.json" "$TMP/zready" & pz=$!
wait_for "$TMP/zready" ready
TEST_RUN_LOCK_WAIT_S=90 run_gate --run-tests --full > "$TMP/b.out" & pb=$!
wait_for "$TMP/b.out" "waiting for it" "$pb"      # B is in the queue for the lock: now A may finish
: > "$GO"
wait "$pb"; rb=$?
wait "$pa"; ra=$?
wait "$pz"
runs="$(wc -l < .runs | tr -d ' ')"
[ "$ra$rb" = 00 ] && [ "$runs" = 1 ] && receipt \
  && ok "a --full that waited for the lock re-uses the PASS of the same content (suite ran once)" \
  || bad "the waiting --full ran the suite again (exits $ra$rb, suite runs $runs)"
# The control: the receipt A leaves is for OTHER content than the tree B finds once it has the lock. (Editing the tree while A runs, as this
# check did, makes A write NO receipt at all, so B ran for that reason and never reached the re-use test.) So A runs to the end and writes its
# receipt; hold.py keeps the lock until the test has edited the tree AFTER that receipt: B then wakes to a receipt that does not match.
rm -f "$GO" "$TMP/zready2" "$TMP/edited2"
make_repo "$MOD" "./gradlew :app:testDebugUnitTest"
held_gradlew
printf '.runs\n' >> .git/info/exclude
echo "// tweak" >> app/src/main/kotlin/pkg/Lonely.kt
run_gate --run-tests --full > "$TMP/a.out" & pa=$!
wait_suite_started
python3 -I "$TMP/hold.py" "$(pwd)/.claude/audit-gate/test_run.lock" "$(git rev-parse --absolute-git-dir)/postfix-gate/full_pass.json" "$TMP/zready2" "$TMP/edited2" & pz=$!
wait_for "$TMP/zready2" ready
TEST_RUN_LOCK_WAIT_S=90 run_gate --run-tests --full > "$TMP/b.out" & pb=$!
wait_for "$TMP/b.out" "waiting for it" "$pb"
: > "$GO"
i=0; while ! receipt && [ $i -lt 450 ]; do sleep 0.1; i=$((i + 1)); done   # A's PASS of the old content is on disk
had_receipt=0; receipt && had_receipt=1
echo "// edited after A's receipt" >> app/src/main/kotlin/pkg/Lonely.kt
: > "$TMP/edited2"                                       # hold.py lets go: B gets the lock and finds a receipt of other content
wait "$pb"; rb=$?
wait "$pa"; ra=$?
wait "$pz"
runs="$(wc -l < .runs | tr -d ' ')"
[ "$had_receipt" = 1 ] && [ "$ra$rb" = 00 ] && [ "$runs" = 2 ] \
  && ok "control: other content after the wait still runs its suites (runs $runs)" \
  || bad "control: waiting run on other content did not run its suites (exits $ra$rb, runs $runs, A's receipt written: $had_receipt)"

# UNTESTED (untested_exit) --full: 2026-09-29 (GeelyEx2: REG-QC-05 "test on the real car" always
# exits 2) the receipt was deleted on exit 4, so the suites that DID pass were never reused and
# every --full ran them all again. Now: an exit-4 receipt naming the untested ids; the next --full
# of the same content reuses the PASS entries and still runs the untested suite. A partial run
# never writes it.
rm -rf "$TMP/repo" && mkdir -p "$TMP/repo/src" && cd "$TMP/repo" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
printf 'echo run >> .runs\nexit 0\n' > ok.sh; printf 'echo car >> .car\nexit 2\n' > car.sh
cat > matrix.json <<'JSON'
{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],
 "mandatory_regression_tests":[{"id":"REG-OK","name":"core","command":"sh ok.sh"},
  {"id":"REG-CAR","name":"real car","command":"sh car.sh","untested_exit":2}]}]}
JSON
printf '.runs\n.car\n' >> .git/info/exclude
git add -A && git commit -qm init
echo "fun ok() = 2" > src/Core.kt
rcpt() { python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r.get("exit"), ",".join(r.get("untested") or []))' \
  "$(git rev-parse --absolute-git-dir)/postfix-gate/full_pass.json" 2>/dev/null; }
out="$(run_gate --run-tests)"; rc=$?
[ "$rc" = 4 ] && ! receipt && ok "a run without --full ending UNTESTED writes no receipt" \
  || bad "partial UNTESTED run (exit $rc, receipt '$(rcpt)')"
rm -f .runs .car
out="$(run_gate --run-tests --full)"; rc=$?
[ "$rc" = 4 ] && [ "$(rcpt)" = "4 REG-CAR" ] && ok "--full with an untested_exit suite: exit 4, receipt {exit 4, untested [REG-CAR]}" \
  || bad "--full UNTESTED receipt (exit $rc, receipt '$(rcpt)')"
out="$(run_gate --run-tests --full)"; rc=$?
runs="$(wc -l < .runs | tr -d ' ')"; cars="$(wc -l < .car | tr -d ' ')"
[ "$rc" = 4 ] && [ "$runs" = 1 ] && [ "$cars" = 2 ] && [ "$(rcpt)" = "4 REG-CAR" ] \
  && ok "second --full, same content: REG-OK reused (ran once), REG-CAR run again, still exit 4" \
  || bad "exit-4 receipt not reused (exit $rc, REG-OK runs $runs, REG-CAR runs $cars, receipt '$(rcpt)')"
out="$(run_gate --run-tests)"; rc=$?   # the Stop hook's run: no --full
runs="$(wc -l < .runs | tr -d ' ')"
[ "$rc" = 4 ] && [ "$runs" = 1 ] && [ "$(rcpt)" = "4 REG-CAR" ] \
  && ok "a partial run ending UNTESTED reuses REG-OK and leaves the exit-4 receipt (like a partial PASS)" \
  || bad "partial UNTESTED run on the same content (exit $rc, REG-OK runs $runs, receipt '$(rcpt)')"
echo "fun ok() = 3" > src/Core.kt
out="$(run_gate --run-tests --full)"; rc=$?
runs="$(wc -l < .runs | tr -d ' ')"
[ "$rc" = 4 ] && [ "$runs" = 2 ] && ok "control: other content runs REG-OK again" || bad "control: other content (exit $rc, runs $runs)"
printf 'echo run >> .runs\nexit 1\n' > ok.sh
out="$(run_gate --run-tests --full)"; rc=$?
[ "$rc" = 1 ] && [ -z "$(rcpt)" ] && ok "control: a FAIL next to the untested suite deletes the receipt" \
  || bad "control: FAIL + UNTESTED left a receipt (exit $rc, receipt '$(rcpt)')"

[ "$FAILS" -eq 0 ] && echo "gate receipt: all checks passed" || { echo "gate receipt: $FAILS FAILED"; exit 1; }
