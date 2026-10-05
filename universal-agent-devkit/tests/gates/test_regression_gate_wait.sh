#!/usr/bin/env bash
# Regression test: how long the Stop hook (hooks/regression_gate.sh) waits for the project's
# test_run.lock another run holds. Measured on 4 repos (2026-09-26..10-04): 73 BUSY outcomes, each a
# full 120 s wait that ran nothing; the waits that did end in a test run were few. The hook's DEFAULT
# wait is WAIT_DEFAULT_S, TEST_RUN_LOCK_WAIT_S overrides it. BUSY stays what it was: exit 0, the
# "lock held" message, nothing cached, no PASS, no block, no full-PASS receipt.
# The default VALUE is checked without waiting it out (the constant in the hook, and the value the hook
# hands the gate when the lock is free); the lock BEHAVIOUR is checked with small overrides, so the
# whole file runs in about 15 s.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u

WAIT_DEFAULT_S=45      # the hook's default lock wait (hooks/regression_gate.sh)
MARGIN_S=15            # process start-up, the gate's own work, one 0.5 s poll, and 10 tests running at once
LIMIT_S=30             # watchdog: a hook still running after this long is stuck on a long wait

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DEVKIT_DIR/hooks/regression_gate.sh"
TMP="$(mktemp -d)"
trap '[ -n "${b_holder:-}" ] && kill "$b_holder" 2>/dev/null; rm -rf "$TMP"' EXIT   # never `kill 0`: that signals the whole process group
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# ── 1. the default value, read from the hook (anchored on the env lookup; exactly one) ─────────
found="$(grep -o 'os.environ.get("TEST_RUN_LOCK_WAIT_S", "[0-9]*")' "$HOOK" | sed 's/.*, "\([0-9]*\)")/\1/')"
if [ "$found" = "$WAIT_DEFAULT_S" ]; then
  ok "the hook's default lock wait is ${WAIT_DEFAULT_S} s (one TEST_RUN_LOCK_WAIT_S lookup in the hook)"
else
  fail "the hook's default lock wait is '${found:-none}', want ${WAIT_DEFAULT_S}"
fi

B="$TMP/busy"; mkdir -p "$B/src" "$B/.agents" && cd "$B" || exit 1
git init -q . && git config user.email t@t && git config user.name t
echo "fun ok() = 1" > src/Core.kt
printf 'printf %%s "${TEST_RUN_LOCK_WAIT_S:-unset}" > "%s"\n' "$TMP/b_wait" > wait.sh
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-B","name":"core","command":"sh wait.sh"}]}]}
JSON
git add -A && git commit -qm init
printf '%s\n' '{"type":"user","message":{"role":"user","content":"fix it"},"uuid":"u1","sessionId":"b-1"}' > "$TMP/b.jsonl"
STATE="$B/.claude/audit-gate/regression_gate.state.json"
LOG="$B/.claude/audit-gate/regression_gate.log"
BUSY_MSG="một lượt chạy test khác đang giữ khoá dự án — chạy lại sau"

# Hold the very lock file the gate uses (post-fix-gate acquire_test_run_lock) for $1 seconds.
hold_lock() { rm -f "$TMP/b_held"
  python3 - "$B" "$TMP/b_held" "$1" <<'PY' &
import fcntl, os, sys, time
os.makedirs(sys.argv[1] + "/.claude/audit-gate", exist_ok=True)
with open(sys.argv[1] + "/.claude/audit-gate/test_run.lock", "a") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    open(sys.argv[2], "w").close()
    time.sleep(float(sys.argv[3]))
PY
  b_holder=$!
  for _ in $(seq 1 50); do [ -f "$TMP/b_held" ] && break; sleep 0.1; done; }

# One Stop, with a watchdog. Sets T_RC (TIMEOUT when the hook outlived LIMIT_S, its process group is
# then killed) and T_SEC. $@ = extra env assignments (NAME=value); TEST_RUN_LOCK_WAIT_S is unset unless given.
timed_stop() {
  python3 - "$HOOK" "$B" "$TMP/b.jsonl" "$LIMIT_S" "$TMP/out" "$TMP/err" "$@" <<'PY' >"$TMP/timed"
import json, os, signal, subprocess, sys, time
hook, repo, tp, limit, out, err = sys.argv[1:7]
env = {k: v for k, v in os.environ.items() if k != "TEST_RUN_LOCK_WAIT_S"}
env["CLAUDE_PROJECT_DIR"] = repo
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
  read -r T_RC T_SEC < "$TMP/timed"; }

state_clean() { python3 -c 'import json,os,sys
d = json.load(open(sys.argv[1])) if os.path.exists(sys.argv[1]) else {}
bad = d.get("untested_fp") or d.get("pass_fp") or any(s.get("result") in ("untested", "pass") for s in d.get("sessions", {}).values())
sys.exit(1 if bad else 0)' "$STATE"; }
no_receipt() { [ ! -e "$B/.git/postfix-gate/full_pass.json" ]; }
within() { python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) <= float(sys.argv[2]) else 1)' "$1" "$2"; }

# ── 2. lock held, override 3 s: BUSY after ~3 s, nothing left behind ───────────────────────────
echo "fun ok() = 2" > src/Core.kt; rm -f "$TMP/b_wait"
hold_lock 60
timed_stop TEST_RUN_LOCK_WAIT_S=3
if [ "$T_RC" = 0 ] && within "$T_SEC" $((3 + MARGIN_S)) && ! within "$T_SEC" 2.7; then
  ok "lock held, TEST_RUN_LOCK_WAIT_S=3: BUSY after ${T_SEC}s (waited, then gave up)"
else
  fail "held lock: rc=$T_RC after ${T_SEC}s, want rc 0 in 3-$((3 + MARGIN_S))s"
fi
grep -q "$BUSY_MSG" "$TMP/out" && [ ! -s "$TMP/err" ] && [ ! -f "$TMP/b_wait" ] \
  && ok "BUSY: stop allowed (no block, nothing on stderr), the lock-held message, no suite ran" \
  || fail "BUSY output (out='$(cat "$TMP/out")' err='$(head -3 "$TMP/err")' ran=$([ -f "$TMP/b_wait" ] && echo yes || echo no))"
state_clean && ! grep -q ' pass ' "$LOG" && no_receipt \
  && ok "BUSY: no cache entry (pass_fp/untested_fp), no pass note, no full-PASS receipt" \
  || fail "BUSY left a verdict behind: state=$(cat "$STATE" 2>/dev/null) log=$(cat "$LOG" 2>/dev/null)"
grep -q ' busy ' "$LOG" && ok "BUSY: logged as busy" || fail "no busy note in the hook log"
kill "$b_holder" 2>/dev/null; wait "$b_holder" 2>/dev/null

# ── 3. lock released during the wait: the suite runs and the normal verdict follows ────────────
hold_lock 2
timed_stop TEST_RUN_LOCK_WAIT_S=8
if [ "$T_RC" = 0 ] && [ "$(cat "$TMP/b_wait" 2>/dev/null)" = 8 ] && ! grep -q "$BUSY_MSG" "$TMP/out" && within "$T_SEC" $((8 + MARGIN_S)); then
  ok "lock released after ~2s: the suite ran, no BUSY, done in ${T_SEC}s"
else
  fail "released lock: rc=$T_RC after ${T_SEC}s wait='$(cat "$TMP/b_wait" 2>/dev/null)' out='$(cat "$TMP/out")'"
fi
grep -q ' pass ' "$LOG" && ok "released lock: the ordinary pass verdict was recorded" || fail "no pass note: $(cat "$LOG")"
wait "$b_holder" 2>/dev/null

# ── 4. a failing suite after the wait still blocks (BUSY must not turn into a PASS or a skip) ──
echo "fun ok() = 3" > src/Core.kt; echo 'exit 1' >> wait.sh
git add -A && git commit -qm "failing suite" && echo "fun ok() = 4" > src/Core.kt
hold_lock 2
timed_stop TEST_RUN_LOCK_WAIT_S=8
if [ "$T_RC" = 2 ] && grep -q "REG-B" "$TMP/err"; then
  ok "lock released, suite fails: the Stop is blocked (exit 2) naming REG-B"
else
  fail "failing suite after the wait: rc=$T_RC err='$(head -3 "$TMP/err")'"
fi
wait "$b_holder" 2>/dev/null

# ── 5. default reaches the gate when the lock is free; an override reaches it unchanged ────────
git checkout -q HEAD~1 -- wait.sh && git add -A && git commit -qm "suite green again"
echo "fun ok() = 5" > src/Core.kt; rm -f "$TMP/b_wait"
timed_stop
[ "$T_RC" = 0 ] && [ "$(cat "$TMP/b_wait" 2>/dev/null)" = "$WAIT_DEFAULT_S" ] \
  && ok "lock free, no override: the hook hands the gate TEST_RUN_LOCK_WAIT_S=$WAIT_DEFAULT_S" \
  || fail "default not handed to the gate: rc=$T_RC wait='$(cat "$TMP/b_wait" 2>/dev/null)'"
echo "fun ok() = 6" > src/Core.kt; rm -f "$TMP/b_wait"
timed_stop TEST_RUN_LOCK_WAIT_S=120
[ "$T_RC" = 0 ] && [ "$(cat "$TMP/b_wait" 2>/dev/null)" = 120 ] \
  && ok "override TEST_RUN_LOCK_WAIT_S=120 is handed to the gate as 120 (above the default 45: not capped to it)" \
  || fail "override not honoured: rc=$T_RC wait='$(cat "$TMP/b_wait" 2>/dev/null)'"

cd "$TMP" || exit 1
if [ "$FAILS" -ne 0 ]; then echo "regression gate lock wait: $FAILS FAILED"; exit 1; fi
echo "regression gate lock wait: all checks passed"
