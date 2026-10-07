#!/usr/bin/env bash
# Regression (DevKit speed, Goods, user decision 2026-10-07): a Unity batch suite (unity-batch / -runTests) was never re-used, so
# every gate run re-ran EditMode (~65 s) and PlayMode (~210 s) on content that had already passed: ~30 % of the Goods gate time.
# A real Unity run does not change tree_fp (measured on a clone), so the full-pass receipt may carry it: a Unity TEST suite is
# re-used only when the receipt matched fingerprint, matrix, local config and format AND that suite ran less than
# DEVKIT_UNITY_REUSE_MAX_S (default 3600) ago (receipt tests[].ran_at, carried over when a later run re-uses it).
#   1. same content twice: Unity runs once, a plain suite once (RED on the old gate: Unity ran twice)
#   2. a suite that talks to a device (adb) next to it runs every time, the Unity one is re-used
#   3. older than the limit: Unity runs again        4. DEVKIT_UNITY_REUSE_MAX_S=0: Unity runs again (kill switch)
#   5. changed content: everything runs again        6. a Unity command that also names adb is never re-used
#   7. re-use does not renew the age: the receipt keeps the suite's own ran_at
#   8. a ran_at in the future (clock skew) is not fresh
#   9. a Unity player run on a device (-testPlatform Android) is never re-used, EditMode/PlayMode are
#  10. only Unity TESTS via unity-batch: compile, execute, look-alike names (community-batch) and a bare -runTests are never re-used
#  11. a Unity suite that was UNTESTED (untested_exit) runs again      12. a re-run that FAILS leaves nothing to re-use
#  13. a Unity PASS that aged out while the others stay re-usable: it runs once, then is re-used again (ran_at is per suite)
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
unset DEVKIT_UNITY_REUSE_MAX_S DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S
export VACUITY_REVERT=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

R="$TMP/repo"
export MARK="$TMP/mark"
OUT=""; RC=0; RCPT=""

suite() { printf '{"id":"%s","name":"%s","command":"%s"}' "$1" "$1" "$2"; }
make_repo() { # $1 = suites (json list body)
  rm -rf "$R" "$MARK" && mkdir -p "$R/src" "$R/tests" "$MARK" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  for n in fake-unity-batch community-batch; do printf 'echo x >> "$MARK/unity_runs"\nexit "${FAKE_UNITY_EXIT:-0}"\n' > "tests/$n.sh"; done
  printf 'echo x >> "$MARK/adb_runs"\nexit 0\n' > tests/device.sh
  printf 'echo x >> "$MARK/plain_runs"\nexit 0\n' > tests/plain.sh
  printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[%s]}]}\n' "$1" > matrix.json
  git add -A && git commit -qm init
  echo "fun ok() = 2" > src/Core.kt
  RCPT="$(git -C "$R" rev-parse --absolute-git-dir)/postfix-gate/full_pass.json"
}
run_gate() { OUT="$(CLAUDE_PROJECT_DIR="$R" env "$@" python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests --full 2>&1)"; RC=$?; }
runs() { if [ -f "$MARK/$1" ]; then wc -l < "$MARK/$1" | tr -d ' '; else echo 0; fi; }
# plant a stamp into the receipt: $1 = suite id (or RECEIPT for its own tested_at), $2 = seconds from now
plant() {
  python3 -I - "$RCPT" "$1" "$2" <<'PY'
import json, sys, time
p, sid, off = sys.argv[1], sys.argv[2], float(sys.argv[3])
r = json.load(open(p))
if sid == "RECEIPT":
    r["tested_at"] = time.time() + off
for t in r["tests"]:
    if t["id"] == sid:
        t["ran_at"] = time.time() + off
json.dump(r, open(p, "w"))
PY
}
ran_at_of() { python3 -I -c "import json,sys;r=json.load(open(sys.argv[1]));print([t.get('ran_at') for t in r['tests'] if t['id']==sys.argv[2]][0])" "$RCPT" "$1"; }
within() { python3 -I -c "import sys,time;print('yes' if abs(float(sys.argv[1]) - (time.time() + float(sys.argv[2]))) < float(sys.argv[3]) else 'no')" "$1" "$2" "$3"; }

UNITY='sh tests/fake-unity-batch.sh playmode'
PLAIN='sh tests/plain.sh'

# 1. same content twice
make_repo "$(suite REG-U "$UNITY"),$(suite REG-P "$PLAIN")"
run_gate A=1; run_gate A=1
if [ "$RC" = 0 ] && [ "$(runs unity_runs)" = 1 ] && [ "$(runs plain_runs)" = 1 ]; then ok "1: the second run on the same content re-uses the Unity PASS (Unity ran $(runs unity_runs)x, plain $(runs plain_runs)x)"
else bad "1: Unity ran $(runs unity_runs)x, plain $(runs plain_runs)x, exit $RC (want 1 and 1)"; printf '%s\n' "$OUT" | tail -12; fi

# 2. a device suite next to it is never re-used, the Unity one is
make_repo "$(suite REG-U "$UNITY"),$(suite REG-D 'sh tests/device.sh adb')"
run_gate A=1; run_gate A=1
if [ "$(runs unity_runs)" = 1 ] && [ "$(runs adb_runs)" = 2 ]; then ok "2: Unity re-used (1 run), the adb suite ran again (2 runs)"
else bad "2: Unity ran $(runs unity_runs)x (want 1), adb $(runs adb_runs)x (want 2), exit $RC"; printf '%s\n' "$OUT" | tail -12; fi

# 3. older than the limit
make_repo "$(suite REG-U "$UNITY"),$(suite REG-P "$PLAIN")"
run_gate DEVKIT_UNITY_REUSE_MAX_S=1; sleep 3; run_gate DEVKIT_UNITY_REUSE_MAX_S=1
if [ "$(runs unity_runs)" = 2 ] && [ "$(runs plain_runs)" = 1 ]; then ok "3: a Unity PASS older than DEVKIT_UNITY_REUSE_MAX_S runs again, the plain suite is still re-used"
else bad "3: Unity ran $(runs unity_runs)x (want 2), plain $(runs plain_runs)x (want 1)"; printf '%s\n' "$OUT" | tail -12; fi

# 4. kill switch
make_repo "$(suite REG-U "$UNITY"),$(suite REG-P "$PLAIN")"
run_gate DEVKIT_UNITY_REUSE_MAX_S=0; run_gate DEVKIT_UNITY_REUSE_MAX_S=0
if [ "$(runs unity_runs)" = 2 ] && [ "$(runs plain_runs)" = 1 ]; then ok "4: DEVKIT_UNITY_REUSE_MAX_S=0 turns the Unity re-use off"
else bad "4: Unity ran $(runs unity_runs)x (want 2), plain $(runs plain_runs)x (want 1)"; printf '%s\n' "$OUT" | tail -12; fi

# 5. changed content
make_repo "$(suite REG-U "$UNITY"),$(suite REG-P "$PLAIN")"
run_gate A=1; echo "fun ok() = 3" > "$R/src/Core.kt"; run_gate A=1
if [ "$(runs unity_runs)" = 2 ] && [ "$(runs plain_runs)" = 2 ]; then ok "5: edited code runs every suite again, Unity included"
else bad "5: Unity ran $(runs unity_runs)x, plain $(runs plain_runs)x (want 2 and 2)"; printf '%s\n' "$OUT" | tail -12; fi

# 6. a Unity command that also names a device
make_repo "$(suite REG-U 'sh tests/fake-unity-batch.sh playmode --device adb'),$(suite REG-P "$PLAIN")"
run_gate A=1; run_gate A=1
if [ "$(runs unity_runs)" = 2 ] && [ "$(runs plain_runs)" = 1 ]; then ok "6: a Unity command that names adb is never re-used"
else bad "6: Unity+adb ran $(runs unity_runs)x (want 2), plain $(runs plain_runs)x (want 1)"; printf '%s\n' "$OUT" | tail -12; fi

# 7. re-use must not renew the age: the receipt of the re-using run keeps the suite's own ran_at
make_repo "$(suite REG-U "$UNITY"),$(suite REG-P "$PLAIN")"
run_gate A=1; plant REG-U -100; run_gate A=1
if [ "$(runs unity_runs)" = 1 ] && [ "$(within "$(ran_at_of REG-U)" -100 30)" = yes ]; then ok "7: the re-using run kept the Unity suite's ran_at (about 100 s old), it did not renew it"
else bad "7: Unity ran $(runs unity_runs)x (want 1), ran_at $(ran_at_of REG-U) is not the planted one"; printf '%s\n' "$OUT" | tail -12; fi

# 8. a ran_at in the future has a negative age: not fresh
make_repo "$(suite REG-U "$UNITY"),$(suite REG-P "$PLAIN")"
run_gate A=1; plant REG-U 1000; run_gate A=1
if [ "$(runs unity_runs)" = 2 ] && [ "$(runs plain_runs)" = 1 ]; then ok "8: a Unity ran_at in the future does not count as fresh (Unity ran again, the plain suite was re-used)"
else bad "8: Unity ran $(runs unity_runs)x (want 2), plain $(runs plain_runs)x (want 1) with a future ran_at"; printf '%s\n' "$OUT" | tail -12; fi

# 9. a Unity player run on a device is never re-used; EditMode / PlayMode platforms are
make_repo "$(suite REG-U 'sh tests/fake-unity-batch.sh playmode -testPlatform Android'),$(suite REG-P "$PLAIN")"
run_gate A=1; run_gate A=1; android="$(runs unity_runs)"
make_repo "$(suite REG-U 'sh tests/fake-unity-batch.sh playmode -testPlatform PlayMode'),$(suite REG-P "$PLAIN")"
run_gate A=1; run_gate A=1
if [ "$android" = 2 ] && [ "$(runs unity_runs)" = 1 ]; then ok "9: -testPlatform Android ran twice (never re-used), -testPlatform PlayMode once (re-used)"
else bad "9: Android ran ${android}x (want 2), PlayMode ran $(runs unity_runs)x (want 1)"; fi

# 10. only Unity tests: compile, execute and a look-alike name are never re-used
bad10=""
for cmd in 'sh tests/fake-unity-batch.sh compile' 'sh tests/fake-unity-batch.sh execute My.Namespace.Method' 'sh tests/community-batch.sh editmode'; do
  make_repo "$(suite REG-U "$cmd"),$(suite REG-P "$PLAIN")"
  run_gate A=1; run_gate A=1
  [ "$(runs unity_runs)" = 2 ] || bad10="$bad10 [$cmd ran $(runs unity_runs)x]"
done
# a command that is not Unity but carries -runTests (the old DEVICE_SUITE never re-used it) must not become re-usable
make_repo "$(suite REG-P 'sh tests/plain.sh -runTests')"
run_gate A=1; run_gate A=1
[ "$(runs plain_runs)" = 2 ] || bad10="$bad10 [a bare -runTests command ran $(runs plain_runs)x]"
if [ -z "$bad10" ]; then ok "10: compile, execute, community-batch and a bare -runTests command ran every time (only unity-batch editmode|playmode is re-used)"
else bad "10: re-used when it must not be:$bad10"; fi

# 11. a Unity suite that was UNTESTED (untested_exit) must run again
make_repo '{"id":"REG-U","name":"REG-U","command":"sh tests/fake-unity-batch.sh playmode","untested_exit":2},'"$(suite REG-P "$PLAIN")"
run_gate FAKE_UNITY_EXIT=2; run_gate FAKE_UNITY_EXIT=0
if [ "$(runs unity_runs)" = 2 ] && [ "$(runs plain_runs)" = 1 ]; then ok "11: a Unity suite that could not run (untested_exit) runs again, the plain suite is re-used"
else bad "11: Unity ran $(runs unity_runs)x (want 2), plain $(runs plain_runs)x (want 1)"; printf '%s\n' "$OUT" | tail -12; fi

# 12. a re-run that FAILS leaves no PASS to re-use
make_repo "$(suite REG-U "$UNITY"),$(suite REG-P "$PLAIN")"
run_gate A=1; plant REG-U -5000; run_gate FAKE_UNITY_EXIT=1 FLAKY_RETRY=0; rc2=$RC; run_gate FAKE_UNITY_EXIT=0
if [ "$rc2" != 0 ] && [ "$(runs unity_runs)" = 3 ]; then ok "12: a Unity re-run that failed deleted the PASS: the next gate ran Unity again (3 runs)"
else bad "12: failing re-run exit $rc2, Unity ran $(runs unity_runs)x (want 3)"; printf '%s\n' "$OUT" | tail -12; fi

# 13. a Unity PASS aged out while the plain suite is still re-usable: Unity runs once, then is re-used again
make_repo "$(suite REG-U "$UNITY"),$(suite REG-P "$PLAIN")"
run_gate A=1; plant REG-U -5000; plant RECEIPT -5000; run_gate A=1; after2="$(runs unity_runs)"; run_gate A=1
if [ "$after2" = 2 ] && [ "$(runs unity_runs)" = 2 ] && [ "$(runs plain_runs)" = 1 ]; then ok "13: an aged-out Unity PASS ran once (2 runs) and the next gate re-used it again (still 2), the plain suite never re-ran"
else bad "13: Unity ran ${after2}x after the aged-out run (want 2) and $(runs unity_runs)x after the next (want 2), plain $(runs plain_runs)x (want 1)"; printf '%s\n' "$OUT" | tail -12; fi

[ "$FAILS" = 0 ] && echo "ALL OK" || { echo "$FAILS FAILED"; exit 1; }
