#!/usr/bin/env python3
"""lane_plan.py — order parallel agent lanes so the whole batch ends as early as possible.

  lane_plan.py plan <lanes.json> [--slots N] [--json]   the order to start the lanes, with a simulated timeline
  lane_plan.py slots [--jobs-per-lane J] [--quiet]      how many lanes this machine can run at once right now
  lane_plan.py record <id> <minutes> --kind K           remember how long a finished lane really took (lanes of that kind)

lanes.json is a list of {"id": "A11", "est_min": 40, "kind": "rules-text", "deps": ["A10"], "risk": "high", "files": ["hooks/x.sh"]};
only "id" is required. A missing est_min is the median of the recorded lanes of the same kind (30 when the lane has no kind or
there is no history). Keep lanes.json outside the repo: a file left in a worktree is swept into the merge. Two lanes whose "files"
share a path (a folder counts for every file in it; the union-merged files in SHARED do not) never run at the same time: the later one in
the order of their deps waits for the earlier one and starts from the trunk once that one is merged ("serialized" in --json, a
SERIAL line in the text).

Why: lanes that start in input order leave the long one for last (the 15/10 batch: the riskiest lane started after the small ones and
was the critical path for five hours) and every lane runs its own test suites, so seven agents at once pushed the load to 37 on a
machine whose tests then crawled. The plan starts, whenever a slot is free, the ready lane with the longest path to the end of the batch
(its own estimate plus the chain that waits for it); a heuristic, so when the listed order happens to end sooner the plan says so and
uses it. `slots` caps the parallelism by the free CPU, never below 1 and never above capacity lane_slots_max (T0052: bin/capacity.py,
lõi/3 × DEVKIT_CAPACITY — 12 lõi: 4, 64 lõi: 21; kit thiếu capacity.py thì MAX_SLOTS = 4).

LANE_PLAN_CORES / LANE_PLAN_LOAD override the machine reading, LANE_PLAN_HISTORY the history file (default
<git common dir>/devkit/lane_times.jsonl: shared by every worktree, never tracked, never swept into a merge). Python stdlib
only, 3.9 compatible.
"""
import errno
import heapq
import importlib.util
import json
import math
import os
import stat
import subprocess
import sys
import time

DEFAULT_EST = 30.0
MAX_EST = 1e6       # minutes: a bigger number is a typo (1e308 would also put Infinity in the --json output)
MAX_SLOTS = 4       # trần khi không nạp được bin/capacity.py; mặc định là capacity.lane_slots_max (T0052, 12 lõi: 4)
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


def _capacity():
    """bin/capacity.py của kit chứa script này (T0052), nạp theo đường dẫn; None khi không nạp được (bản sao LP_KIT thiếu bin/):
    chỗ gọi dùng đọc máy cũ và MAX_SLOTS."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "bin", "capacity.py")
    try:
        spec = importlib.util.spec_from_file_location("devkit_capacity", path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except (ImportError, SyntaxError, OSError, AttributeError) as exc:
        sys.stderr.write("lane_plan: không nạp được bin/capacity.py (%r); trần %d lane\n" % (exc, MAX_SLOTS))
        return None


def slots(jobs_per_lane=None):
    """(slots, cores, load): free CPU divided by what one lane uses, between 1 and capacity lane_slots_max (MAX_SLOTS without it).
    LANE_PLAN_CORES / LANE_PLAN_LOAD, khi đặt, vẫn qua _num (rác: exit 2) rồi mới vào capacity; không đặt thì capacity.cores() /
    capacity.load() (DEVKIT_CAPACITY_CORES / DEVKIT_CAPACITY_LOAD rồi máy thật)."""
    jobs_per_lane = JOBS_PER_LANE if jobs_per_lane is None else jobs_per_lane
    cap = _capacity()
    if "LANE_PLAN_CORES" in os.environ:
        cores = int(_num(os.environ["LANE_PLAN_CORES"], "LANE_PLAN_CORES"))
    else:
        cores = cap.cores() if cap is not None else int(_num(os.cpu_count() or 1, "LANE_PLAN_CORES"))
    if "LANE_PLAN_LOAD" in os.environ:
        load = _num(os.environ["LANE_PLAN_LOAD"], "LANE_PLAN_LOAD")
    elif cap is not None:
        load = cap.load()
        if load is None:
            load = 0.0   # no reading: do not throttle on a guess
    else:
        try:
            load = os.getloadavg()[0]
        except (OSError, AttributeError):
            load = 0.0   # no reading: do not throttle on a guess
    max_slots = cap.lane_slots_max(cores) if cap is not None else MAX_SLOTS
    free = max(0.0, cores - load)
    return max(1, min(max_slots, int(free // max(1, jobs_per_lane)))), cores, load


def _git_common_dir():
    """The absolute git common dir of the current directory, or None. `--path-format` is git 2.31+: an older git prints the unknown option
    back and exits 0, so its answer is accepted only as one absolute line, else the plain flag is used and made absolute here."""
    for flags in (["--path-format=absolute", "--git-common-dir"], ["--git-common-dir"]):
        try:
            r = subprocess.run(["git", "rev-parse"] + flags, capture_output=True, text=True, timeout=10)
        except (OSError, subprocess.SubprocessError):
            return None
        out = r.stdout.rstrip("\n")   # not strip(): a git dir may end in a space
        if r.returncode == 0 and out and "\n" not in out and (os.path.isabs(out) or len(flags) == 1):
            return os.path.abspath(os.path.join(os.getcwd(), out))
    return None


def history_path():
    """The history file; None outside a git repository when LANE_PLAN_HISTORY is not set (a plan then goes on without history)."""
    if os.environ.get("LANE_PLAN_HISTORY"):
        return os.environ["LANE_PLAN_HISTORY"]
    common = _git_common_dir()
    return os.path.join(common, "devkit", "lane_times.jsonl") if common else None


def _open_regular(path, flags):
    """open(2) that never waits for a peer, never follows a link and refuses anything but a regular file (a FIFO at this path would hang
    the open: INSTINCT-040; a link planted there would turn the append into a write to another file)."""
    fd = os.open(path, flags | os.O_NONBLOCK | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0))
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
    if path is None:
        return out
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
    lanes = {}
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
        files = sorted(set(os.path.normpath(f.strip()) for f in files))
        if any(os.path.isabs(f) or f == os.curdir or f == os.pardir or f.startswith(os.pardir + "/") for f in files):
            fail("files of %s must be paths from the repo root (no absolute path, no ., no ..)" % r["id"])
        kind, risk = r.get("kind", ""), r.get("risk", "")
        for field, value in (("kind", kind), ("risk", risk)):
            if value is not None and not isinstance(value, str):   # null is "not given"; any other type is a typo that would skew the plan quietly
                fail("%s of %s must be a string: %s" % (field, r["id"], _show(value)))
        kind, risk = kind or "", risk or ""
        if r.get("est_min") is not None:   # null is "not given", like kind and risk
            est = _num(r["est_min"], "est_min of %s" % r["id"])
        else:
            if kind and hist is None:
                hist = read_history()
            est = median(hist[kind]) if kind and kind in hist else DEFAULT_EST
        lanes[r["id"]] = {"id": r["id"], "est": est, "deps": sorted(set(deps)), "files": files, "high": risk.lower() == "high",
                          "file_waits": {}}
    for l in lanes.values():
        for d in l["deps"]:
            if d not in lanes:
                fail("lane %s waits for unknown lane %s" % (l["id"], d))
    # longest path from each lane to the end of the batch, in topological order (no recursion: a long chain must not hit the limit)
    seen = list(lanes)
    succ = dict((i, []) for i in seen)
    waiting = {}
    for i in seen:
        waiting[i] = len(lanes[i]["deps"])
        for d in lanes[i]["deps"]:
            succ[d].append(i)
    pos = dict((i, n) for n, i in enumerate(seen))
    order, free = [], [(pos[i], i) for i in seen if waiting[i] == 0]   # among ready lanes the listed one first: the file owner below
    heapq.heapify(free)
    while free:
        i = heapq.heappop(free)[1]
        order.append(i)
        for j in succ[i]:
            waiting[j] -= 1
            if waiting[j] == 0:
                heapq.heappush(free, (pos[j], j))
    if len(order) != len(seen):
        done = set(order)
        fail("dependency cycle through %s" % ", ".join(i for i in seen if i not in done))
    # lanes that edit one file never run at the same time (18/10: several agents on one file, every later merge conflicted): each one
    # waits for the previous editor, the one that can start earlier (its deps' chain) first, then the topological order. That key
    # orders every dependency edge too (a lane starts no earlier than its deps), so an added wait always points forward: no cycle.
    rank = dict((i, n) for n, i in enumerate(order))
    head = {}
    for i in order:
        head[i] = max([head[d] + lanes[d]["est"] for d in lanes[i]["deps"]] or [0.0])
    for f, ids in sorted(overlaps_of([lanes[i] for i in seen]).items()):
        ids = sorted(ids, key=lambda i: (head[i], rank[i]))
        for a, b in zip(ids, ids[1:]):
            waits = lanes[b]["file_waits"]
            if a not in waits:
                if _reaches(lanes, b, a):   # b already waits for a through its deps
                    continue
                lanes[b]["deps"].append(a)
                succ[a].append(b)
            waits.setdefault(a, []).append(f)
    for i in sorted(order, key=lambda i: (head[i], rank[i]), reverse=True):   # the key every edge follows, added ones too
        after = [lanes[j]["tail"] for j in succ[i]]
        lanes[i]["tail"] = lanes[i]["est"] + (max(after) if after else 0.0)
    return [lanes[i] for i in seen]


def _reaches(lanes, src, dst):
    """True when lane src waits for lane dst through its deps, directly or along a chain (iterative: a long chain must not recurse)."""
    stack, seen = [src], set()
    while stack:
        i = stack.pop()
        for d in lanes[i]["deps"]:
            if d == dst:
                return True
            if d not in seen:
                seen.add(d)
                stack.append(d)
    return False


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
        group = [running.pop(0)]
        while running and running[0][0] <= group[0][0] + 1e-9:   # a tolerance: 0.1 + 0.2 and 0.3 end together
            group.append(running.pop(0))
        t = max(end for end, _ in group)   # the latest of them: a lane that waited for them never starts before one of them ends
        for _, i in group:
            done[i] = t
    return rows, max(r["end"] for r in rows)


def overlaps_of(lanes):
    """{path: [lane ids]}: a path that more than one lane edits, or that sits inside a folder another lane names (the folder's owners count
    for the path); the union-merged files are left out. One dict lookup per path and parent folder: linear in the files."""
    owners = {}
    for l in lanes:
        for f in l["files"]:
            if not _shared(f):
                owners.setdefault(f, []).append(l["id"])
    rank = dict((l["id"], i) for i, l in enumerate(lanes))
    out = {}
    for f, ids in owners.items():
        who = set(ids)
        parent = f
        while "/" in parent:
            parent = parent.rsplit("/", 1)[0]
            who.update(owners.get(parent, ()))
        if len(who) > 1:
            out[f] = sorted(who, key=rank.get)
    return out


def plan(path, n_slots, as_json):
    lanes = load_lanes(path)
    reading = None if n_slots else slots()   # read ONCE: the load moves between two calls and the printed reading must be the one that set n
    n = n_slots if n_slots else reading[0]
    pos = dict((l["id"], i) for i, l in enumerate(lanes))
    rows, span = simulate(lanes, n, key=lambda l: (-l["tail"], not l["high"]))   # a tie on both: the listed order (sort is stable)
    naive_rows, naive = simulate(lanes, n, key=lambda l: pos[l["id"]])
    order = "critical-path"
    if naive < span - 1e-9:   # the longest-path rule is a heuristic: when the listed order ends sooner, use it and say so
        rows, span, order = naive_rows, naive, "input"
    overlaps = overlaps_of(lanes)
    serialized = [{"id": l["id"], "after": a, "files": sorted(fs)} for l in lanes for a, fs in sorted(l["file_waits"].items(), key=lambda kv: pos[kv[0]])]
    merge_order = [r["id"] for r in sorted(rows, key=lambda r: r["end"])]   # stable: lanes that end together keep their start order
    if as_json:
        print(json.dumps({"slots": n, "order": order, "start_order": [r["id"] for r in rows], "rows": rows, "makespan_min": span,
                          "input_order_makespan_min": naive, "merge_order": merge_order, "overlaps": overlaps,
                          "serialized": serialized}, indent=1))
        return
    print("slots %d (machine now: %s)" % (n, "set by --slots" if reading is None else "%d cores, load %.1f" % reading[1:]))
    print("%-24s %8s %8s %8s" % ("start order", "start", "end", "est"))
    for r in rows:
        print("%-24s %7.0fm %7.0fm %7.0fm" % (r["id"], r["start"], r["end"], r["end"] - r["start"]))
    print("batch ends after %.0f min; the same lanes in input order: %.0f min" % (span, naive))
    if order == "input":
        print("the listed order ends sooner than the longest-path rule here: start the lanes in the order they are listed")
    print("merge order (earliest finished first): %s" % " ".join(merge_order))
    for f, ids in sorted(overlaps.items()):
        print("WARNING %s is edited by %s: they never run at the same time" % (f, ", ".join(ids)))
    for s in serialized:
        print("SERIAL %s starts after %s is merged, from the merged trunk (both edit %s): open its worktree only then; when that "
              "file is the main work of both, make them one lane"
              % (s["id"], s["after"], ", ".join(s["files"])))
    print("then ONE full gate on the merged result: python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --diff origin/<branch>")


def record(lane_id, minutes, kind):
    m = _num(minutes, "minutes")
    p = history_path()
    if p is None:
        fail("not in a git repository: name the history file with LANE_PLAN_HISTORY")
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
            fail("record takes <id> <minutes> --kind K")
        if not kind:
            fail("record needs --kind K: a lane without a kind never takes an estimate from the history")
        record(args[0], args[1], kind)
        return 0
    fail("unknown command %s (plan | slots | record)" % cmd)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
