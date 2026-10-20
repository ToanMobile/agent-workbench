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
if not (DEVKIT / "profiles").is_dir() and (DEVKIT.parent / "profiles").is_dir():
    DEVKIT = DEVKIT.parent
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
        except PermissionError:   # macOS: nhóm còn zombie — gửi cho chính shell (như post-fix-gate _signal_group, review 20/10)
            with contextlib.suppress(OSError):
                proc.kill()
        try:
            return "TIMEOUT", None, proc.communicate(timeout=10)[0] or ""
        except subprocess.TimeoutExpired:   # một tiến trình cháu còn giữ ống output
            with contextlib.suppress(OSError):
                proc.kill()
            return "TIMEOUT", None, "(output cut: a child process still held the output pipe after SIGKILL)"


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


@contextlib.contextmanager
def suite_slots(project: Path, tid: str, cmd: str, held: bool, max_wait=None):
    """P1 (20/10): quyền chạy của suite (bin/heavy_slot.py), như post-fix-gate: nightly và lượt chạy lại STALE từng chạy
    Gradle/Unity mà không xin gì. P1b: theo tải máy, chỉ Unity còn khoá độc quyền. Yields False khi khoá Unity hết giờ chờ: không
    chạy. Trong lúc giữ: SB_HEAVY_SLOT_HELD=1 (khoá độc quyền) hoặc DEVKIT_SLOT_ADVISORY_HELD=1 (chỉ được cho chạy theo
    tải) cho tiến trình suite.
    held False: không lấy gì. max_wait: trần chờ — run_one đang giữ test_run.lock, Stop hook của người dùng chờ khoá đó 45 s."""
    if not held:
        yield True
        return
    try:
        import heavy_slot as hs  # noqa: PLC0415 - bin/ đã ở sys.path
    except ImportError as exc:
        print(f"[stale-rerun] heavy_slot: {exc} — chạy không khoá", file=sys.stderr)
        yield True
        return
    slots = hs.acquire_for_suite(hs.classify(cmd, str(project)), label=f"{project.name}:{tid}", max_wait=max_wait)
    var = "SB_HEAVY_SLOT_HELD" if slots.held else ("DEVKIT_SLOT_ADVISORY_HELD" if slots.advisory else None)
    prev = os.environ.get(var) if var else None
    try:
        if slots.admitted and var:
            os.environ[var] = "1"
        yield slots.admitted
    finally:
        if var and prev is None:
            os.environ.pop(var, None)
        elif var:
            os.environ[var] = prev
        hs.release_suite(slots)


_GATE = []


def _gate_module():
    """bin/post-fix-gate.py nạp như module (như red_proof.py): dùng chung suite_cache_for / suite_cacheable để khoá trùng khoá gate."""
    if not _GATE:
        import importlib.util  # noqa: PLC0415
        spec = importlib.util.spec_from_file_location("post_fix_gate_for_cache", DEVKIT / "bin" / "post-fix-gate.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        _GATE.append(mod)
    return _GATE[0]


def _tree_unchanged(sc, project: Path) -> bool:
    """Nội dung cả cây vẫn là nội dung lúc tính khoá (khoá cả cây chỉ ghi PASS khi đúng như vậy)."""
    gate = _gate_module()
    mod = gate.suite_cache_mod()
    cm = mod.content_map(project) if mod is not None else None
    return cm is not None and mod.tree_digest(cm) == sc.tree_digest


def keyed_context(project: Path, tid: str, cmd: str, matrix=None):
    """(SuiteCache, (khoá chính xác, khoá cả cây), mục suite) để ghi kết quả chạy thật vào sổ khoá dùng chung với gate (P2/P3); None khi
    suite không cache được
    hoặc không dựng được (khi đó run_one chạy và ghi checklist như trước)."""
    try:
        mpath = str(matrix or project / ".agents" / "regression_matrix.active.json")
        with open(mpath, encoding="utf-8") as f:
            rules = json.load(f).get("rules") or []
        test = next((t for r in rules for t in r.get("mandatory_regression_tests") or []
                     if t.get("id") == tid and t.get("command") == cmd), None)
        gate = _gate_module()
        if test is None or not gate.suite_cacheable(test)[0]:
            return None
        items = (rc.load(project).get("items") or {})
        covers = {k: list(v.get("covers") or []) for k, v in items.items()   # như post-fix-gate checklist_covers: chỉ hàng test
                  if isinstance(v, dict) and v.get("kind") == "test" and v.get("covers")}
        sc = gate.suite_cache_for(project, rules, mpath, covers)
        suite = {"id": tid, "command": cmd, "untested_exit": test.get("untested_exit")}
        keys = sc.keys(suite) if sc is not None else (None, None)   # (chính xác, cả cây): run_one chạy lệnh đầy đủ, ghi cả hai
        return (sc, keys, suite) if all(keys) else None
    except Exception as exc:  # noqa: BLE001 - sổ khoá chỉ là phần thêm: run_one vẫn chạy và ghi checklist như cũ
        print(f"[stale-rerun] suite cache {tid}: {exc!r}", file=sys.stderr)
        return None


def run_one(project: Path, tid: str, cmd: str, pats: list, timeout: float, *, mode: str = "stale-rerun",
            retry: bool = False, matrix=None) -> str:
    """Run one suite for real and record it (result + evidence), unless a watched file
    changed while it ran. retry: a FAIL is re-run once; green then = flaky (stays FAIL).
    A run that lost its results store (INFRA_FAILURE_RE) is re-run whatever `retry` says.
    The wait for the project's test-run lock is bounded by `timeout` (held past it → BUSY,
    nothing run or recorded); once held, the suite gets its whole `timeout`, so a TIMEOUT is
    always the suite's own (a job may take up to twice `timeout`)."""
    with test_run_lock(project, time.monotonic() + timeout) as held, suite_slots(project, tid, cmd, held, timeout) as admitted:
        if not held:
            return f"{tid}: BUSY — một lượt chạy test khác đang giữ khoá dự án — chạy lại sau"
        if not admitted:
            return f"{tid}: SLOT — khoá độc quyền (Unity) bận hết thời gian chờ — chạy lại sau"
        deadline = time.monotonic() + timeout
        keyed = keyed_context(project, tid, cmd, matrix)   # khoá TRƯỚC khi chạy (P2): ghi theo khoá chỉ khi sau khi chạy vẫn đúng khoá này
        before = watched_mtimes(project, pats)
        started = time.perf_counter()
        status, code, out = _execute(project, cmd, deadline - time.monotonic())
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
    if keyed:
        sc, keys, suite = keyed
        meta = {"duration": duration, "log": t["log"], "project": project.name[:64],
                "head": (rc._git_lines(project, "rev-parse", "HEAD") or [""])[0] or None, "by": mode}
        try:
            if status != "PASS":
                sc.void(tid)   # mọi không-PASS của lần chạy thật: PASS cũ của suite này hết dùng lại (như gate)
            if status in ("PASS", "FAIL") and not infra:
                # PASS: khoá cả cây chỉ khi cây không đổi trong lúc chạy (như gate); FAIL: mọi khoá
                tree_ok = status == "FAIL" or _tree_unchanged(sc, project)
                msg = sc.record_run(list(keys) if tree_ok else [keys[0]] if keys[0] != keys[1] else [], suite, status, flaky, meta)
                if msg:
                    print(f"[stale-rerun] suite cache: {msg}", file=sys.stderr)
        except Exception as exc:  # noqa: BLE001
            print(f"[stale-rerun] suite cache {tid}: {exc!r}", file=sys.stderr)
    head = (rc._git_lines(project, "rev-parse", "--short", "HEAD") or [""])[0] or None
    dirty = bool(rc._git_lines(project, "status", "--porcelain"))
    with rc.locked(project):
        data = rc.load(project)
        rc.record_results(data, [t], task=mode, commit=f"{head}+dirty" if head and dirty else head,
                          project=project)
        rc.save(project, data)
    return f"{tid}: {status} ({duration})"


def main(argv=None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    wait = "--wait" in args
    args = [a for a in args if a != "--wait"]
    os.environ.setdefault("DEVKIT_SLOT_PRIORITY", "stop")   # P1: chạy nền lúc mở phiên — sau merge/push/interactive ở hàng đợi slot
    # Không chờ tải máy (review 20/10): run_one chờ trong lúc giữ test_run.lock của dự án, Stop gate của người dùng chỉ chờ khoá đó
    # TEST_RUN_LOCK_WAIT_S (45 s) rồi ra BUSY. Lượt chạy lại STALE là việc nền, tải cao thì cứ chạy. nightly.py gọi run_one trực tiếp
    # và vẫn chờ tải (ban đêm không ai chờ khoá).
    os.environ.setdefault("DEVKIT_SLOT_LOAD_WAIT_S", "0")
    project = Path(args[0] if args else os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()).resolve()
    if os.environ.get("STALE_RERUN", "1") == "0" or not (project / rc.STATUS_FILE).is_file():
        return 0
    if rc.skip_bookkeeping(project):   # a LINKED worktree leaves the tracked checklist alone: a re-run could not be recorded
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
