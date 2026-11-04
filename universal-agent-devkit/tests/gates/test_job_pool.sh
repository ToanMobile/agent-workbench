#!/usr/bin/env bash
# tests/lib/job_pool.py: one pool of test slots that several run_impacted.sh shards of one gate share (Việc 2, 04/11).
#   a. 9 jobs over 3 processes' worth of tokens: never more than 3 at once, all 9 ran.
#   b. an --alone job waits for every pool job to end and nothing starts beside it.
#   c. a holder killed by SIGKILL frees its token (flock dies with the process): the next job does not wait for it.
#   d. no pool dir / bad size: the command runs at once (a broken pool never blocks a run); usage error: 64, command not run.
#   e. the wait file holds the seconds waited (whole seconds), the command's exit code is passed through.
#   f. --start-fd/--start-line: the line is written only once the slot is held (a waiting test is not "started"), and fd N is closed
#      before the command runs (it never inherits it).
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
JP="$DEVKIT_DIR/tests/lib/job_pool.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
ok() { echo "ok: $1"; }
bad() { echo "✖ $1"; fails=$((fails + 1)); }
command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; exit 0; }
[ -f "$JP" ] || { echo "✖ tests/lib/job_pool.py missing"; exit 1; }

# job <pool> <size> <name> <seconds> [--alone]: appends "s|e <monotonic ns> <name>" around a sleep
now() { python3 -c 'import time; print(time.monotonic_ns())'; }
job() {
  python3 -I "$JP" "$1" "$2" ${5:-} -- bash -c 'echo "s $(python3 -c "import time; print(time.monotonic_ns())") $1" >> "$2"; sleep "$3"
    echo "e $(python3 -c "import time; print(time.monotonic_ns())") $1" >> "$2"' _ "$3" "$TMP/log" "$4"
}
# peak <log>: the most jobs running at once, and "overlap" when an ALONE job ran beside another
peak() { sort -k2,2n "$1" | awk '{ if ($1 == "s") { n++; if (n > m) m = n; if ($3 ~ /ALONE/) a = 1; else if (a) o = 1; if ($3 ~ /ALONE/ && n > 1) o = 1 }
                                    else { n--; if ($3 ~ /ALONE/) a = 0 } } END { print m + 0, (o ? "overlap" : "clean") }'; }

# a + b
P="$TMP/pool"; mkdir -p "$P"; : > "$TMP/log"
for i in 1 2 3 4 5 6 7 8 9; do job "$P" 3 "w$i" 0.6 & done
sleep 0.3; job "$P" 3 ALONE 0.4 --alone &
wait
read -r m o <<< "$(peak "$TMP/log")"
[ "$m" = 3 ] && ok "a: 9 jobs, at most 3 at once" || bad "a: peak $m jobs at once (want 3)"
[ "$(grep -c '^e ' "$TMP/log")" = 10 ] && ok "a: every job ran" || bad "a: $(grep -c '^e ' "$TMP/log") of 10 jobs ended"
[ "$o" = clean ] && ok "b: the --alone job ran with nothing beside it" || bad "b: a job ran beside the --alone job"

# c: a holder dies by SIGKILL with its token
P2="$TMP/pool2"; mkdir -p "$P2"
python3 -I "$JP" "$P2" 1 -- sleep 30 & holder=$!
sleep 0.5
kill -9 "$holder"; wait "$holder" 2>/dev/null
t0="$(now)"; python3 -I "$JP" "$P2" 1 -- true; t1="$(now)"
[ $(( (t1 - t0) / 1000000 )) -lt 3000 ] && ok "c: a SIGKILLed holder freed its token" || bad "c: waited $(( (t1 - t0) / 1000000 )) ms after the holder died"

# d: no pool / bad size: run at once; usage error 64
out="$(python3 -I "$JP" "$TMP/none" 3 -- echo ran 2>/dev/null)"
[ "$out" = ran ] && ok "d: missing pool dir: the command runs" || bad "d: missing pool dir: got '$out'"
out="$(python3 -I "$JP" "$P" x -- echo ran 2>/dev/null)"
[ "$out" = ran ] && ok "d: bad size: the command runs" || bad "d: bad size: got '$out'"
python3 -I "$JP" "$P" 3 echo ran > "$TMP/u.out" 2>/dev/null; rc=$?
[ "$rc" = 64 ] && [ ! -s "$TMP/u.out" ] && ok "d: no -- : usage error 64, nothing run" || bad "d: usage rc $rc, out '$(cat "$TMP/u.out")'"

# e: wait file + exit code
P3="$TMP/pool3"; mkdir -p "$P3"
python3 -I "$JP" "$P3" 1 -- sh -c ': > "$1"; sleep 2' _ "$TMP/held3" & h=$!
i=0; while [ ! -e "$TMP/held3" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done   # the holder has its slot (a slow start cannot win)
python3 -I "$JP" "$P3" 1 --wait-file "$TMP/w" -- sh -c 'exit 7'; rc=$?
wait "$h"
w="$(cat "$TMP/w" 2>/dev/null)"
[ "$rc" = 7 ] && ok "e: exit code passed through" || bad "e: rc $rc (want 7)"
case "$w" in 1|2|3) ok "e: wait file says ${w}s" ;; *) bad "e: wait file '$w' (want 1–3: the holder's 2 s, whole seconds)" ;; esac

# f: start line only after the slot is held; the command does not get fd 3
P4="$TMP/pool4"; mkdir -p "$P4"; : > "$TMP/start"
python3 -I "$JP" "$P4" 1 -- sleep 2 & h=$!
sleep 0.3
python3 -I "$JP" "$P4" 1 --start-fd 3 --start-line "· start t" -- sh -c 'if : >&3; then echo fd3-open; else echo fd3-closed; fi' 3>>"$TMP/start" > "$TMP/f.out" 2>/dev/null &
w=$!
sleep 0.8
early="$(cat "$TMP/start")"
wait "$h"; wait "$w"
[ -z "$early" ] && ok "f: no start line while the test waits for its slot" || bad "f: start line written while waiting: '$early'"
[ "$(cat "$TMP/start")" = "· start t" ] && ok "f: start line written once the slot is held" || bad "f: start file '$(cat "$TMP/start")'"
[ "$(cat "$TMP/f.out")" = fd3-closed ] && ok "f: the command does not inherit fd 3" || bad "f: command saw fd 3: $(cat "$TMP/f.out")"

[ "$fails" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS ($fails)"; exit 1; }
