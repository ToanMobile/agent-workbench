#!/usr/bin/env bash
# Regression test: `agent-kit test` runs the suites that come BEFORE the parallel pool (hook contract tests, hook
# contract facts, workflow tests: ~80 s one after another) BESIDE the pool (`run_impacted.sh --all`, ~160 s), and that
# changes NOTHING a caller can see: the same text, in the same order, the same exit code (any failing part = 1,
# exactly as the old `|| exit 1` chain), the same env knobs, death by the signal that interrupted it. Only the wall time drops.
# Every check runs a COPY of bin/agent-kit in a fixture kit of stub suites that sleep, record when they ran and exit
# 0 or 1 (never the real suites). Group A (exit codes, text, order, env) and the signal exit codes of B4 must hold for the
# old serial code too: they are what the speed-up must not change. B (overlap, nothing left after a stop, SIGQUIT included), C (the
# runner holds its timing tests back, and stops by itself when its parent was SIGKILLed: C5) and D (the real runner killed in mid-run
# leaves no temp dir) are what the speed-up adds.
# bash 3.2 compatible.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
unset DEVKIT_GATE_DONE DEVKIT_TEST_JOBS DEVKIT_TEST_CORES DEVKIT_IMPACT_TEST_CHANGED CONTRACT_FACTS_SKIP_HARNESS DEVKIT_ALONE_AFTER_FILE
TMP="$(mktemp -d)"
# BEFORE the trap: an empty $TMP (mktemp failed) would make its `pkill -f -- "$TMP/"` a `pkill -f -- /`, SIGTERM for nearly every process
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
# a stub still sleeping when this test ends (a broken agent-kit leaves them) is found by the unique fixture path
trap 'pkill -f -- "$TMP/" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

# ── helpers (python: float timestamps, process table, signals, a bounded run) ───────────────────────────────────
cat > "$TMP/tools.py" <<'PY'
import os, signal, subprocess, sys, time

def read_log(path):
    out = {}
    try:
        for line in open(path):
            f = line.split()
            if len(f) >= 3 and f[0] in ("START", "END"):
                out.setdefault(f[1], {})[f[0]] = float(f[2])
    except OSError:
        pass
    return out

def overlap(log, a, b):
    x, y = read_log(log).get(a, {}), read_log(log).get(b, {})
    return int("START" in x and "START" in y and "END" in x and "END" in y
               and x["START"] < y["END"] and y["START"] < x["END"])

def leftovers(path):
    me = {os.getpid(), os.getppid()}
    ps = subprocess.run(["ps", "-axo", "pid=,command="], capture_output=True, text=True).stdout
    return [l.strip() for l in ps.splitlines() if path in l and int(l.split()[0]) not in me]

def wait_gone(path, secs):
    end = time.time() + secs
    while time.time() < end:
        if not leftovers(path):
            return True
        time.sleep(0.1)
    return not leftovers(path)

def default_signals():
    for n in ("SIGINT", "SIGQUIT", "SIGPIPE", "SIGXFSZ", "SIGHUP"):   # SIGHUP: ignored when this test runs under nohup, and an ignored signal survives an exec
        if hasattr(signal, n):
            signal.signal(getattr(signal, n), signal.SIG_DFL)

cmd = sys.argv[1]
if cmd == "exec":                          # tools.py exec cmd...: the command with the default INT/QUIT/PIPE whatever this test inherited
    default_signals()
    os.execvp(sys.argv[2], sys.argv[2:])
elif cmd == "overlap":                       # tools.py overlap LOG A B...: how many of B... run at the same time as A
    log, a = sys.argv[2], sys.argv[3]
    print(sum(overlap(log, a, b) for b in sys.argv[4:]))
elif cmd == "before":                      # tools.py before LOG A B: 1 when A ended before B started
    log, a, b = sys.argv[2:5]
    d = read_log(log)
    print(int(a in d and b in d and "END" in d[a] and "START" in d[b] and d[a]["END"] <= d[b]["START"]))
elif cmd == "leftovers":                   # tools.py leftovers PATH [SECS]: wait for no process of the fixture, print what stays
    wait_gone(sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 0)
    for l in leftovers(sys.argv[2]):
        print(l)
elif cmd == "signal":                      # tools.py signal KIT LOG SIGNAL group|pid: start agent-kit test, signal it once it runs
    kit, log, sig, mode = sys.argv[2:6]
    pool_wait = 40 if len(sys.argv) > 6 and sys.argv[6] == "pool" else 5   # how long to give the pool to start before the signal
    def started(n):
        try:
            return ("START %s " % n) in open(log).read()
        except OSError:
            return False
    if os.environ.get("TOOLS_IGNORE_HUP"):   # a caller under nohup: SIGHUP is ignored here, and what is ignored survives an exec
        signal.signal(signal.SIGHUP, signal.SIG_IGN)
    with open(kit + "/sig.out", "w") as o, open(kit + "/sig.err", "w") as e:
        p = subprocess.Popen(["bash", kit + "/bin/agent-kit", "test"], stdin=subprocess.DEVNULL, stdout=o, stderr=e,
                             start_new_session=True, preexec_fn=default_signals)   # its own session, like a terminal's foreground group
        end = time.time() + 60
        while time.time() < end and not started("hook_contract"):
            time.sleep(0.05)
        ran = started("hook_contract")
        end = time.time() + pool_wait                   # beside it the pool starts within moments (the serial code never starts it)
        while time.time() < end and not started("pool"):
            time.sleep(0.05)
        if mode == "group":
            os.killpg(p.pid, getattr(signal, sig))   # what ^C does: the whole foreground process group
        else:
            os.kill(p.pid, getattr(signal, sig))
        try:
            rc = p.wait(timeout=60)   # it must stop at once: the suites it started sleep 150 s, so waiting for them is "hung"
        except subprocess.TimeoutExpired:
            rc = "hung"
            os.killpg(p.pid, signal.SIGKILL)
    print("rc=%s started=%s" % (rc, int(ran)))
elif cmd == "orphan":                      # tools.py orphan RUNNER LOG: SIGKILL the process that started the runner; did the runner stop?
    runner, log = sys.argv[2:4]
    env = dict(os.environ, DEVKIT_ALONE_AFTER_FILE=runner + "/never")   # a file nobody creates: what `agent-kit test` leaves behind when killed
    parent = subprocess.Popen(["bash", "-c", 'bash "$1/tests/run_impacted.sh" --all </dev/null >/dev/null 2>&1 & echo $!; wait', "_", runner],
                              cwd=runner, env=env, stdout=subprocess.PIPE, text=True, start_new_session=True)
    kid = int(parent.stdout.readline())
    def seen(n):
        try:
            return ("START %s " % n) in open(log).read()
        except OSError:
            return False
    end = time.time() + 60
    while time.time() < end and not (seen("p1") and seen("p2")):   # its parallel tests have run: it is in the wait for the timing tests now
        time.sleep(0.05)
    os.kill(parent.pid, signal.SIGKILL)                           # no trap can run: only the runner itself can notice
    parent.wait()
    def alive(pid):
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False
    end = time.time() + 40
    while time.time() < end and alive(kid):
        time.sleep(0.2)
    gone = int(not alive(kid))
    if not gone:
        os.kill(kid, signal.SIGKILL)                               # the old code waits up to 900 s: do not leave it behind
    print("gone=%d timing_test_ran=%d" % (gone, int(seen("budgets"))))
elif cmd == "timed":                       # tools.py timed SECS cmd...: "rc=N secs=S" (rc=hung when it ran past SECS: it is killed then)
    t0 = time.time()
    p = subprocess.Popen(sys.argv[3:], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True, preexec_fn=default_signals)
    try:
        rc = p.wait(timeout=float(sys.argv[2]))
    except subprocess.TimeoutExpired:
        rc = "hung"
        os.killpg(p.pid, signal.SIGKILL)
        p.wait()
    print("rc=%s secs=%.0f" % (rc, time.time() - t0))
elif cmd == "ttyint":                      # tools.py ttyint KIT: agent-kit test on a TERMINAL whose pool reads that terminal, then ^C
    import pty, select
    kit = sys.argv[2]
    try:
        pid, fd = pty.fork()               # the child is a session leader with the pty as controlling terminal: what a shell window is
    except OSError:                        # a sandbox without pseudo-terminals: there is nothing to check here
        print("rc=skip stopped=0")
        sys.exit(0)
    if pid == 0:
        default_signals()
        os.execvp("bash", ["bash", kit + "/bin/agent-kit", "test"])
    def table():                           # (pid, pgid, stat) of every process of the fixture
        ps = subprocess.run(["ps", "-axo", "pid=,pgid=,stat=,command="], capture_output=True, text=True).stdout
        return [l.split(None, 3) for l in ps.splitlines() if (kit + "/") in l]
    def drain(secs):
        r, _, _ = select.select([fd], [], [], secs)
        if r:
            try:
                os.read(fd, 4096)
            except OSError:
                pass
    end = time.time() + 40
    stopped = []
    while time.time() < end and not stopped:   # the pool reads the terminal from the background: SIGTTIN stops its group (state T)
        drain(0.2)
        stopped = [int(r[1]) for r in table() if r[2].startswith("T")]
    time.sleep(0.5)
    os.write(fd, b"\x03")                   # ^C: the terminal sends SIGINT to the foreground group, which is agent-kit's
    end = time.time() + 20
    rc = "hung"
    while time.time() < end:
        drain(0.1)
        wp, st = os.waitpid(pid, os.WNOHANG)
        if wp:
            rc = -os.WTERMSIG(st) if os.WIFSIGNALED(st) else os.WEXITSTATUS(st)
            break
    if rc == "hung":                       # SIGKILL reaches a stopped group too
        for g in set(stopped) | {pid}:
            try:
                os.killpg(g, signal.SIGKILL)
            except OSError:
                pass
        os.waitpid(pid, 0)
    print("rc=%s stopped=%d" % (rc, int(bool(stopped))))
elif cmd == "bounded":                     # tools.py bounded SECS cmd...: rc of the command, 124 when it ran past SECS
    try:
        print(subprocess.run(sys.argv[3:], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             timeout=float(sys.argv[2])).returncode)
    except subprocess.TimeoutExpired:
        print(124)
PY
T() { python3 -I "$TMP/tools.py" "$@"; }

# ── the fixture kit: agent-kit under test + stub suites ─────────────────────────────────────────────────────────────
cat > "$TMP/stub.py" <<'PY'
import os, sys, time
name = sys.argv[1]
def rec(*f):
    with open(os.environ["STUB_LOG"], "a") as fh:
        fh.write(" ".join(str(x) for x in f) + "\n")
rec("START", name, "%.4f" % time.time())
rec("ARGS", name, *sys.argv[2:])
rec("ENV", name, "FACTS=" + os.environ.get("CONTRACT_FACTS_SKIP_HARNESS", "-"), "JOBS=" + os.environ.get("DEVKIT_TEST_JOBS", "-"))
af = os.environ.get("DEVKIT_ALONE_AFTER_FILE", "")   # the file the real runner waits for before its timing tests
def seen():
    return "set=%d exists=%d" % (1 if af else 0, 1 if af and os.path.exists(af) else 0)
rec("ALONE_START", name, seen())
import select
rec("STDIN", name, "bytes=%d" % (len(os.read(0, 100)) if select.select([0], [], [], 0)[0] else -1))   # -1: nothing to read yet
import signal
rec("PROC", name, "leader=%d" % (os.getpgrp() == os.getpid()),   # its own process group (what one kill reaches)
    "int=%s" % ("ignored" if signal.getsignal(signal.SIGINT) == signal.SIG_IGN else "default"),   # a background bash job starts with these two ignored
    "quit=%s" % ("ignored" if signal.getsignal(signal.SIGQUIT) == signal.SIG_IGN else "default"))
time.sleep(float(os.environ.get("STUB_SLEEP_" + name, "0.3")))
sys.stdout.write("out-%s\n" % name); sys.stdout.flush()
sys.stderr.write("err-%s\n" % name); sys.stderr.flush()
rc = int(os.environ.get("STUB_RC_" + name, "0"))
rec("ALONE_END", name, seen())
rec("END", name, "%.4f" % time.time(), rc)
sys.exit(rc)
PY
cat > "$TMP/probe.sh" <<'SH'
# what a bash pipeline sees of SIGPIPE here: `yes` dies of it (141) unless it was set to ignored (then `yes` fails with 1)
yes 2>/dev/null | head -1 > /dev/null; echo "PIPE $1 ${PIPESTATUS[0]}" >> "$STUB_LOG"
SH
mk_kit() { # <dir>: bin/agent-kit (the real one) and one stub per suite it runs
  local k="$1"
  mkdir -p "$k/bin" "$k/hooks/tests" "$k/workflows" "$k/tests" "$k/stubbin" "$k/tmp"
  cp "$DEVKIT_DIR/bin/agent-kit" "$k/bin/agent-kit"; cp "$TMP/stub.py" "$k/stub.py"
  printf '#!/bin/bash\n. "%s/probe.sh" hook_contract\nexec python3 "%s/stub.py" hook_contract "$@"\n' "$TMP" "$k" > "$k/hooks/tests/hook_contract_test.sh"
  printf '#!/bin/bash\nexec python3 "%s/stub.py" or_ported "$@"\n'      "$k" > "$k/hooks/tests/or_ported_contract_test.sh"
  printf '#!/bin/bash\nexec python3 "%s/stub.py" contract_facts "$@"\n' "$k" > "$k/hooks/tests/contract_facts_test.sh"
  printf '#!/bin/bash\nexec python3 "%s/stub.py" node "$@"\n'          "$k" > "$k/stubbin/node"
  printf '#!/bin/bash\n. "%s/probe.sh" pool\nexec python3 "%s/stub.py" pool "$@"\n' "$TMP" "$k" > "$k/tests/run_impacted.sh"
  chmod +x "$k/stubbin/node"; : > "$k/workflows/a.test.mjs"; : > "$k/workflows/b.test.mjs"
}
run_kit() { # <kit> [VAR=value ...] -> OUT ERR RC and $K/log (fresh); TMPDIR is the kit's own tmp/ so leftovers show
  local k="$1"; shift
  : > "$k/log"; rm -rf "$k/tmp"; mkdir -p "$k/tmp"
  # the caller's stdin never runs dry (`yes`): the suites that run in the foreground always see data on it
  ( cd "$TMP" && env STUB_LOG="$k/log" TMPDIR="$k/tmp" PATH="$k/stubbin:$PATH" "$@" python3 -I "$TMP/tools.py" exec bash "$k/bin/agent-kit" test >"$k/out" 2>"$k/err" < <(yes 2>/dev/null) )
  RC=$?; OUT="$(cat "$k/out")"; ERR="$(cat "$k/err")"
}

# What the ORIGINAL serial code printed: five blocks, a part's text only when the chain got that far.
RULE="$(printf '%65s' '' | tr ' ' '=')"
banner() { printf '%s\n  %s\n%s\n' "$RULE" "$1" "$RULE"; }
golden_out() { # <n parts>: stdout through part n (1 hook_contract, 2 or_ported, 3 contract_facts, 4 node, 5 pool)
  local n="$1"
  banner "🧪 Running Hook Contract Tests..."
  [ "$n" -ge 1 ] && echo "out-hook_contract"
  [ "$n" -ge 2 ] && echo "out-or_ported"
  [ "$n" -ge 3 ] && { echo; banner "📋 Running Hook Contract Facts (registries, headers, wiring)..."; echo "out-contract_facts"; }
  [ "$n" -ge 4 ] && { echo; banner "⚡ Running Workflow Engine Tests..."; echo "out-node"; }
  [ "$n" -ge 5 ] && { echo; banner "🧰 Running Installer & Gate Regression Tests..."; echo "out-pool"; }
  return 0
}
golden_err() { # <n parts>: stderr through part n
  local n="$1" names="hook_contract or_ported contract_facts node pool" i=0 x
  for x in $names; do i=$((i + 1)); [ "$i" -le "$n" ] && echo "err-$x"; done
  return 0
}
PARTS="hook_contract or_ported contract_facts node pool"

# ── A: what a caller sees must not change ───────────────────────────────────────────────────────────────────────
K="$TMP/kit"; mk_kit "$K"

run_kit "$K" STUB_SLEEP_pool=0.2
[ "$RC" = 0 ] && ok "A1 every suite passes: exit 0" || fail "A1 exit $RC, not 0"
[ "$OUT" = "$(golden_out 5)" ] && ok "A2 stdout is the five blocks, in the original order, byte for byte" \
  || fail "A2 stdout differs: $(diff <(printf '%s\n' "$OUT") <(golden_out 5) | head -8 | tr '\n' '|')"
[ "$ERR" = "$(golden_err 5)" ] && ok "A3 stderr keeps its own stream, in the original order" \
  || fail "A3 stderr is '$(printf '%s' "$ERR" | tr '\n' '|')'"

i=0
for p in $PARTS; do
  i=$((i + 1))
  run_kit "$K" STUB_RC_$p=1 STUB_SLEEP_pool=0.6
  [ "$RC" = 1 ] && ok "A4.$i $p fails: exit 1" || fail "A4.$i $p fails: exit $RC, not 1"
  [ "$OUT" = "$(golden_out $i)" ] && [ "$ERR" = "$(golden_err $i)" ] && ok "A5.$i $p fails: the output stops right after it, nothing later is printed" \
    || fail "A5.$i $p fails: stdout/stderr differ from the serial run: '$(printf '%s' "$OUT" | tr '\n' '|')' / '$(printf '%s' "$ERR" | tr '\n' '|')'"
  later=""; j=0
  for q in $PARTS; do j=$((j + 1)); [ "$j" -gt "$i" ] && [ "$q" != pool ] && grep -q "^START $q " "$K/log" && later="$later $q"; done
  [ -z "$later" ] && ok "A6.$i $p fails: no later suite of the chain runs" || fail "A6.$i $p fails but these still ran:$later"
  [ -z "$(ls "$K/tmp")" ] && ok "A7.$i $p fails: no temp dir left" || fail "A7.$i $p fails: left $(ls "$K/tmp" | tr '\n' ' ')"
  [ -z "$(T leftovers "$K/" 30)" ] && ok "A8.$i $p fails: no process left" || fail "A8.$i $p fails: left $(T leftovers "$K/" 0 | head -3 | tr '\n' '|')"
done

run_kit "$K" STUB_RC_pool=2 STUB_SLEEP_pool=0.2
[ "$RC" = 1 ] && ok "A9 the pool exits 2: still exit 1, as the \`|| exit 1\` did" || fail "A9 pool exit 2 gave exit $RC"

run_kit "$K" CONTRACT_FACTS_SKIP_HARNESS=0 DEVKIT_TEST_JOBS=7 STUB_SLEEP_pool=0.2
env_of() { grep "^ENV $1 " "$K/log" | head -1; }
[ "$(env_of contract_facts)" = "ENV contract_facts FACTS=1 JOBS=7" ] && [ "$(env_of hook_contract)" = "ENV hook_contract FACTS=0 JOBS=7" ] \
  && [ "$(env_of pool)" = "ENV pool FACTS=0 JOBS=7" ] \
  && ok "A10 env knobs: CONTRACT_FACTS_SKIP_HARNESS=1 only for the facts suite, DEVKIT_TEST_JOBS and the rest reach every suite" \
  || fail "A10 env: $(env_of hook_contract) / $(env_of contract_facts) / $(env_of pool)"
[ "$(grep '^ARGS pool ' "$K/log")" = "ARGS pool --all" ] && [ "$(grep '^ARGS node ' "$K/log")" = "ARGS node --test $K/workflows/a.test.mjs $K/workflows/b.test.mjs" ] \
  && ok "A11 arguments: the pool gets --all, node gets --test and the expanded workflow test files" \
  || fail "A11 args: $(grep '^ARGS \(pool\|node\) ' "$K/log" | tr '\n' '|')"

run_kit "$K" DEVKIT_TEST_JOBS=1 STUB_SLEEP_pool=0.4 STUB_SLEEP_hook_contract=0.3 STUB_SLEEP_or_ported=0.3 STUB_SLEEP_node=0.3
n="$(T overlap "$K/log" pool hook_contract or_ported contract_facts node)"
[ "$RC" = 0 ] && [ "$OUT" = "$(golden_out 5)" ] && [ "$n" = 0 ] && ok "A12 DEVKIT_TEST_JOBS=1 (one at a time) keeps the old serial order: no overlap, same text" \
  || fail "A12 DEVKIT_TEST_JOBS=1: exit $RC, $n suites overlapped the pool (want 0)"
[ "$(grep '^ALONE_START pool ' "$K/log")" = "ALONE_START pool set=1 exists=1" ] \
  && ok "B9 one at a time: the file already exists when the pool starts, so run_impacted.sh never waits" \
  || fail "B9 serial hand-over: $(grep '^ALONE_START pool ' "$K/log")"

# ── B: what the speed-up adds ───────────────────────────────────────────────────────────────────────────────────────
# The pool (sleeps longest) must run at the same time as the earlier suites; those stay one after another. COUNTS of
# overlapping intervals, no absolute seconds: a loaded machine moves every time, not who overlaps whom.
run_kit "$K" STUB_SLEEP_pool=2.5 STUB_SLEEP_hook_contract=0.4 STUB_SLEEP_or_ported=0.3 STUB_SLEEP_contract_facts=0.1 STUB_SLEEP_node=0.4
n="$(T overlap "$K/log" pool hook_contract or_ported contract_facts node)"
[ "$n" -ge 3 ] && ok "B1 the pool overlaps the earlier suites in time ($n of 4)" || fail "B1 the pool overlaps only $n of the 4 earlier suites: they run serially before it"
seq_ok=1; prev=""
for p in hook_contract or_ported contract_facts node; do
  [ -n "$prev" ] && [ "$(T before "$K/log" "$prev" "$p")" != 1 ] && seq_ok=0
  prev="$p"
done
[ "$seq_ok" = 1 ] && ok "B2 the earlier suites still run one after another, in the original order" || fail "B2 the earlier suites overlap each other or run out of order"
[ "$RC" = 0 ] && [ "$OUT" = "$(golden_out 5)" ] && ok "B3 the overlapping run prints the same text" || fail "B3 overlapping run: exit $RC, text differs"
[ "$(grep '^ALONE_START pool ' "$K/log")" = "ALONE_START pool set=1 exists=0" ] && [ "$(grep '^ALONE_END pool ' "$K/log")" = "ALONE_END pool set=1 exists=1" ] \
  && ok "B8 the pool is told which file the earlier suites create when they end, and it exists by then (run_impacted.sh waits for it)" \
  || fail "B8 hand-over: $(grep '^ALONE_' "$K/log" | grep ' pool ' | tr '\n' '|')"
[ "$(grep '^STDIN hook_contract ' "$K/log")" = "STDIN hook_contract bytes=100" ] && [ "$(grep '^STDIN pool ' "$K/log")" = "STDIN pool bytes=0" ] \
  && ok "B10 stdin: the earlier suites keep the caller's, the background pool gets /dev/null (a background group must never wait on the terminal)" \
  || fail "B10 stdin: $(grep '^STDIN \(hook_contract\|pool\) ' "$K/log" | tr '\n' '|')"
proc_of() { grep "^PROC $1 " "$K/log" | cut -d' ' -f3-; }   # "leader=. int=. quit=."
case "$(proc_of pool)|$(proc_of hook_contract)" in
  "leader=1 "*"|leader=0 "*)
    [ "$(proc_of pool | cut -d' ' -f2-)" = "$(proc_of hook_contract | cut -d' ' -f2-)" ] \
      && [ "$(grep '^PIPE pool ' "$K/log" | cut -d' ' -f3)" = "$(grep '^PIPE hook_contract ' "$K/log" | cut -d' ' -f3)" ] \
      && ok "B11 the pool is its own process group, its SIGINT/SIGQUIT/SIGPIPE as the caller handed them down; the earlier suites stay in the caller's group" \
      || fail "B11 the pool's signals differ from the earlier suites': $(proc_of pool) vs $(proc_of hook_contract); $(grep '^PIPE ' "$K/log" | tr '\n' '|')" ;;
  *) fail "B11 process groups: pool '$(proc_of pool)', hook_contract '$(proc_of hook_contract)'" ;;
esac

# What the caller sees of an interrupted run must stay what it was: the process is killed BY the signal (a shell loop
# or script around `agent-kit test` stops on ^C), and nothing it started is left. The pool's tests sleep 150 s, so a missing
# stop shows as "hung" (agent-kit would wait for them) or as left-behind processes. The bounds are wide (a loaded machine).
for spec in "INT group 150" "TERM group 150" "HUP group 150" "HUP group 150 nohup" "QUIT group 150" "TERM pid 3"; do
  set -- $spec; sig="$1"; mode="$2"; nap="$3"; ign="${4:-}"; lbl="SIG$sig ($mode${ign:+, the caller ignores SIGHUP})"
  case "$sig" in INT) num=2 ;; TERM) num=15 ;; HUP) num=1 ;; QUIT) num=3 ;; esac
  : > "$K/log"; rm -rf "$K/tmp"; mkdir -p "$K/tmp"
  res="$( export STUB_LOG="$K/log" TMPDIR="$K/tmp" PATH="$K/stubbin:$PATH" STUB_SLEEP_pool=150 STUB_SLEEP_hook_contract=$nap; [ -n "$ign" ] && export TOOLS_IGNORE_HUP=1; T signal "$K" "$K/log" "SIG$sig" "$mode" )"
  [ "$res" = "rc=-$num started=1" ] && ok "B4 $lbl: agent-kit dies by that signal, at once ($res)" || fail "B4 $lbl: '$res', want rc=-$num started=1"
  left="$(T leftovers "$K/" 30)"
  [ -z "$left" ] && ok "B5 $lbl: no suite process is left running" || fail "B5 $lbl: left behind: $(printf '%s' "$left" | head -3 | tr '\n' '|')"
  [ -z "$(ls "$K/tmp")" ] && ok "B6 $lbl: no temp dir left" || fail "B6 $lbl: left $(find "$K/tmp" | tr '\n' ' ')"
  pkill -f -- "$K/" 2>/dev/null
done
run_kit "$K" STUB_SLEEP_pool=0.2   # and a clean run still works after the signals
[ "$RC" = 0 ] && ok "B7 after the signal runs, a plain run still passes" || fail "B7 plain run after signals: exit $RC"

# ── D: the REAL run_impacted.sh as the pool, stopped in mid-run (an earlier suite failed, ^C, a kill): the pool now starts
# before the earlier suites, so it is killed on every failure of theirs. Its own temp dir and those of its tests (they
# mktemp, and remove it in an EXIT trap) must be gone afterwards: TMPDIR is the fixture's, so any leftover shows.
D="$TMP/kitd"; mk_kit "$D"; cp "$DEVKIT_DIR/tests/run_impacted.sh" "$D/tests/run_impacted.sh"; : > "$D/tests/impact_map.txt"
mkdir -p "$D/tests/gates"; ( cd "$D" && git init -q . )
cat > "$D/tests/gates/test_t1.sh" <<'SH'
d="$(mktemp -d "$TMPDIR/fake.XXXXXX")"; trap 'rm -rf "$d"' EXIT
echo "START pool x" >> "$STUB_LOG"
sleep 150
SH
cp "$D/tests/gates/test_t1.sh" "$D/tests/gates/test_t2.sh"
own_left() { ls "$1/tmp" 2>/dev/null | grep -v '^fake\.'; }   # what agent-kit and run_impacted.sh themselves made, at the moment agent-kit is gone
tmp_settles() { local i; for i in $(seq 1 300); do [ -z "$(ls "$1/tmp" 2>/dev/null)" ] && return 0; sleep 0.1; done; return 1; }
run_kit "$D" STUB_RC_hook_contract=1 STUB_SLEEP_hook_contract=4
if grep -q '^START pool ' "$D/log"; then
  [ "$RC" = 1 ] && [ -z "$(own_left "$D")" ] && tmp_settles "$D" && ok "D1 an earlier suite fails while the real pool runs: exit 1, pool stopped, no temp dir left" \
    || fail "D1 exit $RC, left in tmp: $(find "$D/tmp" | tr '\n' ' ')"
else fail "D1 the pool's tests never started (the check proved nothing)"; fi
for sig in INT TERM; do
  : > "$D/log"; rm -rf "$D/tmp"; mkdir -p "$D/tmp"
  res="$( export STUB_LOG="$D/log" TMPDIR="$D/tmp" PATH="$D/stubbin:$PATH" STUB_SLEEP_hook_contract=150; T signal "$D" "$D/log" "SIG$sig" group pool )"
  if grep -q '^START pool ' "$D/log"; then
    [ -z "$(own_left "$D")" ] && tmp_settles "$D" && ok "D2 SIG$sig while the real pool runs: no temp dir left ($res)" || fail "D2 SIG$sig: left in tmp: $(find "$D/tmp" | tr '\n' ' ')"
  else fail "D2 SIG$sig: the pool's tests never started (the check proved nothing)"; fi
  pkill -f -- "$D/" 2>/dev/null
done

# ── C: tests/run_impacted.sh holds its timing tests back while `agent-kit test`'s earlier suites still run ─────────
# (a copy of the real runner in a kit of fake tests). The parallel tests do NOT wait; the timing tests (test_budgets,
# test_session_context) run alone, so they start only after the file DEVKIT_ALONE_AFTER_FILE names exists. Unset: no wait.
R="$TMP/runner"; mkdir -p "$R/tests/lib" "$R/tests/gates" "$R/tests/context_memory"
cp "$DEVKIT_DIR/tests/run_impacted.sh" "$R/tests/"; : > "$R/tests/impact_map.txt"; ( cd "$R" && git init -q . )
cat > "$TMP/fake.sh" <<'SH'
echo "START $1 $(python3 -c 'import time; print("%.4f" % time.time())')" >> "$R_LOG"
echo "KNOB $1 ${DEVKIT_ALONE_AFTER_FILE-unset}" >> "$R_LOG"
sleep 0.3
SH
mk_fake() { # <relative path> <name>: a fake test that records its start, and what it sees of the knob
  printf '#!/bin/bash\nexec bash "%s/fake.sh" %s\n' "$TMP" "$2" > "$R/$1"
}
mk_fake tests/gates/test_p1.sh p1; mk_fake tests/gates/test_p2.sh p2; mk_fake tests/context_memory/test_budgets.sh budgets
export R_LOG="$TMP/runner.log"
run_runner() { # [VAR=value ...]: run_impacted.sh --all, bounded to 60 s -> RRC, $R_LOG
  : > "$R_LOG"; rm -f "$TMP/marker"
  RRC="$(cd "$R" && T bounded 60 env "$@" bash tests/run_impacted.sh --all)"
}
( sleep 3; python3 -c 'import time; print("MARK marker %.4f" % time.time())' >> "$R_LOG"; : > "$TMP/marker" ) &
MARKER_JOB=$!
run_runner DEVKIT_ALONE_AFTER_FILE="$TMP/marker"
wait "$MARKER_JOB"
mark="$(awk '$1=="MARK"{print $3}' "$R_LOG")"; bud="$(awk '$1=="START"&&$2=="budgets"{print $3}' "$R_LOG")"; p1="$(awk '$1=="START"&&$2=="p1"{print $3}' "$R_LOG")"
[ "$RRC" = 0 ] && ok "C1 with the knob set, run_impacted.sh --all still passes" || fail "C1 exit $RRC"
python3 -I -c 'import sys; m, b, p = map(float, sys.argv[1:]); sys.exit(0 if b >= m and p < m else 1)' "${mark:-0}" "${bud:-0}" "${p1:-0}" \
  && ok "C2 the timing test starts only after the file exists; the parallel tests did not wait for it" \
  || fail "C2 order: marker=$mark budgets=$bud p1=$p1 (budgets must start after the marker, p1 before it)"
[ "$(grep -c '^KNOB .* unset$' "$R_LOG")" = 3 ] && ok "C3 the knob is not handed on to the tests it starts" || fail "C3 a test saw the knob: $(grep '^KNOB' "$R_LOG" | tr '\n' '|')"
run_runner
[ "$RRC" = 0 ] && ok "C4 knob unset: no wait, the run just finishes" || fail "C4 knob unset: run_impacted.sh --all exit $RRC (124 = it waited)"

# C5: the process that started the runner is KILLED (SIGKILL: its trap cannot run, nothing tells the runner), and the file it waits for
# will never exist. The runner must notice that its parent is gone and stop at once, WITHOUT the timing tests, not wait its 900 s.
: > "$R_LOG"
res="$(T orphan "$R" "$R_LOG")"
[ "$res" = "gone=1 timing_test_ran=0" ] && ok "C5 the runner whose parent was killed stops by itself and runs no timing test ($res)" \
  || fail "C5 orphaned runner: '$res' (want gone=1 timing_test_ran=0; gone=0 = still waiting for a file nobody creates)"

# ── E: found by an independent review of the first version ──────────────────────────────────────────────────────────
# E1: a RELATIVE TMPDIR. The file the pool waits for was named relative to the caller's folder, and run_impacted.sh does a `cd` to the
# kit: it never saw the file and waited its 900 s (the old serial code needed no file). The real runner, a timing test, a relative TMPDIR
# (rt, ./rt) in a folder of its own: it must finish in seconds, run the timing test, and leave nothing in that TMPDIR.
E="$TMP/kite"; mk_kit "$E"; cp "$DEVKIT_DIR/tests/run_impacted.sh" "$E/tests/run_impacted.sh"; : > "$E/tests/impact_map.txt"
mkdir -p "$E/tests/gates" "$E/tests/context_memory"; ( cd "$E" && git init -q . )
printf '#!/bin/bash\nexit 0\n' > "$E/tests/gates/test_e1.sh"
printf '#!/bin/bash\necho "BUDGETS ran" >> "$STUB_LOG"\n' > "$E/tests/context_memory/test_budgets.sh"
n=0
for rel in rt ./rt; do
  n=$((n + 1)); w="$E/work$n"; mkdir -p "$w/rt"; : > "$E/log"
  res="$( cd "$w" && STUB_LOG="$E/log" TMPDIR="$rel" PATH="$E/stubbin:$PATH" STUB_SLEEP_hook_contract=0.2 T timed 45 bash "$E/bin/agent-kit" test )"
  secs="${res##*secs=}"
  [ "${res%% *}" = "rc=0" ] && [ "$secs" -lt 40 ] && grep -q '^BUDGETS ran' "$E/log" && [ -z "$(ls "$w/rt")" ] \
    && ok "E1 TMPDIR=$rel (relative): the run finishes ($res), the timing test ran, no temp dir left" \
    || fail "E1 TMPDIR=$rel: '$res' (hung = the pool waits for a file named relative to the wrong folder), timing test ran: $(grep -c '^BUDGETS ran' "$E/log"), left: $(ls "$w/rt" | tr '\n' ' ')"
  pkill -f -- "$E/" 2>/dev/null
done

# E2: ^C on a TERMINAL while the pool reads that terminal. A background group that reads its terminal is stopped (SIGTTIN, state T) and
# a stopped group acts on SIGTERM only when it is continued: agent-kit waited for it for ever and ^C did nothing. (No suite reads the terminal
# today; install.sh does when a menu needs it.) The real runner, one test that reads /dev/tty; ^C must end agent-kit by SIGINT, nothing left.
Tt="$TMP/kitt"; mk_kit "$Tt"; cp "$DEVKIT_DIR/tests/run_impacted.sh" "$Tt/tests/run_impacted.sh"; : > "$Tt/tests/impact_map.txt"
mkdir -p "$Tt/tests/gates"; ( cd "$Tt" && git init -q . )
printf '#!/bin/bash\necho "START pool x" >> "$STUB_LOG"\nread -t 100 -r _x < /dev/tty\necho "END pool x" >> "$STUB_LOG"\n' > "$Tt/tests/gates/test_tty.sh"
: > "$Tt/log"; mkdir -p "$Tt/tmp"
res="$( export STUB_LOG="$Tt/log" TMPDIR="$Tt/tmp" PATH="$Tt/stubbin:$PATH" STUB_SLEEP_hook_contract=150; T ttyint "$Tt" )"
if [ "$res" = "rc=skip stopped=0" ]; then ok "E2 skipped: this machine gives no pseudo-terminal (nothing to check)"
elif [ "$res" = "rc=-2 stopped=1" ]; then ok "E2 ^C while the pool is stopped on the terminal: agent-kit dies by SIGINT at once ($res)"
else fail "E2 ^C with a stopped pool: '$res', want rc=-2 stopped=1 (hung = it waits for a stopped pool; stopped=0 = the check proved nothing)"; fi
left="$(T leftovers "$Tt/" 30)"
[ -z "$left" ] && [ -z "$(ls "$Tt/tmp")" ] && ok "E2 and nothing is left: no process, no temp dir" \
  || fail "E2 left behind: $(printf '%s' "$left" | head -3 | tr '\n' '|') / $(ls "$Tt/tmp" | tr '\n' ' ')"
pkill -f -- "$Tt/" 2>/dev/null

# E3: this test's own clean-up. `TMP="$(mktemp -d)"` is EMPTY when mktemp fails (no space left) and the EXIT trap's `pkill -f -- "$TMP/"` was then
# `pkill -f -- /`: SIGTERM for nearly every process of the user. The test must stop BEFORE it installs that trap. A copy of this very file runs with a
# mktemp that fails and a pkill that only writes down its arguments; it must end at once, with exit 1 and no pkill call.
if [ -z "${AGENT_KIT_ORDER_META:-}" ]; then
  SH3="$TMP/shim3"; mkdir -p "$SH3"
  printf '#!/bin/sh\nexit 1\n' > "$SH3/mktemp"; printf '#!/bin/sh\necho "$*" >> "$KILL_LOG"\nexit 0\n' > "$SH3/pkill"; chmod +x "$SH3/mktemp" "$SH3/pkill"
  : > "$TMP/kill.log"
  res="$( export KILL_LOG="$TMP/kill.log" AGENT_KIT_ORDER_META=1 PATH="$SH3:$PATH"; T timed 20 bash "$DEVKIT_DIR/tests/verification/test_agent_kit_test_order.sh" )"
  [ "${res%% *}" = "rc=1" ] && [ ! -s "$TMP/kill.log" ] \
    && ok "E3 no temp dir (mktemp fails): the test stops at once and calls no pkill ($res)" \
    || fail "E3 mktemp fails: '$res' (want rc=1), pkill was called with: '$(tr '\n' '|' < "$TMP/kill.log")' (an empty \$TMP made it \`pkill -f -- /\`)"
fi

echo
[ "$FAILS" = 0 ] && echo "agent-kit test order: all checks passed" || echo "agent-kit test order: $FAILS FAILED"
exit $((FAILS > 0))
