#!/bin/bash
# #572: a SIGINT/SIGTERM that lands while the main thread holds Popen._waitpid_lock (inside p.wait(timeout=...)) must not deadlock tlimit.py:
# the handler used to call p.wait() with no timeout, which waits for that same lock. The lock window is widened here by sleeping inside
# Popen._try_wait. Rows: SIGINT -> exit 130 + grandchild gone · SIGTERM -> exit 143 + grandchild gone · a child that ignores TERM still ends
# within the ceiling + 2 s after a SIGINT. TLIMIT=<path> tests another copy of the helper (the pre-fix one must go red).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TL="${TLIMIT:-$HERE/lib/tlimit.py}"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed)" >&2; exit 1; fi
cleanup() {
  local f
  for f in "$TMP"/gc.*; do [ -f "$f" ] && kill -9 "$(cat "$f")" 2>/dev/null; done
  [ -n "${PID:-}" ] && kill -9 "$PID" 2>/dev/null
  rm -r "$TMP" 2>/dev/null
}
trap cleanup EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# runs tlimit.py with Popen._try_wait slowed to 0.4 s per poll, so the wait lock is held almost all the time
SLOW='import runpy, subprocess, sys, time
orig = subprocess.Popen._try_wait
def slow(self, wait_flags):
    time.sleep(0.4)
    return orig(self, wait_flags)
subprocess.Popen._try_wait = slow
tl = sys.argv[1]
sys.argv = [tl] + sys.argv[2:]
runpy.run_path(tl, run_name="__main__")'

# <signal> <want rc> <label> <ceiling s> <max wall s> <child script>
lock_row() {
  local sig="$1" want="$2" label="$3" ceil="$4" maxwall="$5" script="$6" f="$TMP/gc.$1" gc rc i t0 t1
  PID=""
  python3 -I -c "$SLOW" "$TL" "$ceil" sh -c "$script" >/dev/null 2>&1 &
  PID=$!
  for i in $(seq 1 50); do [ -s "$f" ] && break; sleep 0.1; done
  if [ ! -s "$f" ]; then bad "$label: grandchild never started"; return; fi
  gc="$(cat "$f")"
  sleep 0.2   # the main thread is now inside the slowed p.wait(timeout=...)
  t0=$(date +%s)
  kill -"$sig" "$PID"
  for i in $(seq 1 $((maxwall * 10))); do kill -0 "$PID" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$PID" 2>/dev/null; then bad "$label: tlimit still alive ${maxwall}s after SIG$sig (deadlock)"; kill -9 "$PID" 2>/dev/null; PID=""; return; fi
  wait "$PID"; rc=$?; PID=""
  t1=$(date +%s)
  if [ "$rc" = "$want" ]; then ok "$label: exit $rc in $((t1 - t0))s"; else bad "$label: exit $rc, want $want"; fi
  for i in $(seq 1 30); do kill -0 "$gc" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$gc" 2>/dev/null; then bad "$label: grandchild $gc still running"; kill -9 "$gc" 2>/dev/null; else ok "$label: grandchild stopped"; fi
}
lock_row INT 130 "SIGINT in wait lock" 60 10 "sleep 300 & echo \$! > '$TMP/gc.INT'; wait"
lock_row TERM 143 "SIGTERM in wait lock" 60 10 "sleep 300 & echo \$! > '$TMP/gc.TERM'; wait"
# the child ignores TERM; the ceiling (5 s) still has to hold after a SIGINT: ceiling + 2 s
lock_row INT 130 "SIGINT, child ignores TERM" 5 8 "trap '' TERM; sleep 300 & echo \$! > '$TMP/gc.INT'; while :; do sleep 1; done"

if [ "$FAILS" = 0 ]; then echo "PASS"; exit 0; fi
echo "FAIL ($FAILS)"; exit 1
