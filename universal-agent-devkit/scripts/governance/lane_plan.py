#!/usr/bin/env python3
"""lane_plan.py — order parallel agent lanes so the whole batch ends as early as possible.

  lane_plan.py plan <lanes.json> [--slots N] [--json]   the order to start the lanes, with a simulated timeline
  lane_plan.py slots [--jobs-per-lane J] [--quiet]      how many lanes this machine can run at once right now
  lane_plan.py record <id> <minutes> [--kind K]         remember how long a finished lane really took

lanes.json is a list of {"id": "A11", "est_min": 40, "kind": "rules-text", "deps": ["A10"], "risk": "high", "files": ["hooks/x.sh"]};
only "id" is required. A missing est_min is the median of the recorded lanes of the same kind (30 when the lane has no kind or
there is no history). Keep lanes.json outside the repo: a file left in a worktree is swept into the merge.

Why: lanes that start in input order leave the long one for last (the 15/10 batch: the riskiest lane started after the small ones and
was the critical path for five hours) and every lane runs its own test suites, so seven agents at once pushed the load to 37 on a
machine whose tests then crawled. The plan starts, whenever a slot is free, the ready lane with the longest path to the end of the batch
(its own estimate plus the chain that waits for it); a heuristic, so when the listed order happens to end sooner the plan says so and
uses it. `slots` caps the parallelism by the free CPU, never below 1 and never above MAX_SLOTS (the 3-4 agents that run suites at once).

LANE_PLAN_CORES / LANE_PLAN_LOAD override the machine reading, LANE_PLAN_HISTORY the history file (default
<git common dir>/devkit/lane_times.jsonl: shared by every worktree, never tracked, never swept into a merge). Python stdlib
only, 3.9 compatible.
"""
import errno
import json
import math
import os
import stat
import subprocess
import sys
import time

DEFAULT_EST = 30.0
MAX_EST = 1e6       # minutes: a bigger number is a typo (1e308 would also put Infinity in the --json output)
MAX_SLOTS = 4       # the repo's rule: at most 3-4 agents running test suites at once
JOBS_PER_LANE = 4   # a lane that runs the gate starts several test processes of its own
# files every lane touches and git merges as a union: not a reason to warn (matched at the end of a path: the kit sits in a folder)
SHARED = ("tests/impact_map.txt", "tests/lib/test_durations.txt", ".agents/CHECKLIST.md", ".agents/regression_status.json")


def fail(msg):
    sys.stderr.write("lane_plan: %s\n" % msg)
    sys.exit(2)


def _show(value):
    """A short text of any JSON value for a message (str() of a value nested 100000 deep raises RecursionError)."""
    try:
        return str(value)[:40]
    except RecursionError:
        return type(value).__name__


def _num(value, name):
    """A finite number 0..MAX_EST from JSON or the command line; a bool is not a number here (float(True) is 1.0)."""
    shown = _show(value)
    if isinstance(value, bool):
        fail("%s is not a number: %s" % (name, shown))
    try:
        v = float(value)
    except (TypeError, ValueError, OverflowError):   # OverflowError: an integer of 400 digits
        fail("%s is not a number: %s" % (name, shown))
    if not math.isfinite(v) or v < 0 or v > MAX_EST:
        fail("%s must be a finite number between 0 and %d: %s" % (name, MAX_EST, shown))
    return v


def slots(jobs_per_lane=JOBS_PER_LANE):
    """(slots, cores, load): free CPU divided by what one lane uses, between 1 and MAX_SLOTS."""
    cores = int(_num(os.environ.get("LANE_PLAN_CORES", os.cpu_count() or 1), "LANE_PLAN_CORES"))
    if "LANE_PLAN_LOAD" in os.environ:
        load = _num(os.environ["LANE_PLAN_LOAD"], "LANE_PLAN_LOAD")
    else:
        try:
            load = os.getloadavg()[0]
        except (OSError, AttributeError):
            load = 0.0   # no reading: do not throttle on a guess
    free = max(0.0, cores - load)
    return max(1, min(MAX_SLOTS, int(free // max(1, jobs_per_lane)))), cores, load


def history_path():
    if os.environ.get("LANE_PLAN_HISTORY"):
        return os.environ["LANE_PLAN_HISTORY"]
    try:
        r = subprocess.run(["git", "rev-parse", "--git-common-dir"], capture_output=True, text=True, timeout=10)
        common = r.stdout.strip() if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        common = ""
    if not common:
        fail("not in a git repository: name the history file with LANE_PLAN_HISTORY")
    return os.path.join(os.path.abspath(os.path.join(os.getcwd(), common)), "devkit", "lane_times.jsonl")


def _open_regular(path, flags):
    """open(2) that never waits for a peer and refuses anything but a regular file (a FIFO at this path would hang the open: INSTINCT-040)."""
    fd = os.open(path, flags | os.O_NONBLOCK | getattr(os, "O_CLOEXEC", 0))
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise OSError(errno.EINVAL, "not a regular file", path)
    except BaseException:
        os.close(fd)
        raise
    return fd


def read_history():
    """{kind: [minutes]} - one bad line (not JSON, not UTF-8, a wrong shape, a huge number) is skipped, never fatal."""
    out = {}
    path = history_path()
    try:
        fd = _open_regular(path, os.O_RDONLY)
    except FileNotFoundError:
        return out
    except OSError as e:
        fail("cannot read the history %s: %s" % (path, e))
    try:
        with os.fdopen(fd, "rb") as fh:
            for raw in fh:
                try:
                    r = json.loads(raw.decode("utf-8"))
                    k, m = r["kind"], r["minutes"]
                    m = None if isinstance(m, bool) else float(m)
                except (ValueError, KeyError, TypeError, OverflowError, RecursionError):
                    continue
                if isinstance(k, str) and k and m is not None and math.isfinite(m) and 0 <= m <= MAX_EST:
                    out.setdefault(k, []).append(m)
    except OSError as e:
        fail("cannot read the history %s: %s" % (path, e))
    return out


def median(xs):
    s = sorted(xs)
    n = len(s)
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2.0


def _norm(path):
    return os.path.normpath(path)


def _shared(path):
    return any(path == s or path.endswith("/" + s) for s in SHARED)


def load_lanes(path):
    try:
        with open(path, encoding="utf-8") as fh:
            raw = json.load(fh)
    except (OSError, ValueError, RecursionError) as e:   # RecursionError: JSON nested deeper than the parser reads
        fail("cannot read %s: %s" % (path, e))
    if not isinstance(raw, list) or not raw:
        fail("%s must hold a non-empty list of lanes" % path)
    hist = None   # read only when a lane needs it: a broken history file never blocks a plan whose lanes all carry an estimate
    lanes, seen = {}, []
    for r in raw:
        if not isinstance(r, dict) or not isinstance(r.get("id"), str) or not r["id"]:
            fail("every lane needs a non-empty string id: %s" % _show(r))
        if r["id"] in lanes:
            fail("duplicate lane id %s" % r["id"])
        deps = r.get("deps", [])
        files = r.get("files", [])
        if not isinstance(deps, list) or not all(isinstance(d, str) for d in deps):
            fail("deps of %s must be a list of ids" % r["id"])
        if not isinstance(files, list) or not all(isinstance(f, str) and f.strip() for f in files):
            fail("files of %s must be a list of non-empty paths" % r["id"])
        kind = r.get("kind") if isinstance(r.get("kind"), str) else ""
        if "est_min" in r:
            est = _num(r["est_min"], "est_min of %s" % r["id"])
        else:
            if kind and hist is None:
                hist = read_history()
            est = median(hist[kind]) if kind and kind in hist else DEFAULT_EST
        risk = r.get("risk")
        lanes[r["id"]] = {"id": r["id"], "est": est, "deps": sorted(set(deps)), "files": files,
                          "high": isinstance(risk, str) and risk.lower() == "high"}
        seen.append(r["id"])
    for l in lanes.values():
        for d in l["deps"]:
            if d not in lanes:
                fail("lane %s waits for unknown lane %s" % (l["id"], d))
    # longest path from each lane to the end of the batch, in topological order (no recursion: a long chain must not hit the limit)
    succ = dict((i, []) for i in seen)
    waiting = {}
    for i in seen:
        waiting[i] = len(lanes[i]["deps"])
        for d in lanes[i]["deps"]:
            succ[d].append(i)
    order, free = [], [i for i in seen if waiting[i] == 0]
    while free:
        i = free.pop()
        order.append(i)
        for j in succ[i]:
            waiting[j] -= 1
            if waiting[j] == 0:
                free.append(j)
    if len(order) != len(seen):
        done = set(order)
        fail("dependency cycle through %s" % ", ".join(i for i in seen if i not in done))
    for i in reversed(order):
        after = [lanes[j]["tail"] for j in succ[i]]
        lanes[i]["tail"] = lanes[i]["est"] + (max(after) if after else 0.0)
    return [lanes[i] for i in seen]


def simulate(lanes, n, key):
    """List scheduling on n slots: whenever a slot is free start the ready lane that sorts first by key. -> (rows, makespan).
    Every lane that ends at the moment time moves to is done BEFORE the next start is chosen: a lane that waited for two of them
    must compete for the freed slots with the others, not after a shorter lane took one."""
    done, running, rows, t = {}, [], [], 0.0
    pending = list(lanes)
    while pending or running:
        ready = [l for l in pending if all(d in done for d in l["deps"])]
        while ready and len(running) < n:
            ready.sort(key=key)
            l = ready.pop(0)
            pending.remove(l)
            running.append((t + l["est"], l["id"]))
            rows.append({"id": l["id"], "start": t, "end": t + l["est"]})
        running.sort()
        t = running[0][0]
        while running and running[0][0] <= t:
            done[running.pop(0)[1]] = t
    return rows, max(r["end"] for r in rows)


def overlaps_of(lanes):
    """{path: [lane ids]} for lanes that edit the same file or one inside a folder another names; the union-merged files are left out."""
    owned = []
    for l in lanes:
        for f in sorted(set(_norm(f) for f in l["files"])):
            if not _shared(f):
                owned.append((f, l["id"]))
    out = {}
    for a in range(len(owned)):
        for b in range(a + 1, len(owned)):
            (fa, ia), (fb, ib) = owned[a], owned[b]
            if ia != ib and (fa == fb or fa.startswith(fb + "/") or fb.startswith(fa + "/")):
                ids = out.setdefault(fa if len(fa) <= len(fb) else fb, [])
                for i in (ia, ib):
                    if i not in ids:
                        ids.append(i)
    return out


def plan(path, n_slots, as_json):
    lanes = load_lanes(path)
    n = n_slots if n_slots else slots()[0]
    pos = dict((l["id"], i) for i, l in enumerate(lanes))
    rows, span = simulate(lanes, n, key=lambda l: (-l["tail"], not l["high"], -l["est"]))
    naive_rows, naive = simulate(lanes, n, key=lambda l: pos[l["id"]])
    order = "critical-path"
    if naive < span:   # the longest-path rule is a heuristic: when the listed order ends sooner, use it and say so
        rows, span, order = naive_rows, naive, "input"
    overlaps = overlaps_of(lanes)
    merge_order = [r["id"] for r in sorted(rows, key=lambda r: r["end"])]   # stable: lanes that end together keep their start order
    if as_json:
        print(json.dumps({"slots": n, "order": order, "start_order": [r["id"] for r in rows], "rows": rows, "makespan_min": span,
                          "input_order_makespan_min": naive, "merge_order": merge_order, "overlaps": overlaps}, indent=1))
        return
    print("slots %d (machine now: %s)" % (n, "%d cores, load %.1f" % slots()[1:] if not n_slots else "set by --slots"))
    print("%-24s %8s %8s %8s" % ("start order", "start", "end", "est"))
    est = dict((l["id"], l["est"]) for l in lanes)
    for r in rows:
        print("%-24s %7.0fm %7.0fm %7.0fm" % (r["id"], r["start"], r["end"], est[r["id"]]))
    print("batch ends after %.0f min; the same lanes in input order: %.0f min" % (span, naive))
    if order == "input":
        print("the listed order ends sooner than the longest-path rule here: start the lanes in the order they are listed")
    print("merge order (earliest finished first): %s" % " ".join(merge_order))
    for f, ids in sorted(overlaps.items()):
        print("WARNING %s is edited by %s: the later merge conflicts, keep one owner" % (f, ", ".join(ids)))
    print("then ONE full gate on the merged result: python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --diff origin/<branch>")


def record(lane_id, minutes, kind):
    m = _num(minutes, "minutes")
    p = history_path()
    line = (json.dumps({"id": lane_id, "kind": kind, "minutes": m, "at": int(time.time())}) + "\n").encode("utf-8")
    try:
        os.makedirs(os.path.dirname(os.path.abspath(p)), exist_ok=True)
        fd = _open_regular(p, os.O_WRONLY | os.O_APPEND | os.O_CREAT)
        try:
            os.write(fd, line)   # one write: two lanes recording at once never interleave a line
        finally:
            os.close(fd)
    except OSError as e:
        fail("cannot record to %s: %s" % (p, e))
    print("recorded %s: %.0f min (%s)" % (lane_id, m, kind or "no kind"))


def opt(args, name, default=None):
    if name in args:
        i = args.index(name)
        if i + 1 >= len(args):
            fail("%s needs a value" % name)
        v = args[i + 1]
        del args[i:i + 2]
        return v
    return default


def main(argv):
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    cmd, args = argv[0], list(argv[1:])
    if cmd == "plan":
        n = opt(args, "--slots")
        as_json = "--json" in args
        args = [a for a in args if a != "--json"]
        if len(args) != 1:
            fail("plan takes one lanes.json")
        if n is not None:
            n = _num(n, "--slots")
            if n < 1 or n != int(n):
                fail("--slots must be a whole number >= 1")
            n = int(n)
        plan(args[0], n, as_json)
        return 0
    if cmd == "slots":
        j = _num(opt(args, "--jobs-per-lane", JOBS_PER_LANE), "--jobs-per-lane")
        if j < 1 or j != int(j):
            fail("--jobs-per-lane must be a whole number >= 1")
        quiet = "--quiet" in args
        if [a for a in args if a != "--quiet"]:
            fail("slots takes only --jobs-per-lane J and --quiet")
        s, cores, load = slots(int(j))
        print(s if quiet else "slots=%d cores=%d load=%.1f jobs_per_lane=%d" % (s, cores, load, j))
        return 0
    if cmd == "record":
        kind = opt(args, "--kind", "")
        if len(args) != 2:
            fail("record takes <id> <minutes>")
        record(args[0], args[1], kind)
        return 0
    fail("unknown command %s (plan | slots | record)" % cmd)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
