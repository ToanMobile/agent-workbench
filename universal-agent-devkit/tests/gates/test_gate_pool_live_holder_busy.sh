#!/usr/bin/env bash
# Regression test (gate wave 2, lane C2, 03/11): the B5 rule for the machine-wide gate queue (pool 'gate', bin/heavy_slot.py).
# Measured 03/11: the Stop runs that waited the whole 45 s were waiting for a gate SLOT (DEVKIT_GATE_SLOT_WAIT_S=45 from the Stop hook), not
# for test_run.lock: in 61 of 62 Stop waits >= 20 s a gate of another project held a slot for the whole wait. A Stop run
# (TEST_RUN_LOCK_BUSY_FAST=1) that finds EVERY slot held by a LIVE gate (the pid in <slot>.held is a process started before that marker
# was written) waits only DEVKIT_REUSE_LOCK_WAIT_S and says BUSY (exit 4, busy_reason gate_queue, busy_holder who=gate_queue).
#   P1  one slot, held by a live gate: BUSY after <= ~5 s (was the whole DEVKIT_GATE_SLOT_WAIT_S)
#   P2  two slots, both held by live gates: the same
#   P3  two slots, one free: the run takes it and runs its suite (exit 0)
#   P4  a slot held with no .held marker (a holder it cannot name): the whole DEVKIT_GATE_SLOT_WAIT_S, as before
#   P5  the marker names a dead pid: the whole wait
#   P6  the marker is older than the process that has its pid now (a recycled pid): the whole wait
#   P7  the CLI (no BUSY_FAST) behind a live gate: its whole wait, as before
# bash 3.2 compatible; every gate run is under tests/lib/tlimit.py; a private SB_HEAVY_SLOT_DIR (never the real machine pool).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*
set -u
unset DEVKIT_GATE_CACHE DEVKIT_GATE_CACHE_MAX_S GATE_TOTAL_BUDGET_S TEST_RUN_LOCK_WAIT_S DEVKIT_REUSE_LOCK_WAIT_S TEST_RUN_LOCK_BUSY_FAST \
      SB_HEAVY_SLOT_HELD DEVKIT_GATE_SLOT_HELD DEVKIT_GATE_SLOT_WAIT_S DEVKIT_IMPACTED_SINCE CLAUDE_CODE_SESSION_ID DEVKIT_SLOT_ADVISORY_HELD \
      DEVKIT_GATE_SLOTS
export VACUITY_REVERT=0 FLAKY_RETRY=0 DEVKIT_SUITE_CACHE=0
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${POOLLIVE_KIT:-$DEVKIT_DIR}"   # POOLLIVE_KIT=<kit dir>: run against another copy of the kit (the unfixed one goes red)
GATE="$KIT/bin/post-fix-gate.py"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
HOLDERS=""
cleanup() { touch "$TMP/release" 2>/dev/null; for p in $HOLDERS; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }
cp "$DEVKIT_DIR/tests/lib/tlimit.py" "$TMP/tlimit.py"
tl() { python3 -I "$TMP/tlimit.py" "$@"; }

R="$TMP/repo"
export MARK="$TMP/mark"
make_repo() {
  rm -rf "$R" "$MARK" "$SB_HEAVY_SLOT_DIR" && mkdir -p "$R/src" "$MARK" "$SB_HEAVY_SLOT_DIR" && cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  echo "fun ok() = 1" > src/Core.kt
  printf 'echo x >> "$MARK/runs"\nexit 0\n' > ok.sh
  printf '{"project":"t","rules":[{"component":"Core","watch_files":["src/*"],"mandatory_regression_tests":[{"id":"REG-OK","name":"core","command":"sh ok.sh"}]}]}\n' > matrix.json
  git add -A && git commit -qm init
  echo "fun ok() = 2" > src/Core.kt
  GD="$(git -C "$R" rev-parse --absolute-git-dir)/postfix-gate"
}
gate() { # gate <env words…> -- <flags…>: output $TMP/out, exit $RC
  local envs=() flags=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  flags=("$@")
  tl 150 env CLAUDE_PROJECT_DIR="$R" ${envs[@]+"${envs[@]}"} python3 "$GATE" --matrix "$R/matrix.json" --lang en --run-tests ${flags[@]+"${flags[@]}"} \
    > "$TMP/out" 2>&1; RC=$?
}
stop_gate() { gate TEST_RUN_LOCK_BUSY_FAST=1 GATE_TOTAL_BUDGET_S=900 "$@" -- --json --session S-1 --task session-t; }
# hold_slot <k> <marker: live | none | dead | old>: a process that holds gate-<k>.lock (LOCK_EX), as an admitted gate does
hold_slot() {
  rm -f "$TMP/held-$1" "$TMP/release"
  python3 -I - "$SB_HEAVY_SLOT_DIR/gate-$1.lock" "$TMP/held-$1" "$TMP/release" "$2" <<'PY' &
import fcntl, os, subprocess, sys, time
lock, held, release, kind = sys.argv[1:5]
with open(lock, "a") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    if kind == "live":
        open(lock + ".held", "w").write("%d\n" % os.getpid())
    elif kind == "dead":
        p = subprocess.Popen(["true"]); p.wait()
        open(lock + ".held", "w").write("%d\n" % p.pid)
    elif kind == "old":   # written an hour before this process started: a dead holder whose pid this process got
        open(lock + ".held", "w").write("%d\n" % os.getpid())
        t = time.time() - 3600
        os.utime(lock + ".held", (t, t))
    open(held, "w").close()
    for _ in range(1800):
        if os.path.exists(release):
            break
        time.sleep(0.1)
PY
  HOLDERS="$HOLDERS $!"
  local i=0; while [ ! -f "$TMP/held-$1" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
}
release() { touch "$TMP/release"; for p in $HOLDERS; do wait "$p" 2>/dev/null; done; HOLDERS=""; }
lastrow() { python3 -I -c 'import json,sys
try:
    r = [json.loads(l) for l in open(sys.argv[1]) if l.strip()][-1]
except (OSError, ValueError, IndexError):
    print("-1 none"); sys.exit()
print((r.get("steps") or {}).get("lock", -1), json.dumps(r.get("busy_holder"), sort_keys=True, separators=(",", ":")) if "busy_holder" in r else "none")' "$GD/runs.jsonl"; }
lt() { python3 -I -c 'import sys; sys.exit(0 if float(sys.argv[1]) < float(sys.argv[2]) else 1)' "$1" "$2"; }
ge() { python3 -I -c 'import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)' "$1" "$2"; }
queue_busy() { grep -q '"busy_reason": "gate_queue"' "$TMP/out"; }

# ── P1 / P2: every slot held by a live gate: BUSY after the short wait ─────────────────────────────────────────────────────────
fast_case() { # $1 label, $2 number of slots
  make_repo
  local k=1; while [ "$k" -le "$2" ]; do hold_slot "$k" live; k=$((k + 1)); done
  stop_gate DEVKIT_GATE_SLOTS="$2" DEVKIT_GATE_SLOT_WAIT_S=20
  release
  local row lw bh; row="$(lastrow)"; lw="${row%% *}"; bh="${row#* }"
  if [ "$RC" = 4 ] && queue_busy && lt "$lw" 6 && [ ! -f "$MARK/runs" ] && printf '%s' "$bh" | grep -q '"who":"gate_queue"' \
     && printf '%s' "$bh" | grep -q '"fast":"live_pool"'; then
    ok "$1: every slot ($2) held by a live gate: BUSY exit 4 after a ${lw} s wait (not the 20 s of DEVKIT_GATE_SLOT_WAIT_S); busy_holder $bh"
  else
    bad "$1: rc=$RC (want 4), gate_queue lines $(grep -c '"busy_reason": "gate_queue"' "$TMP/out"), lock step ${lw} s (want < 6 of 20), suite ran: $([ -f "$MARK/runs" ] && echo yes || echo no), busy_holder $bh"
  fi
}
fast_case P1 1
fast_case P2 2

# ── P3: two slots, one free: the run is admitted ─────────────────────────────────────────────────────────────────────────────
make_repo
hold_slot 1 live
stop_gate DEVKIT_GATE_SLOTS=2 DEVKIT_GATE_SLOT_WAIT_S=20
release
if [ "$RC" = 0 ] && [ -f "$MARK/runs" ]; then
  ok "P3: one of two slots free: admitted, the suite ran (exit 0)"
else
  bad "P3: rc=$RC (want 0), suite ran: $([ -f "$MARK/runs" ] && echo yes || echo no)"
fi

# ── P4 / P5 / P6 / P7: a holder it cannot name as a live gate, or the CLI: the whole wait, as before ─────────────────────────────
slow_case() { # $1 label, $2 marker kind, $3 stop | cli
  make_repo
  hold_slot 1 "$2"
  if [ "$3" = cli ]; then gate DEVKIT_GATE_SLOTS=1 DEVKIT_GATE_SLOT_WAIT_S=6 -- --json; else stop_gate DEVKIT_GATE_SLOTS=1 DEVKIT_GATE_SLOT_WAIT_S=6; fi
  release
  local row lw; row="$(lastrow)"; lw="${row%% *}"
  if [ "$RC" = 4 ] && queue_busy && ge "$lw" 5.5; then
    ok "$1: BUSY only after the whole DEVKIT_GATE_SLOT_WAIT_S (${lw} s of 6)"
  else
    bad "$1: rc=$RC (want 4), gate_queue lines $(grep -c '"busy_reason": "gate_queue"' "$TMP/out"), lock step ${lw} s (want >= 5.5: the whole wait)"
  fi
}
slow_case "P4/no marker" none stop
slow_case "P5/dead pid" dead stop
slow_case "P6/recycled pid (marker older than the process)" old stop
slow_case "P7/CLI behind a live gate" live cli

echo
if [ "$FAILS" -eq 0 ]; then echo "test_gate_pool_live_holder_busy: all passed"; exit 0; fi
echo "test_gate_pool_live_holder_busy: $FAILS failed"; exit 1
