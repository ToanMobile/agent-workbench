#!/usr/bin/env bash
# Regression test (gate wave 2, lane C, 03/11): who holds .claude/audit-gate/test_run.lock, and what a Stop run does about it.
# Measured 03/11 (runs.jsonl): 41 BUSY Stop runs; 22 waited ~3 s (B5: a named, live gate), 19 waited the whole 45 s with no gate of the
# same project running. The 45 s turned out to be the machine-wide gate queue (pool 'gate', DEVKIT_GATE_SLOT_WAIT_S=45 from the Stop hook),
# not test_run.lock: busy_holder now says which (case G). Cases:
#   A  a Stop run (TEST_RUN_LOCK_BUSY_FAST=1, --session S) with every suite re-used meets a LIVE holder of the SAME session: BUSY at once
#      (exit 4, --json busy true, lock wait < 1 s), never the read-only exit 0; the receipt is left as it was; runs.jsonl has busy_holder
#   B  the same with a suite left to run: BUSY at once (< 1 s; B5 alone waited DEVKIT_REUSE_LOCK_WAIT_S, 3 s)
#   C  a live holder of ANOTHER session: the B5 short wait (DEVKIT_REUSE_LOCK_WAIT_S) as before; busy_holder says sid_match false, alive true
#   D  a holder whose sid is "default": no same-session cut, the B5 short wait
#   E  a same-session record whose start time is not the live process's (a recycled pid): unknown holder, the long wait stays
#   F  the CLI (no BUSY_FAST) behind a same-session holder keeps its own wait, and writes no busy_holder
#   G  test_run.lock free, the machine gate queue full: BUSY after DEVKIT_GATE_SLOT_WAIT_S, busy_holder who=gate_queue
#   H  stale_rerun: while it waits for a gate's lock it does not empty the gate's record; holding the lock it writes who=stale_rerun and
#      empties the record before it lets go
#   J  the gate's own record names its session and who=gate
#   K  (wave 2 fix G1) every suite re-used by content key (suite cache), same-session live holder: BUSY exit 4, never exit 0
#   L  (recheck H2) every suite re-used, the first look sees ANOTHER session's live holder, then this session's run holds the lock before
#      the short wait ends: the give-up look classifies it again: BUSY exit 4 (fast same_session), never the read-only exit 0
# bash 3.2 compatible; every gate run is under tests/lib/tlimit.py; a private SB_HEAVY_SLOT_DIR (never the real machine pool).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S GATE_TOTAL_BUDGET_S TEST_RUN_LOCK_WAIT_S DEVKIT_REUSE_LOCK_WAIT_S TEST_RUN_LOCK_BUSY_FAST \
      SB_HEAVY_SLOT_HELD DEVKIT_GATE_SLOT_HELD DEVKIT_GATE_SLOT_WAIT_S DEVKIT_IMPACTED_SINCE CLAUDE_CODE_SESSION_ID DEVKIT_SLOT_ADVISORY_HELD
export VACUITY_REVERT=0 FLAKY_RETRY=0 DEVKIT_SUITE_CACHE=0 DEVKIT_GATE_SLOTS=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${LOCKSID_KIT:-$DEVKIT_DIR}"   # LOCKSID_KIT=<kit dir>: run against another copy of the kit (the unfixed one goes red)
GATE="$KIT/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
HOLDER=""
trap 'touch "$TMP/release" 2>/dev/null; [ -n "$HOLDER" ] && kill "$HOLDER" 2>/dev/null; rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
cp "$DEVKIT_DIR/tests/lib/tlimit.py" "$TMP/tlimit.py"
tl() { python3 -I "$TMP/tlimit.py" "$@"; }

R="$TMP/repo"
export MARK="$TMP/mark"
make_repo() {
  rm -rf "$R" "$MARK" && mkdir -p "$R/src" "$MARK" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  # the suite copies the lock file while it runs: the record of the gate that holds the lock (case J)
  printf 'cat .claude/audit-gate/test_run.lock > "$MARK/rec" 2>/dev/null; echo x >> "$MARK/runs"\nexit 0\n' > ok.sh
  printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-OK","name":"core","command":"sh ok.sh"}]}]}\n' > matrix.json
  git add -A && git commit -qm init
  echo "fun ok() = 2" > src/Core.kt
  GD="$(git -C "$R" rev-parse --absolute-git-dir)/postfix-gate"
}
# gate <env words…> -- <flags…>: output $TMP/out, exit $RC
gate() {
  local envs=() flags=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  flags=("$@")
  tl 120 env CLAUDE_PROJECT_DIR="$R" ${envs[@]+"${envs[@]}"} python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests ${flags[@]+"${flags[@]}"} \
    > "$TMP/out" 2>&1; RC=$?
}
stop_gate() { # stop_gate <session> <env words…>: what hooks/regression_gate.sh starts (BUSY_FAST, a budget, --session, --json)
  local sid="$1"; shift
  gate TEST_RUN_LOCK_BUSY_FAST=1 GATE_TOTAL_BUDGET_S=900 "$@" -- --json --session "$sid" --task "session-t"
}
# hold_lock <sid> [pid_start override] [flip sid]: a live holder that writes the gate-shaped record {pid, pid_start, sid, who};
# with a flip sid it rewrites the record to that sid (same pid, flock kept) once $TMP/flip exists
hold_lock() {
  rm -f "$TMP/held" "$TMP/release" "$TMP/flip" "$TMP/flipped"
  python3 -I - "$R" "$TMP/held" "$TMP/release" "$KIT/bin" "$1" "${2:-}" "${3:-}" "$TMP/flip" "$TMP/flipped" <<'PY' &
import fcntl, json, os, sys, time
sys.path.insert(0, sys.argv[4]); import session_lock
d = sys.argv[1] + "/.claude/audit-gate"
os.makedirs(d, exist_ok=True)
def record(f, sid):
    f.truncate(0)
    f.write(json.dumps({"pid": os.getpid(), "pid_start": sys.argv[6] or session_lock.pid_start(os.getpid()), "sid": sid, "who": "gate"}) + "\n")
    f.flush()
with open(d + "/test_run.lock", "a") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    record(f, sys.argv[5])
    open(sys.argv[2], "w").close()
    for _ in range(1200):
        if os.path.exists(sys.argv[3]):
            break
        if sys.argv[7] and os.path.exists(sys.argv[8]) and not os.path.exists(sys.argv[9]):
            record(f, sys.argv[7])
            open(sys.argv[9], "w").close()
        time.sleep(0.1)
PY
  HOLDER=$!
  local i=0; while [ ! -f "$TMP/held" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
}
release() { touch "$TMP/release"; [ -z "$HOLDER" ] || { wait "$HOLDER" 2>/dev/null; HOLDER=""; }; }
# last runs.jsonl row: "<lock seconds> <busy> <verdict> <busy_holder json or none>"
lastrow() { python3 -I -c 'import json,sys
try:
    r = [json.loads(l) for l in open(sys.argv[1]) if l.strip()][-1]
except (OSError, ValueError, IndexError):
    print("-1 none none none"); sys.exit()
print((r.get("steps") or {}).get("lock", -1), str(r.get("busy")).lower(), r.get("verdict"), json.dumps(r.get("busy_holder"), sort_keys=True, separators=(",", ":")) if "busy_holder" in r else "none")' "$GD/runs.jsonl"; }
holder_field() { python3 -I -c 'import json,sys
h = json.loads(sys.argv[1]) if sys.argv[1] != "none" else None
v = (h or {}).get(sys.argv[2], "absent")
print(json.dumps(v))' "$1" "$2"; }
lt() { python3 -I -c 'import sys; sys.exit(0 if float(sys.argv[1]) < float(sys.argv[2]) else 1)' "$1" "$2"; }
ge() { python3 -I -c 'import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)' "$1" "$2"; }
rtime() { python3 -I -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("time"))
except (OSError, ValueError): print("none")' "$GD/full_pass.json"; }

# ── A: every suite re-used, same-session live holder: BUSY at once, never the read-only exit 0 ─────────────────────────────────
make_repo
gate -- --full --no-checklist; seed=$RC; t0="$(rtime)"
hold_lock S-1
stop_gate S-1
release
row="$(lastrow)"; set -- $row; lw="$1"; busy="$2"; verdict="$3"; bh="${row#* * * }"
if [ "$seed" != 0 ] || [ "$t0" = none ]; then
  bad "A: setup went wrong: seed --full rc=$seed receipt time $t0"
elif [ "$RC" = 4 ] && lt "$lw" 1 && grep -q '"busy": true' "$TMP/out" && [ "$busy" = true ] && [ "$(rtime)" = "$t0" ] \
     && [ "$(holder_field "$bh" who)" = '"gate"' ] && [ "$(holder_field "$bh" sid_match)" = true ] && [ "$(holder_field "$bh" alive)" = true ]; then
  ok "A: all suites re-used, same-session live holder: BUSY exit 4 after a ${lw} s lock wait, not read-only; receipt untouched; busy_holder $bh"
else
  bad "A: rc=$RC (want 4, never the read-only 0), lock wait ${lw} s (want < 1), runs.jsonl busy=$busy verdict=$verdict, receipt time $t0 -> $(rtime), busy_holder $bh; out: $(grep -E 'wrote nothing|UNTESTED|PASS' "$TMP/out" | head -2)"
fi

# ── B: a suite left to run, same-session live holder: BUSY at once (B5 alone waited 3 s) ──────────────────────────────────────
make_repo
hold_lock S-1
stop_gate S-1
release
row="$(lastrow)"; set -- $row; lw="$1"; busy="$2"; bh="${row#* * * }"
if [ "$RC" = 4 ] && lt "$lw" 1 && [ "$busy" = true ] && [ ! -f "$MARK/runs" ] && [ "$(holder_field "$bh" sid_match)" = true ]; then
  ok "B: suite to run, same-session live holder: BUSY exit 4 after ${lw} s, nothing run; busy_holder $bh"
else
  bad "B: rc=$RC (want 4), lock wait ${lw} s (want < 1), busy=$busy, suite ran: $([ -f "$MARK/runs" ] && echo yes || echo no), busy_holder $bh"
fi

# ── C: another session's live gate: the B5 short wait as before, busy_holder says so ──────────────────────────────────────────
make_repo
hold_lock S-2
stop_gate S-1 DEVKIT_REUSE_LOCK_WAIT_S=2 TEST_RUN_LOCK_WAIT_S=8
release
row="$(lastrow)"; set -- $row; lw="$1"; bh="${row#* * * }"
if [ "$RC" = 4 ] && ge "$lw" 1.5 && lt "$lw" 6 && [ "$(holder_field "$bh" sid_match)" = false ] && [ "$(holder_field "$bh" alive)" = true ] \
   && [ "$(holder_field "$bh" who)" = '"gate"' ]; then
  ok "C: another session's live gate: BUSY after the B5 short wait (${lw} s of DEVKIT_REUSE_LOCK_WAIT_S=2); busy_holder $bh"
else
  bad "C: rc=$RC (want 4), lock wait ${lw} s (want 2..6), busy_holder $bh (want who gate, sid_match false, alive true)"
fi

# ── D: sid "default" is no session: no same-session cut ───────────────────────────────────────────────────────────────────
make_repo
hold_lock default
stop_gate default DEVKIT_REUSE_LOCK_WAIT_S=2 TEST_RUN_LOCK_WAIT_S=8
release
row="$(lastrow)"; set -- $row; lw="$1"
if [ "$RC" = 4 ] && ge "$lw" 1.5; then
  ok "D: holder and run both 'default': no same-session cut, the B5 short wait (${lw} s)"
else
  bad "D: rc=$RC (want 4), lock wait ${lw} s (want >= 1.5: 'default' is no session)"
fi

# ── E: same sid, but the record's start time is not the live process's (recycled pid): unknown, the long wait ─────────────────
make_repo
hold_lock S-1 "Thu Jan  1 00:00:00 1970"
stop_gate S-1 TEST_RUN_LOCK_WAIT_S=4
release
row="$(lastrow)"; set -- $row; lw="$1"; bh="${row#* * * }"
if [ "$RC" = 4 ] && ge "$lw" 3.5 && [ "$(holder_field "$bh" alive)" = false ]; then
  ok "E: same-session record with another start time (a recycled pid): unknown holder, the long wait stays (${lw} s); busy_holder $bh"
else
  bad "E: rc=$RC (want 4), lock wait ${lw} s (want >= 3.5), busy_holder $bh (want alive false)"
fi

# ── F: the CLI behind a same-session holder keeps its own wait; no busy_holder in its row ─────────────────────────────────────
make_repo
hold_lock S-1
gate CLAUDE_CODE_SESSION_ID=S-1 TEST_RUN_LOCK_WAIT_S=3 -- --json
release
row="$(lastrow)"; set -- $row; lw="$1"; bh="${row#* * * }"
if [ "$RC" = 4 ] && ge "$lw" 2.5 && [ "$bh" = none ]; then
  ok "F: the CLI (no BUSY_FAST) behind a same-session holder waits its TEST_RUN_LOCK_WAIT_S (${lw} s), no busy_holder field"
else
  bad "F: rc=$RC (want 4), lock wait ${lw} s (want >= 2.5), busy_holder $bh (want none)"
fi

# ── G: test_run.lock free, the machine gate queue full: BUSY after DEVKIT_GATE_SLOT_WAIT_S, busy_holder who=gate_queue ──────────
make_repo
mkdir -p "$SB_HEAVY_SLOT_DIR"; rm -f "$TMP/sheld" "$TMP/release"
python3 -I - "$SB_HEAVY_SLOT_DIR/gate-1.lock" "$TMP/sheld" "$TMP/release" <<'PY' &
import fcntl, os, sys, time
with open(sys.argv[1], "a") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    open(sys.argv[1] + ".held", "w").write("%d\n" % os.getpid())
    open(sys.argv[2], "w").close()
    for _ in range(1200):
        if os.path.exists(sys.argv[3]):
            break
        time.sleep(0.1)
PY
HOLDER=$!
i=0; while [ ! -f "$TMP/sheld" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
stop_gate S-1 DEVKIT_GATE_SLOTS=1 DEVKIT_GATE_SLOT_WAIT_S=3
release
row="$(lastrow)"; set -- $row; lw="$1"; bh="${row#* * * }"
if [ "$RC" = 4 ] && grep -q '"busy_reason": "gate_queue"' "$TMP/out" && ge "$lw" 2.5 && [ "$(holder_field "$bh" who)" = '"gate_queue"' ]; then
  ok "G: lock free, gate queue full: BUSY after ${lw} s (DEVKIT_GATE_SLOT_WAIT_S=3), busy_reason gate_queue, busy_holder $bh"
else
  bad "G: rc=$RC (want 4), busy_reason lines $(grep -c '"busy_reason": "gate_queue"' "$TMP/out"), lock step ${lw} s (want >= 2.5), busy_holder $bh (want who gate_queue)"
fi

# ── H: stale_rerun keeps a gate's record while it waits; writes its own while it holds; empties it before letting go ─────────────
make_repo
hold_lock S-9
python3 -I - "$KIT/scripts/testing" "$KIT/bin" "$R" > "$TMP/h1" 2>&1 <<'PY'
import sys, time
from pathlib import Path
sys.path[:0] = [sys.argv[1], sys.argv[2]]
import stale_rerun
with stale_rerun.test_run_lock(Path(sys.argv[3]), time.monotonic() + 1.0) as held:
    print("held=%s" % held)
PY
rec1="$(cat "$R/.claude/audit-gate/test_run.lock" 2>/dev/null)"
release
python3 -I - "$KIT/scripts/testing" "$KIT/bin" "$R" > "$TMP/h2" 2>&1 <<'PY'
import json, os, sys, time
from pathlib import Path
sys.path[:0] = [sys.argv[1], sys.argv[2]]
import stale_rerun
p = Path(sys.argv[3]) / ".claude" / "audit-gate" / "test_run.lock"
with stale_rerun.test_run_lock(Path(sys.argv[3]), time.monotonic() + 5.0) as held:
    rec = json.loads(p.read_text() or "null")
    print("held=%s who=%s mine=%s" % (held, (rec or {}).get("who"), (rec or {}).get("pid") == os.getpid()))
print("after=%r" % p.read_text())
PY
if grep -q 'held=False' "$TMP/h1" && printf '%s' "$rec1" | grep -q '"sid": "S-9"'; then
  ok "H1: stale_rerun waiting behind a gate (BUSY) left the gate's record as it was"
else
  bad "H1: stale_rerun: $(cat "$TMP/h1"); gate record after its wait: '$rec1' (want the S-9 record kept)"
fi
if grep -q 'held=True who=stale_rerun mine=True' "$TMP/h2" && grep -q "after=''" "$TMP/h2"; then
  ok "H2: stale_rerun holding the lock writes who=stale_rerun (its own pid) and empties the record before it lets go"
else
  bad "H2: stale_rerun record: $(tr '\n' ' ' < "$TMP/h2")"
fi

# ── J: the gate's own record names its session and who=gate ──────────────────────────────────────────────────────────────
make_repo
stop_gate S-7
if [ "$RC" = 0 ] && python3 -I -c 'import json,sys
r = json.loads(open(sys.argv[1]).read() or "null") or {}
sys.exit(0 if r.get("sid") == "S-7" and r.get("who") == "gate" and isinstance(r.get("pid"), int) else 1)' "$MARK/rec" 2>/dev/null; then
  ok "J: the gate holding the lock recorded {pid, pid_start, sid S-7, who gate}: $(cat "$MARK/rec")"
else
  bad "J: rc=$RC (want 0), record seen by the suite: '$(cat "$MARK/rec" 2>/dev/null)' (want sid S-7, who gate)"
fi

# ── K (wave 2 fix G1): every suite re-used by CONTENT KEY (suite cache, no receipt), same-session live holder: BUSY exit 4 ─────────
# Before the fix reused_pass() left KEYED suites out, nothing turned UNTESTED and the Stop run said exit 0 (the hook then writes pass_fp).
make_repo
gate DEVKIT_SUITE_CACHE=1 -- --full --no-checklist; seed=$RC
rm -f "$GD/full_pass.json"   # no receipt to re-use: the suite comes back by its content key alone
hold_lock S-1
stop_gate S-1 DEVKIT_SUITE_CACHE=1 POSTFIX_GATE_FORCE_FULL=1   # a forced Stop run (CI / POSTFIX_GATE_FORCE_FULL) re-uses by key
release
row="$(lastrow)"; set -- $row; busy="$2"
if [ "$seed" != 0 ]; then
  bad "K: setup went wrong: seed --full rc=$seed"
elif ! grep -q 'content key' "$TMP/out"; then
  bad "K: setup went wrong: the suite was not re-used by content key (rc=$RC); out: $(grep -E 'PASS|UNTESTED' "$TMP/out" | head -2)"
elif [ "$RC" = 4 ] && grep -q '"busy": true' "$TMP/out" && [ "$busy" = true ]; then
  ok "K: every suite re-used by content key, same-session live holder: BUSY exit 4, busy true"
else
  bad "K: rc=$RC (want 4, never exit 0 behind its own session's run), runs.jsonl busy=$busy; out: $(grep -E 'VERDICT|UNTESTED' "$TMP/out" | head -2)"
fi

# ── L (recheck H2): first look = another session's live holder, then this session's run holds the lock: BUSY at give-up ─────────
# Before the fix the give-up look recorded the new holder without `fast`: read_only stayed on and the Stop run said exit 0 (pass_fp).
make_repo
gate -- --full --no-checklist; seed=$RC
hold_lock S-2 "" S-1
rm -f "$TMP/out"
( i=0; while [ "$i" -lt 300 ] && ! grep -q "Another test run is using" "$TMP/out" 2>/dev/null; do sleep 0.1; i=$((i + 1)); done
  touch "$TMP/flip" ) &
WATCH=$!
stop_gate S-1 DEVKIT_REUSE_LOCK_WAIT_S=4
wait "$WATCH" 2>/dev/null
flipped=no; [ -f "$TMP/flipped" ] && flipped=yes
release
row="$(lastrow)"; set -- $row; lw="$1"; busy="$2"; bh="${row#* * * }"
if [ "$seed" != 0 ] || [ "$flipped" != yes ]; then
  bad "L: setup went wrong: seed --full rc=$seed, holder record flipped to S-1: $flipped"
elif [ "$RC" = 4 ] && grep -q '"busy": true' "$TMP/out" && [ "$busy" = true ] && [ "$(holder_field "$bh" fast)" = '"same_session"' ] \
     && [ "$(holder_field "$bh" sid_match)" = true ]; then
  ok "L: holder turned this session's during the short wait: BUSY exit 4 after ${lw} s, busy_holder $bh"
else
  bad "L: rc=$RC (want 4, never the read-only 0 behind its own session's run), runs.jsonl busy=$busy, busy_holder $bh (want fast same_session)"
fi

echo
if [ "$FAILS" -eq 0 ]; then echo "test_test_run_lock_holder_session: all passed"; exit 0; fi
echo "test_test_run_lock_holder_session: $FAILS failed"; exit 1
