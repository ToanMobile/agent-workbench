#!/usr/bin/env python3
"""job_pool.py <dir> <size> [--alone] [--wait-file F] [--start-fd N --start-line TEXT] -- <command> [args...]

One pool of test slots for the run_impacted.sh shards of ONE gate run (04/11): REG-DK-ALL-GATES-01 / -WORKTREE-01 / -REST-01 ran one after
another, though WORKTREE and REST each keep only 1–3 of their JOBS busy (one long test: REST 186 s for 368 test-s, WORKTREE 50 s for 50).
post-fix-gate.py now starts them side by side and hands each the same <dir> and <size> (= one shard's JOBS): the tests of all three
together never run more than <size> at once, as one shard did.

- A test takes <dir>/alone.lock shared, then one free <dir>/tok.<i> (i < size), polling every POLL_S; an --alone test (the timing tests
  run_impacted.sh runs after its pool) takes alone.lock exclusive: no test of any shard runs beside it. fcntl.flock locks die with the
  process, so a killed test never leaves a slot taken.
- The locks are handed to <command> by exec (the fds stay open across it); run_bounded.py then holds them for the test's whole life.
- No pool (missing dir, size not a positive integer, a lock file that cannot be opened): <command> runs at once, with a note on stderr.
  A broken pool never blocks a run.
- <size> is the most slots the pool ever has. <dir>/size (an integer the gate rewrites every few seconds from capacity.test_jobs(), 04/11)
  is how many it has NOW: another gate that starts shrinks it, one that ends grows it back (a pool fixed at its start ran 26 min at
  6 slots while the other gate had long finished). A test starts only while fewer than that many slots are held (counted under
  <dir>/pick.lock, so two waiters never both take the last one); a running test is never stopped. No file / not a number: <size>.
- --wait-file F gets the whole seconds spent waiting, so the runner can leave them out of the test's own duration.
- --start-fd N --start-line TEXT: TEXT goes to fd N once the place is held (run_impacted.sh's `· start <test>`: a test still waiting is not
  running, and the gate's HANG report must not name it), then fd N is closed so <command> never inherits it. A reader that is gone (EPIPE):
  exit 141 and <command> is not started, as the runner's own printf did (nobody wants its result).
- run_bounded.py forks its watchdog after the exec: the watchdog keeps the lock fds until it ends (right after the test's group), so a slot is
  free a moment after its test, never while the test runs.
- Usage error: exit 64, nothing run (run_bounded.py's code: never 2, which a gate under test uses for UNVERIFIED).
"""
import fcntl
import os
import sys
import time

POLL_S = 0.2
USAGE_RC = 64
USAGE = "usage: job_pool.py <dir> <size> [--alone] [--wait-file F] [--start-fd N --start-line TEXT] -- <command> [args...]"


def _allowed(pool: str, size: int) -> int:
    """How many slots the pool has now: <dir>/size clamped to 1..size; <size> when the file is missing or not a number."""
    try:
        with open(os.path.join(pool, "size"), encoding="utf-8") as f:
            n = int(f.read().strip())
    except (OSError, ValueError):
        return size
    return min(max(n, 1), size)


def _take(pool: str, size: int, alone: bool) -> list:
    """The fds holding this test's place: [alone.lock] for --alone, [alone.lock, tok.<i>] otherwise. Raises OSError when a file cannot
    be opened (the caller runs without the pool)."""
    gate = os.open(os.path.join(pool, "alone.lock"), os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(gate, fcntl.LOCK_EX if alone else fcntl.LOCK_SH)
    except OSError:
        os.close(gate)
        raise
    if alone:
        return [gate]
    try:
        pick = os.open(os.path.join(pool, "pick.lock"), os.O_RDWR | os.O_CREAT, 0o600)
    except OSError:
        os.close(gate)
        raise
    try:
        while True:
            free, held = None, 0
            fcntl.flock(pick, fcntl.LOCK_EX)   # count + take as one step: two waiters never both see "one slot left"
            try:
                allowed = _allowed(pool, size)
                for k in range(size):
                    fd = os.open(os.path.join(pool, f"tok.{k}"), os.O_RDWR | os.O_CREAT, 0o600)
                    try:
                        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except OSError:   # held by a running test (BlockingIOError)
                        os.close(fd)
                        held += 1
                        continue
                    if free is None:
                        free = fd
                    else:
                        os.close(fd)   # closing the only fd of a lock releases it
                if free is not None and held < allowed:
                    return [gate, free]
                if free is not None:
                    os.close(free)
            finally:
                fcntl.flock(pick, fcntl.LOCK_UN)
            time.sleep(POLL_S)
    except OSError:
        os.close(gate)
        raise
    finally:
        os.close(pick)


def main(argv: list) -> int:
    if "--" not in argv:
        print(USAGE, file=sys.stderr)
        return USAGE_RC
    cut = argv.index("--")
    opts, cmd = argv[:cut], argv[cut + 1:]
    if len(opts) < 2 or not cmd:
        print(USAGE, file=sys.stderr)
        return USAGE_RC
    pool, size, rest = opts[0], opts[1], opts[2:]
    alone = "--alone" in rest
    vals = {}
    for name in ("--wait-file", "--start-fd", "--start-line"):
        if name in rest:
            i = rest.index(name)
            if i + 1 >= len(rest):
                print(USAGE, file=sys.stderr)
                return USAGE_RC
            vals[name] = rest[i + 1]
    wait_file, start_fd = vals.get("--wait-file", ""), vals.get("--start-fd", "")
    if start_fd and not start_fd.isdigit():
        print(USAGE, file=sys.stderr)
        return USAGE_RC
    t0 = time.monotonic()
    fds = []
    if size.isdigit() and int(size) > 0 and os.path.isdir(pool):
        try:
            fds = _take(pool, int(size), alone)
        except OSError as exc:
            print(f"job_pool.py: pool {pool} unusable ({exc}): the test runs without it", file=sys.stderr)
    else:
        print(f"job_pool.py: no pool (dir {pool!r}, size {size!r}): the test runs without it", file=sys.stderr)
    if wait_file:
        try:
            with open(wait_file, "w", encoding="utf-8") as f:
                f.write(f"{int(time.monotonic() - t0)}\n")
        except OSError as exc:
            print(f"job_pool.py: wait file {wait_file}: {exc}", file=sys.stderr)
    if start_fd:
        try:
            if "--start-line" in vals:
                os.write(int(start_fd), (vals["--start-line"] + "\n").encode("utf-8", "replace"))
        except BrokenPipeError:
            return 141
        except OSError as exc:   # fd not open: the line is lost, the test still runs
            print(f"job_pool.py: start line to fd {start_fd}: {exc}", file=sys.stderr)
        finally:
            try:
                os.close(int(start_fd))
            except OSError:
                pass
    for fd in fds:
        os.set_inheritable(fd, True)
    try:
        os.execvp(cmd[0], cmd)
    except OSError as exc:
        print(f"job_pool.py: cannot run {cmd[0]}: {exc}", file=sys.stderr)
        return 127


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
