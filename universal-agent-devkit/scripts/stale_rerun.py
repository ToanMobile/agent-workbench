#!/usr/bin/env python3
"""
stale_rerun.py — re-run the regression suites whose PASS went STALE (code changed since the
run), in the background at session start, so "🟡 CẦN CHẠY LẠI" clears without anyone asking.

  stale_rerun.py <project> [--wait]

Rules that keep it honest and cheap:
  - only a matrix the Stop gate trusts (hooks/regression_gate.sh probe: committed, or
    byte-identical to `agent-kit matrix`) — an edited matrix could run anything
  - only light suites: a command naming Gradle, Unity or xcodebuild waits for the nightly job
  - a time budget for the whole pass (STALE_RERUN_BUDGET_S, default 120 s)
  - each run is real: its result and evidence log are recorded like the gate's
  - a watched file that changes while the suite runs → the result is thrown away (it tested
    neither the old nor the new code); the row stays STALE
  - one pass at a time per project; STALE_RERUN=0 turns it off
Without --wait the pass detaches and returns at once. 100% standard library.
"""

from __future__ import annotations

import contextlib
import fnmatch
import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

DEVKIT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(DEVKIT / "bin"))
sys.dont_write_bytecode = True
import regression_checklist as rc  # noqa: E402

HEAVY = re.compile(r"gradlew|\bgradle\b|unity|-runTests|xcodebuild", re.I)


def is_light(command: str | None) -> bool:
    return bool(command) and not HEAVY.search(command)


def matrix_trusted(project: Path) -> bool:
    """Ask the Stop gate itself (its probe runs no test) whether it trusts the matrix."""
    gate = DEVKIT / "hooks" / "regression_gate.sh"
    try:
        r = subprocess.run(["bash", str(gate)], input="{}", capture_output=True, text=True, timeout=30,
                           env={**os.environ, "REGRESSION_GATE_PROBE": "1", "CLAUDE_PROJECT_DIR": str(project)})
        return json.loads((r.stdout.strip().splitlines() or ["{}"])[-1]).get("state") == "trusted"
    except (OSError, ValueError, subprocess.SubprocessError):
        return False


def candidates(project: Path) -> list:
    """(id, command, watch patterns) of the STALE suites with a light command."""
    with rc.locked(project):
        data = rc.load(project)
        rc.mark_stale(data, project)
    return [(tid, it.get("command"), list(it.get("watch_files", [])) + list(it.get("covers", [])))
            for tid, it in sorted(data["items"].items())
            if it.get("kind") == "test" and rc.effective_status(data, it) == "STALE" and is_light(it.get("command"))]


def watched_mtimes(project: Path, pats: list) -> dict:
    files = (rc._git_lines(project, "ls-files") or []) + \
            (rc._git_lines(project, "ls-files", "--others", "--exclude-standard") or [])
    out = {}
    for f in files:
        if any(fnmatch.fnmatch(f, p) for p in pats):
            try:
                out[f] = (project / f).stat().st_mtime_ns
            except OSError:
                out[f] = None
    return out


def _execute(project: Path, cmd: str, timeout: float) -> tuple:
    proc = subprocess.Popen(cmd, shell=True, cwd=str(project), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, errors="replace", start_new_session=True)
    try:
        out, _ = proc.communicate(timeout=max(1.0, timeout))
        return ("PASS" if proc.returncode == 0 else "FAIL"), proc.returncode, out or ""
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        return "TIMEOUT", None, proc.communicate()[0] or ""


# Twins of bin/post-fix-gate.py INFRA_FAILURE_RE / TEST_RUN_LOCK (keep them in step): a run
# that lost Gradle's results store (two Gradle runs in one tree) is infrastructure, never FLAKY;
# and one suite run at a time per project tree, whichever DevKit runner starts it.
INFRA_FAILURE_RE = re.compile(
    r"^\s*> java\.io\.EOFException\b|test-results[/\\]\S*binary[/\\]|\bresults(?:-generic)?\.bin\b|"
    r"in-progress-results[\w-]*\.bin|Could not write [^\n]*test-results", re.M)
TEST_RUN_LOCK = "test_run.lock"


@contextlib.contextmanager
def test_run_lock(project: Path, deadline: float):
    """The per-project test-run flock (.claude/audit-gate/test_run.lock), waited for until
    `deadline` (time.monotonic()). Yields held: False = another run kept it past the deadline
    (BUSY — do not run)."""
    import fcntl
    state = project / ".claude" / "audit-gate"
    try:
        state.mkdir(parents=True, exist_ok=True)
        if not (state / ".gitignore").exists():
            (state / ".gitignore").write_text("*\n", encoding="utf-8")
        fh = open(state / TEST_RUN_LOCK, "w")
    except OSError:
        yield True  # cannot make the lock file: never worse than no lock
        return
    with fh:
        while True:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() >= deadline:
                    yield False
                    return
                time.sleep(0.2)
        yield True


def run_one(project: Path, tid: str, cmd: str, pats: list, timeout: float, *, mode: str = "stale-rerun",
            retry: bool = False) -> str:
    """Run one suite for real and record it (result + evidence), unless a watched file
    changed while it ran. retry: a FAIL is re-run once; green then = flaky (stays FAIL).
    A run that lost its results store (INFRA_FAILURE_RE) is re-run whatever `retry` says.
    The wait for the project's test-run lock comes out of `timeout`: held past it → BUSY,
    nothing run or recorded."""
    deadline = time.monotonic() + timeout
    with test_run_lock(project, deadline) as held:
        if not held:
            return f"{tid}: BUSY — một lượt chạy test khác đang giữ khoá dự án — chạy lại sau"
        waited = timeout - (deadline - time.monotonic()) > 1.0   # the lock wait took part of the budget
        before = watched_mtimes(project, pats)
        started = time.perf_counter()
        status, code, out = _execute(project, cmd, deadline - time.monotonic())
        if status == "TIMEOUT" and waited:
            # Out of time only because another run held the lock: that measured the wait, not
            # the code. Never record it as a red TIMEOUT (nightly would report "turned red").
            return f"{tid}: bỏ kết quả — hết thời gian vì phải chờ khoá chạy test"
        flaky = infra = False
        broke = status == "FAIL" and bool(INFRA_FAILURE_RE.search(out))
        if status == "FAIL" and ((broke and os.environ.get("INFRA_RETRY", "1") != "0")
                                 or (retry and not broke and os.environ.get("FLAKY_RETRY", "1") != "0")):
            st2, code2, out2 = _execute(project, cmd, max(1.0, deadline - time.monotonic()))
            first = out
            out += f"\n# --- chạy lại 1 lần ({'INFRA_RETRY' if broke else 'FLAKY_RETRY'}) — exit {code2} ---\n{out2}"
            if st2 == "PASS" and (broke or not rc.test_failure_reported(first)):
                status, code, infra = "PASS", 0, True   # build broke, the re-run ran green: a real PASS
            elif not broke:
                flaky = st2 == "PASS"
        after = watched_mtimes(project, pats)
    duration = f"{time.perf_counter() - started:.2f}s"
    if after != before:
        return f"{tid}: bỏ kết quả — file được canh đổi trong lúc chạy"
    t = {"id": tid, "status": status, "exit_code": code, "duration": duration, "mode": mode, "flaky": flaky,
         "infra_retry": infra}
    t["log"] = rc.write_evidence(project, tid, out, {"command": cmd, "mode": mode, "status": status,
                                                     "exit": code, "duration": duration})
    head = (rc._git_lines(project, "rev-parse", "--short", "HEAD") or [""])[0] or None
    dirty = bool(rc._git_lines(project, "status", "--porcelain"))
    with rc.locked(project):
        data = rc.load(project)
        rc.record_results(data, [t], task=mode, commit=f"{head}+dirty" if head and dirty else head)
        rc.save(project, data)
    return f"{tid}: {status} ({duration})"


def main(argv=None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    wait = "--wait" in args
    args = [a for a in args if a != "--wait"]
    project = Path(args[0] if args else os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()).resolve()
    if os.environ.get("STALE_RERUN", "1") == "0" or not (project / rc.STATUS_FILE).is_file():
        return 0
    if not wait:   # detach: SessionStart must not wait for tests
        subprocess.Popen([sys.executable, __file__, str(project), "--wait"], cwd=str(project),
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return 0
    import fcntl
    state_dir = project / ".claude" / "audit-gate"
    state_dir.mkdir(parents=True, exist_ok=True)
    with open(state_dir / "stale_rerun.lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return 0       # another pass is running for this project
        if not matrix_trusted(project):
            print("ma trận chưa được gate tin — không chạy lại gì")
            return 0
        try:
            budget = float(os.environ.get("STALE_RERUN_BUDGET_S", "120"))
        except ValueError:
            budget = 120.0
        deadline = time.monotonic() + budget
        for tid, cmd, pats in candidates(project):
            left = deadline - time.monotonic()
            if left <= 1:
                break
            print(run_one(project, tid, cmd, pats, left))
    return 0


if __name__ == "__main__":
    sys.exit(main())
