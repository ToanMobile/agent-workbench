#!/usr/bin/env bash
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/testsourceset_gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

B="$TMP/busy"; mkdir -p "$B" && cd "$B" || exit 1
git init -q . && git config user.email t@t && git config user.name t

cat > gradlew <<EOF
#!/bin/sh
echo "1" >> "$TMP/b_compiled"
exit 0
EOF
chmod +x gradlew

mkdir -p app/src/main/java
echo "fun ok() = 1" > app/src/main/java/Core.kt
cat > app/build.gradle <<'EOF'
plugins {
    id 'org.jetbrains.kotlin.jvm' version '1.9.0'
}
EOF
git add -A && git commit -qm init

printf '%s\n' '{"type":"user","message":{"role":"user","content":"fix it"},"uuid":"u1","sessionId":"b-1"}' '{"type":"model","message":{"role":"model","content":[{"type":"tool_use","id":"1","name":"bash","input":{"command":"echo > app/src/main/java/Core.kt"}}]},"uuid":"u2","sessionId":"b-1"}' > "$TMP/b.jsonl"

LOG_DIR="$B/.claude/audit-gate"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/testsourceset_gate.log"

hold_lock() {
  rm -f "$TMP/b_held"
  python3 - "$B" "$TMP/b_held" "$1" <<'PY' &
import fcntl, os, sys, time
os.makedirs(sys.argv[1] + "/.claude/audit-gate", exist_ok=True)
with open(sys.argv[1] + "/.claude/audit-gate/test_run.lock", "a") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    open(sys.argv[2], "w").close()
    time.sleep(float(sys.argv[3]))
PY
  b_holder=$!
  for _ in $(seq 1 50); do [ -f "$TMP/b_held" ] && break; sleep 0.1; done
}

timed_stop() {
  python3 - "$HOOK" "$B" "$TMP/b.jsonl" "70" "$TMP/out" "$TMP/err" "$@" <<'PY' >"$TMP/timed"
import json, os, signal, subprocess, sys, time
hook, repo, tp, limit, out, err = sys.argv[1:7]
env = {k: v for k, v in os.environ.items() if k != "TESTSOURCESET_LOCK_WAIT_S"}
env["CLAUDE_PROJECT_DIR"] = repo
env["TESTSOURCESET_GATE_MAX_ATTEMPTS"] = "10"
for kv in sys.argv[7:]:
    k, v = kv.split("=", 1)
    env[k] = v
payload = json.dumps({"session_id": "b-1", "hook_event_name": "Stop", "transcript_path": tp})
t0 = time.monotonic()
with open(out, "w") as fo, open(err, "w") as fe:
    p = subprocess.Popen(["bash", hook], stdin=subprocess.PIPE, stdout=fo, stderr=fe, env=env, start_new_session=True)
    try:
        p.communicate(payload.encode(), timeout=float(limit))
        rc = p.returncode
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.wait()
        rc = "TIMEOUT"
print(rc, "%.1f" % (time.monotonic() - t0))
PY
  read -r T_RC T_SEC < "$TMP/timed"
}

echo "fun ok() = 2" > app/src/main/java/Core.kt

# 1.
rm -f "$TMP/b_compiled"
rm -f "$LOG_DIR/.testsourceset_attempts_b_1"
hold_lock 60
timed_stop TESTSOURCESET_LOCK_WAIT_S=3
if grep -q "BUSY" "$TMP/err" "$TMP/out" || grep -q "một lượt chạy test khác đang giữ khoá" "$TMP/err" "$TMP/out"; then
  ok "1: Found BUSY system message"
else
  fail "1: No BUSY system message. err='$(cat "$TMP/err")'"
fi
if [ ! -f "$TMP/b_compiled" ]; then
  ok "1: Did not compile"
else
  fail "1: Compiled despite lock!"
fi
kill "$b_holder" 2>/dev/null; wait "$b_holder" 2>/dev/null

# 2.
rm -f "$TMP/b_compiled"
timed_stop TESTSOURCESET_LOCK_WAIT_S=3
if [ -f "$TMP/b_compiled" ]; then
  count=$(wc -l < "$TMP/b_compiled" | tr -d ' ')
  if [ "$count" -eq 1 ]; then
    ok "2: Compiled EXACTLY ONCE when lock free"
  else
    fail "2: Compiled $count times, expected 1"
  fi
else
  fail "2: Did not compile when lock free. err=$(cat $TMP/err) out=$(cat $TMP/out) log=$(cat $LOG)"
fi
python3 - "$B" <<'PY' || fail "2: Lock was not released"
import fcntl, os, sys
try:
    with open(sys.argv[1] + "/.claude/audit-gate/test_run.lock", "a") as f:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        sys.exit(0)
except Exception:
    sys.exit(1)
PY

# 3.
echo "fun ok() = 3" > app/src/main/java/Core.kt
rm -f "$TMP/b_compiled"
hold_lock 10
timed_stop TESTSOURCESET_LOCK_WAIT_S=3
kill "$b_holder" 2>/dev/null; wait "$b_holder" 2>/dev/null
rm -f "$TMP/b_compiled"
timed_stop TESTSOURCESET_LOCK_WAIT_S=3
if [ -f "$TMP/b_compiled" ]; then
  ok "3: Compiled after BUSY"
else
  fail "3: Did not compile after BUSY (maybe cached?)"
fi

# 4.
echo "fun ok() = 4" > app/src/main/java/Core.kt
rm -f "$TMP/b_compiled"
hold_lock 60
t0=$(python3 -c "import time; print(time.monotonic())")
timed_stop TESTSOURCESET_LOCK_WAIT_S=0
t1=$(python3 -c "import time; print(time.monotonic())")
duration=$(python3 -c "print($t1 - $t0)")
if python3 -c "import sys; sys.exit(0 if $duration < 30 else 1)"; then
  if grep -q 'UNTESTED' "$TMP/out" && grep -q 'waited 0s' "$LOG"; then
    ok "4: Returned immediately ($duration s) and logged waited 0s"
  else
    fail "4: Did not contain expected BUSY and waited 0s. Out: $(cat "$TMP/out")"
  fi
else
  fail "4: Took too long ($duration s)"
fi
kill "$b_holder" 2>/dev/null; wait "$b_holder" 2>/dev/null
# 5.
echo "fun ok() = 5" > app/src/main/java/Core.kt
rm -f "$TMP/b_compiled"
rm -f "$LOG_DIR/test_run.lock"
mkdir -p "$LOG_DIR/test_run.lock"
if [ -d "$LOG_DIR/test_run.lock" ]; then
  timed_stop TESTSOURCESET_LOCK_WAIT_S=3
  if [ -f "$TMP/b_compiled" ]; then
    ok "5: Compiled when lock file cannot be created (is directory)"
  else
    fail "5: Did not compile when lock file cannot be created"
  fi
else
  fail "5: Could not create test_run.lock directory"
fi
rmdir "$LOG_DIR/test_run.lock"

# 6.
echo "fun ok() = 6" > app/src/main/java/Core.kt
rm -f "$TMP/b_compiled"
cat > gradlew <<EOF
#!/bin/sh
( sleep 8 >/dev/null 2>&1 & )
echo "1" >> "$TMP/b_compiled"
exit 0
EOF
chmod +x gradlew
timed_stop TESTSOURCESET_LOCK_WAIT_S=3
if python3 - "$B" <<'PY'; then
import fcntl, os, sys
try:
    with open(sys.argv[1] + "/.claude/audit-gate/test_run.lock", "a") as f:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        sys.exit(0)
except Exception:
    sys.exit(1)
PY
  ok "6: Lock is free immediately despite child process living on"
else
  fail "6: Lock STILL HELD because FD leaked to child process!"
fi


# 7. Injection in WAIT_LIMIT
echo "fun ok() = 7" > app/src/main/java/Core.kt
rm -f "$TMP/b_compiled"
rm -f "$DEVKIT_DIR/INJECTED" "$B/INJECTED" "INJECTED"
timed_stop TESTSOURCESET_LOCK_WAIT_S='1); open("INJECTED","w"); ('
if [ ! -f "INJECTED" ] && [ ! -f "$B/INJECTED" ] && [ ! -f "$DEVKIT_DIR/INJECTED" ]; then
  if [ -f "$TMP/b_compiled" ]; then
    ok "7: Injection did not execute and compiled"
  else
    fail "7: Did not compile"
  fi
else
  fail "7: INJECTED file created!"
fi
rm -f "$DEVKIT_DIR/INJECTED" "$B/INJECTED" "INJECTED"


# 8. Cached block ignores lock
rm -f "$TMP/b_compiled" "$TMP/err" "$TMP/out"
# Change gradlew to fail
cat << 'SH' > gradlew
#!/bin/sh
echo "e: Compilation error"
exit 1
SH
chmod +x gradlew
echo "fun break_it() = 1" > app/src/main/java/Core.kt
# First run to cache the block
timed_stop TESTSOURCESET_LOCK_WAIT_S=3 TESTS_SOURCESET_TEST_DRY_RUN=1
if [ "$T_RC" = "2" ]; then
  # Now hold the lock and run again on the same tree
  hold_lock 60
  b_holder=$!
  rm -f "$TMP/b_compiled" "$TMP/err" "$TMP/out"
  timed_stop TESTSOURCESET_LOCK_WAIT_S=3 TESTS_SOURCESET_TEST_DRY_RUN=1
  rc=$T_RC
  if [ $rc -eq 2 ] && ! grep -q "UNTESTED" "$TMP/err" "$TMP/out"; then
    ok "8: Cached block bypasses lock and returns rc=2"
  else
    fail "8: Expected rc=2 without UNTESTED, got rc=$rc. err=$(cat $TMP/err) out=$(cat $TMP/out)"
  fi
  kill "$b_holder" 2>/dev/null; wait "$b_holder" 2>/dev/null
else
  fail "8: Setup failed, expected rc=2. err=$(cat $TMP/err) out=$(cat $TMP/out)"
fi

[ $FAILS -eq 0 ] && echo "ALL OK" && exit 0 || { echo "$FAILS FAILED"; exit 1; }
