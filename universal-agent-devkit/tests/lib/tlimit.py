import os, signal, subprocess, sys, time
# usage: tlimit.py <seconds> <cmd...>. The command runs in its own process group. Past the limit, or when tlimit itself gets
# SIGINT/SIGTERM (Ctrl-C, run_impacted killing a suite), the whole group is stopped (TERM, 1 s, KILL): no orphaned gate keeps its lock/slot (#488).
# #572: the handler runs between bytecodes of the main thread, possibly inside p.wait(timeout=...) holding Popen._waitpid_lock, so it must not
# wait on p itself: it records the signal and forwards it to the group; the main loop below polls with short timeouts and does the stopping.
limit = float(sys.argv[1])
p = subprocess.Popen(sys.argv[2:], start_new_session=True)


def stop_group():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(p.pid, sig)
        except ProcessLookupError:
            break
        except PermissionError:   # macOS refuses a signal to a group that holds a zombie: signal the child itself
            try:
                p.send_signal(sig)
            except OSError:
                pass
        try:
            p.wait(timeout=1)
        except subprocess.TimeoutExpired:
            continue
        try:   # the leader is gone; a grandchild it did not clean up still gets the KILL
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
        break
    try:   # never an unbounded wait: a KILLed group that cannot be reaped must not hold tlimit past its ceiling
        p.wait(timeout=1)
    except subprocess.TimeoutExpired:
        pass


got = []   # signum of the first SIGINT/SIGTERM


def on_signal(signum, _frame):
    if not got:
        got.append(signum)
    try:   # only a signal here, no wait: see #572 above
        os.killpg(p.pid, signum)
    except OSError:
        try:
            p.send_signal(signum)
        except OSError:
            pass


# explicit handlers: a background job of a non-interactive shell inherits SIGINT=ignored, which would swallow Ctrl-C
signal.signal(signal.SIGINT, on_signal)
signal.signal(signal.SIGTERM, on_signal)
deadline = time.monotonic() + limit
rc = None
while rc is None:
    if got:
        stop_group()
        sys.exit(128 + got[0])
    left = deadline - time.monotonic()
    if left <= 0:
        stop_group()
        sys.exit(124)
    try:
        rc = p.wait(timeout=min(0.2, left))
    except subprocess.TimeoutExpired:
        pass
if got:   # the signal ended the child itself; sweep any grandchild it left
    stop_group()
    sys.exit(128 + got[0])
sys.exit(rc)
