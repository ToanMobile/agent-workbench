#!/usr/bin/env python3
"""run_bounded.py <seconds> -- <command> [args...]

Runs <command> with a hard deadline and never leaves it behind. 24/10: run_impacted.sh ran every test as a bare `bash "$1"`; the
FIFO case of test_gate_robustness.sh (a gate under test blocked in open() of a FIFO with no writer) hung, the runner above it went
away, and two post-fix-gate.py processes lived on for 18 h (state S, 0 % CPU) while the other gates waited and reported BUSY.

- The command runs in a session / process group of its own (setsid right before exec): one killpg reaches every process that stays
  in that group. A descendant that calls setsid itself (the suites of a gate under test) is cleaned up by that descendant's parent.
- This helper stays in its caller's process group, so a Ctrl-C or a group SIGTERM aimed at the caller reaches it: it ends the
  command's group, then dies by that same signal (a waiting shell sees the usual "killed by SIGINT").
- A watchdog process, started and settled in a session of its own BEFORE the command exists, ends the command's group when this
  helper dies by a signal it cannot catch (a group SIGKILL aimed at the caller: post-fix-gate's run_in_group TERM-then-KILL and its
  vacuity handler, the board runner's `pkill -9`). It does nothing else.
- The helper's caller dies (even by SIGKILL, its parent pid changes): the group is ended.
- <seconds> elapsed: SIGTERM to the group, SIGKILL after RUN_BOUNDED_GRACE_S (5 s, 0-60: a test's EXIT trap removes its temp dirs on
  TERM), exit code 124 as timeout(1). 0 = no deadline (everything else still applies).
- Otherwise the command's own exit code (128 + n when a signal ended it); background processes it left in its group are ended too
  (TERM, then KILL 0.5 s later if any is still there).
- The reason of every kill goes to stderr, and logging can never stop a cleanup: Python ignores SIGPIPE, so a print to a stderr pipe
  whose reader died (`OUT="$(… 2>&1)"` in the group that was just signalled) raised BrokenPipeError before the group was ended.
- A usage error exits 64: never 2, which a gate under test uses for UNVERIFIED and a caller could take for the command's verdict.
"""
import os
import signal
import subprocess
import sys
import time

POLL_S = 0.2
WATCH_S = 0.5
USAGE_RC = 64
SIGNALS = (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)


def _say(msg: str) -> None:
    """One line to stderr, unbuffered; a closed or broken stderr is ignored (see the module doc)."""
    try:
        os.write(2, (msg + "\n").encode("utf-8", "replace"))
    except OSError:
        pass


def _usage() -> int:
    _say("usage: run_bounded.py <seconds> -- <command> [args...]")
    return USAGE_RC


def _group_alive(pgid: int) -> bool:
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:   # macOS: a group left with only zombies refuses signals (INSTINCT-056); its members are not running
        return True
    return True


def _signal_group(pgid: int, sig, leader=None) -> None:
    try:
        os.killpg(pgid, sig)
    except ProcessLookupError:
        pass
    except PermissionError:   # only zombies left (see _group_alive): signal the leader itself when we still hold it
        if leader is not None:
            try:
                leader.send_signal(sig)
            except OSError:
                pass


def _end_group(pgid: int, grace: float, leader=None) -> None:
    """SIGTERM to the group, SIGKILL to whatever is left after `grace` seconds (a grandchild that ignored TERM included)."""
    if not _group_alive(pgid):
        return
    _signal_group(pgid, signal.SIGTERM, leader)
    end = time.monotonic() + grace
    while time.monotonic() < end and _group_alive(pgid):
        if leader is not None:
            leader.poll()   # reap it: an unreaped zombie leader keeps the group "alive" for the whole grace
        time.sleep(0.05)
    if not _group_alive(pgid):
        return
    _signal_group(pgid, signal.SIGKILL, leader)
    if leader is not None:
        try:
            leader.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass


def _start_watchdog(grace: float) -> tuple:
    """Fork the watchdog and wait until it sits in a session of its own (a group kill aimed at our caller can no longer reach it),
    all before the command exists: no instant is left where the command would run unwatched (OCR, review round 2). stdin/stdout go
    to /dev/null (it must not hold a pipe its caller reads to EOF); it logs through _say only. It learns the command's pgid from a
    pipe the command writes itself before exec, ends that group once this helper is gone, and exits once the group is empty.
    (watchdog pid, write end of the pgid pipe)."""
    helper = os.getpid()
    pg_r, pg_w = os.pipe()
    ready_r, ready_w = os.pipe()
    pid = os.fork()
    if pid:
        os.close(pg_r)
        os.close(ready_w)
        try:
            if not os.read(ready_r, 1):   # b"r" once the watchdog is settled; b"" if it died first
                _say(f"run_bounded: watchdog (pid {pid}) did not start; the command runs without it (deadline and signals still apply)")
        finally:
            os.close(ready_r)
        return pid, pg_w
    try:
        os.close(pg_w)
        os.close(ready_r)
        for s in SIGNALS:
            signal.signal(s, signal.SIG_DFL)
        os.setsid()
        null = os.open(os.devnull, os.O_RDWR)
        os.dup2(null, 0)
        os.dup2(null, 1)
        os.write(ready_w, b"r")
        os.close(ready_w)
        data = b""
        while not data.endswith(b"\n"):   # the command's pgid, written by the command itself before it execs (see main)
            chunk = os.read(pg_r, 32)
            if not chunk:   # EOF: the helper died (or failed) before any command started — nothing to watch
                break
            data += chunk
        pgid = int(data) if data.strip().isdigit() else 0
        while pgid > 1 and _group_alive(pgid):
            if os.getppid() != helper:
                _say(f"run_bounded: watchdog: the helper (pid {helper}) died; ending process group {pgid}")
                _end_group(pgid, grace)
                break
            time.sleep(WATCH_S)
    except BaseException:   # noqa: BLE001 — a forked child must never return into the helper's code
        pass
    os._exit(0)


def _stop_watchdog(pid: int) -> None:
    if pid <= 1:   # kill(0) / kill(-1) would hit our caller's whole group / every process of the user
        return
    try:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    except (ProcessLookupError, ChildProcessError):
        pass


def main(argv) -> int:
    if len(argv) < 3 or argv[1] != "--":
        return _usage()
    try:
        limit = float(argv[0])
    except ValueError:
        return _usage()
    if not limit >= 0:   # negative or NaN
        return _usage()
    cmd = argv[2:]
    try:
        grace = float(os.environ.get("RUN_BOUNDED_GRACE_S", "5"))
    except ValueError:
        grace = 5.0
    if not 0 <= grace <= 60:   # inf would never send KILL, NaN / negative would skip the TERM grace (EXIT traps)
        grace = 5.0
    parent = os.getppid()
    got = []
    for s in SIGNALS:
        # an INT / HUP the caller ignores (nohup) stays ignored for the command too; TERM is always ours to forward
        if s == signal.SIGTERM or signal.getsignal(s) != signal.SIG_IGN:
            signal.signal(s, lambda n, _f: got.append(n))
    try:
        watchdog, to_watchdog = _start_watchdog(grace)
    except OSError as exc:   # fork / pipe refused (EAGAIN, EMFILE on a loaded machine): 127, never a traceback's 1 a caller reads as FAIL
        _say(f"run_bounded: cannot start the watchdog: {exc}")
        return 127

    def _own_group_and_tell_watchdog():   # runs in the command's process after fork, before exec
        os.setsid()
        # A watchdog that already died leaves no reader: subprocess has reset SIGPIPE to default by now, so a bare write would kill
        # the command before exec (OCR). Ignore it for this one write; the command then runs unwatched, and gets SIGPIPE back.
        signal.signal(signal.SIGPIPE, signal.SIG_IGN)
        try:
            os.write(to_watchdog, b"%d\n" % os.getpid())
        except OSError:
            pass
        finally:
            signal.signal(signal.SIGPIPE, signal.SIG_DFL)
            os.close(to_watchdog)

    try:
        child = subprocess.Popen(cmd, preexec_fn=_own_group_and_tell_watchdog, pass_fds=(to_watchdog,))
    except (OSError, subprocess.SubprocessError) as exc:
        _say(f"run_bounded: cannot start {cmd[0]}: {exc}")
        os.close(to_watchdog)
        _stop_watchdog(watchdog)
        return 127
    os.close(to_watchdog)
    start = time.monotonic()
    try:
        while True:
            try:
                rc = child.wait(timeout=POLL_S)   # returns as soon as the command ends (no fixed poll floor per test)
            except subprocess.TimeoutExpired:
                rc = None
            if rc is not None:
                _end_group(child.pid, 0.5)   # background processes it left behind (a `sleep 300 &` nobody killed); none: no delay
                return 128 - rc if rc < 0 else rc
            why, code = None, 0
            if got:
                why, code = f"received signal {got[0]}", -got[0]
            elif os.getppid() != parent:
                why, code = f"its caller (pid {parent}) is gone", 125
            elif limit and time.monotonic() - start >= limit:
                why, code = f"killed after {limit:g}s (deadline)", 124
            if why:
                _say(f"run_bounded: {' '.join(cmd)}: {why}; ending its process group")
                _end_group(child.pid, grace, child)
                if code < 0:   # die by the same signal: a shell waiting on us sees "killed by SIGINT" and stops too
                    _stop_watchdog(watchdog)
                    watchdog = 0
                    signal.signal(-code, signal.SIG_DFL)
                    os.kill(os.getpid(), -code)
                    return 128 - code
                return code
    finally:
        if watchdog:
            _stop_watchdog(watchdog)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
