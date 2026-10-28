import os, signal, subprocess, sys, time
# usage: tlimit.py <seconds> <cmd...>. The command runs in its own process group. Past the limit, or when tlimit itself gets
# SIGINT/SIGTERM (Ctrl-C, run_impacted killing a suite), the whole group is stopped (TERM, 1 s, KILL): no orphaned gate keeps its lock/slot (#488).
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
    p.wait()


def on_signal(signum, _frame):
    stop_group()
    sys.exit(128 + signum)


# explicit handlers: a background job of a non-interactive shell inherits SIGINT=ignored, which would swallow Ctrl-C
signal.signal(signal.SIGINT, on_signal)
signal.signal(signal.SIGTERM, on_signal)
try:
    rc = p.wait(timeout=limit)
except subprocess.TimeoutExpired:
    stop_group()
    rc = 124
sys.exit(rc)
