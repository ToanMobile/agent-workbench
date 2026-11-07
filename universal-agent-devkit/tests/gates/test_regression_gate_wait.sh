#!/usr/bin/env bash
# Regression test (ported to gate speed v26 mục 1, 07/11): the Stop hook (hooks/regression_gate.sh) never waits on the project's
# test_run.lock. Before v26 the hook ran the gate, which waited up to TEST_RUN_LOCK_WAIT_S (hook default 45 s) for the lock another run
# held, then said BUSY (measured on 4 repos, 2026-09-26..10-04: 73 BUSY outcomes, each a full wait that ran nothing). v26: the Stop runs
# NO suite and starts no gate; it only reads the receipt / outcome of the tree, so a held lock changes nothing and costs no time.
#   W1 lock held by another process, no receipt: the Stop blocks with the gate command at once (no BUSY wording), starts nothing
#   W2 lock held, a receipt of this tree: the Stop allows at once, starts nothing
#   W3 lock held, TEST_RUN_LOCK_WAIT_S=120 in the environment: still at once (the hook hands no wait to anything), blocked, nothing started
#   W4 the hook holds no TEST_RUN_LOCK_WAIT_S lookup (the old default wait lived there)
# Every Stop runs under a watchdog (LIMIT_S; a hook that outlives it is killed and reported TIMEOUT) and must end within MAX_S.
# The kit under test is a COPY whose bin/post-fix-gate.py counts its starts when GATE_SPAWNS names a file (only the hook's Stops set it).
# bash 3.2 compatible; LOCKWAIT_KIT=<kit dir> tests another copy of the kit (a mutant, or the pre-v26 kit, must go red).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
export WORKTREE_TRUNK_MODE=0   # K12 (18/10): các ca ở đây là phiên sửa thẳng main (không trunk mode); ở trunk mode Stop tại main không gate (test_regression_gate_trunk_main.sh)

MAX_S=10               # a Stop that reads files only: process start-up and a few git calls, with room for a loaded machine
LIMIT_S=20             # watchdog: a hook still running after this long is waiting on the lock

DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SRC_KIT="${LOCKWAIT_KIT:-$DEVKIT_DIR}"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap '[ -n "${b_holder:-}" ] && kill "$b_holder" 2>/dev/null; rm -rf "$TMP"' EXIT   # never `kill 0`: that signals the whole process group
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
unset CLAUDE_CODE_SESSION_ID DEVKIT_SESSION_ID CLAUDE_SESSION_ID REGRESSION_GATE_MAX_ATTEMPTS DEVKIT_GATE_CACHE_MAX_S TEST_RUN_LOCK_WAIT_S
export FLAKY_RETRY=0 VACUITY_REVERT=0 DEVKIT_GATE_CACHE=0

KIT="$TMP/kit"
if ! { mkdir -p "$KIT" && cp -R "$SRC_KIT/hooks" "$KIT/hooks" && cp -R "$SRC_KIT/bin" "$KIT/bin"; }; then echo "✖ cannot copy the kit $SRC_KIT"; exit 1; fi
for d in scripts profiles templates rules; do [ -e "$SRC_KIT/$d" ] && ln -s "$SRC_KIT/$d" "$KIT/$d"; done   # what the gate imports (scripts/governance ...)
python3 -I -c 'import sys
p = sys.argv[1]; src = open(p, encoding="utf-8").read().split("\n")
i = next(n for n, l in enumerate(src) if l.startswith("import "))
src.insert(i, "import os as _spawn_os; _spawn_os.environ.get(\"GATE_SPAWNS\") and open(_spawn_os.environ[\"GATE_SPAWNS\"], \"a\").write(\"x\")")
open(p, "w", encoding="utf-8").write("\n".join(src))' "$KIT/bin/post-fix-gate.py" || { echo "✖ cannot instrument the gate copy"; exit 1; }
HOOK="$KIT/hooks/regression_gate.sh"
GATE="$KIT/bin/post-fix-gate.py"
SPAWNS="$TMP/spawns"; : > "$SPAWNS"
spawns() { wc -c < "$SPAWNS" | tr -d ' '; }

# ── W4: no lock wait in the hook ─────────────────────────────────────────────────────────────
n_wait="$(grep -c 'TEST_RUN_LOCK_WAIT_S' "$SRC_KIT/hooks/regression_gate.sh" | tr -d ' ')"
[ "$n_wait" = 0 ] && ok "W4: the hook holds no TEST_RUN_LOCK_WAIT_S lookup (no lock wait to hand to a gate)" \
  || fail "W4: the hook still names TEST_RUN_LOCK_WAIT_S ($n_wait lines)"

B="$TMP/busy"; mkdir -p "$B/src" "$B/.agents" && cd "$B" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
printf '.claude/\n.agents/CHECKLIST.md\n.agents/regression_status.json\n.agents/regression_checklist.md\n' > .gitignore
echo "fun ok() = 1" > src/Core.kt
cat > .agents/regression_matrix.active.json <<'JSON'
{"project":"t","adopted":true,"rules":[{"component":"Core","watch_files":["src/Core.kt"],
 "mandatory_regression_tests":[{"id":"REG-B","name":"core","command":"true"}]}]}
JSON
git add -A && git commit -qm init
printf '%s\n' '{"type":"user","message":{"role":"user","content":"fix it"},"uuid":"u1","sessionId":"b-1"}' > "$TMP/b.jsonl"
STATE="$B/.claude/audit-gate/regression_gate.state.json"
BUSY_MSG="đang giữ khoá"
CMD="post-fix-gate.py --run-tests --scoped --brief"

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

# One Stop, with a watchdog. Sets T_RC (TIMEOUT when the hook outlived LIMIT_S, its process group is then killed) and T_SEC.
# $@ = extra env assignments (NAME=value); TEST_RUN_LOCK_WAIT_S is unset unless given.
timed_stop() {
  python3 - "$HOOK" "$B" "$TMP/b.jsonl" "$LIMIT_S" "$TMP/out" "$TMP/err" "GATE_SPAWNS=$SPAWNS" "$@" <<'PY' >"$TMP/timed"
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
within() { python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) <= float(sys.argv[2]) else 1)' "$1" "$2"; }
gaterun() {
  local vh; vh="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("verified_head") or "")' "$STATE" 2>/dev/null)"
  git cat-file -e "${vh:-none}^{commit}" 2>/dev/null || vh=""
  ( cd "$B" && CLAUDE_PROJECT_DIR="$B" python3 "$GATE" --run-tests --scoped --brief ${vh:+--diff "$vh"} ) >"$TMP/gate.out" 2>&1; GRC=$?
}

timed_stop   # clean tree: verified_head = the start point

# ── W1: lock held, no receipt ───────────────────────────────────────────────────────────────
echo "fun ok() = 2" > src/Core.kt
hold_lock 120
timed_stop
if [ "$T_RC" = 2 ] && within "$T_SEC" "$MAX_S" && grep -q -- "$CMD" "$TMP/err" && ! grep -q "$BUSY_MSG" "$TMP/out" "$TMP/err" && [ "$(spawns)" = 0 ]; then
  ok "W1: lock held, no receipt: blocked with the gate command after ${T_SEC}s (no wait, no BUSY), nothing started"
else
  fail "W1: rc=$T_RC after ${T_SEC}s (want 2 within ${MAX_S}s) spawns=$(spawns) out='$(head -c 200 "$TMP/out")' err='$(head -c 300 "$TMP/err")'"
fi

# ── W3: lock held, a long TEST_RUN_LOCK_WAIT_S in the environment ───────────────────────────
echo "fun ok() = 3" > src/Core.kt
timed_stop TEST_RUN_LOCK_WAIT_S=120
if [ "$T_RC" = 2 ] && within "$T_SEC" "$MAX_S" && grep -q -- "$CMD" "$TMP/err" && [ "$(spawns)" = 0 ]; then
  ok "W3: lock held, TEST_RUN_LOCK_WAIT_S=120: still blocked at once (${T_SEC}s), nothing started"
else
  fail "W3: rc=$T_RC after ${T_SEC}s (want 2 within ${MAX_S}s) spawns=$(spawns) err='$(head -c 300 "$TMP/err")'"
fi
kill "$b_holder" 2>/dev/null; wait "$b_holder" 2>/dev/null

# ── W2: a receipt of this tree, then the lock held: allowed at once ──────────────────────────
echo "fun ok() = 4" > src/Core.kt
gaterun; g2=$GRC
hold_lock 120
timed_stop
if [ "$g2" = 0 ] && [ "$T_RC" = 0 ] && within "$T_SEC" "$MAX_S" && [ ! -s "$TMP/err" ] && ! grep -q "$BUSY_MSG" "$TMP/out" && [ "$(spawns)" = 0 ]; then
  ok "W2: lock held, a receipt of this tree: allowed after ${T_SEC}s, nothing started"
else
  fail "W2: gate=$g2 rc=$T_RC after ${T_SEC}s spawns=$(spawns) out='$(head -c 200 "$TMP/out")' err='$(head -c 300 "$TMP/err")'"
fi
kill "$b_holder" 2>/dev/null; wait "$b_holder" 2>/dev/null

cd "$TMP" || exit 1
if [ "$FAILS" -ne 0 ]; then echo "regression gate lock wait: $FAILS FAILED"; exit 1; fi
echo "regression gate lock wait: all checks passed"
