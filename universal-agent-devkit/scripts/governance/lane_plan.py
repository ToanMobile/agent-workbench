#!/usr/bin/env python3
"""lane_plan.py — order parallel agent lanes so the whole batch ends as early as possible.

  lane_plan.py plan <lanes.json> [--slots N] [--json]   the order to start the lanes, with a simulated timeline
  lane_plan.py slots [--jobs-per-lane J] [--quiet]      how many lanes this machine can run at once right now
  lane_plan.py record <id> <minutes> [--kind K]         remember how long a finished lane really took

lanes.json is a list of {"id": "A11", "est_min": 40, "kind": "rules-text", "deps": ["A10"], "risk": "high", "files": ["hooks/x.sh"]};
only "id" is required. A missing est_min is the median of the recorded lanes of the same kind (30 when there is no history).

Why: lanes that start in input order leave the long one for last (the 15/10 batch: the riskiest lane started after the small ones and
was the critical path for five hours) and every lane runs its own test suites, so seven agents at once pushed the load to 37 on a
machine whose tests then crawled. The plan starts, whenever a slot is free, the ready lane with the longest path to the end of the batch
(its own estimate plus the chain that waits for it); `slots` caps the parallelism by the free CPU, never below 1.

LANE_PLAN_CORES / LANE_PLAN_LOAD override the machine reading, LANE_PLAN_HISTORY the history file (default
<repo>/.agents/local/lane_times.jsonl). Python stdlib only, 3.9 compatible.
"""
import json
import math
import os
import subprocess
import sys
import time

DEFAULT_EST = 30.0
MAX_SLOTS = 6
JOBS_PER_LANE = 4   # a lane that runs the gate starts several test processes of its own
# files every lane touches and git merges as a union: not a reason to warn
SHARED = ("tests/impact_map.txt", "tests/lib/test_durations.txt", ".agents/CHECKLIST.md", ".agents/regression_status.json")


def fail(msg):
    sys.stderr.write("lane_plan: %s\n" % msg)
    sys.exit(2)


def _num(text, name):
    try:
        v = float(text)
    except (TypeError, ValueError):
        fail("%s is not a number: %r" % (name, text))
    if not math.isfinite(v) or v < 0:
        fail("%s must be a finite number >= 0: %r" % (name, text))
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
        top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        top = ""
    return os.path.join(top or os.getcwd(), ".agents", "local", "lane_times.jsonl")


def read_history():
    """{kind: [minutes]} - junk lines are skipped, never fatal."""
    out = {}
    try:
        with open(history_path(), encoding="utf-8") as fh:
            for line in fh:
                try:
                    r = json.loads(line)
                    k, m = r["kind"], float(r["minutes"])
                except (ValueError, KeyError, TypeError):
                    continue
                if isinstance(k, str) and math.isfinite(m) and m >= 0:
                    out.setdefault(k, []).append(m)
    except OSError:
        pass
    return out


def median(xs):
    s = sorted(xs)
    n = len(s)
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2.0


def load_lanes(path):
    try:
        with open(path, encoding="utf-8") as fh:
            raw = json.load(fh)
    except (OSError, ValueError) as e:
        fail("cannot read %s: %s" % (path, e))
    if not isinstance(raw, list) or not raw:
        fail("%s must hold a non-empty list of lanes" % path)
    hist = read_history()
    lanes, seen = {}, []
    for r in raw:
        if not isinstance(r, dict) or not isinstance(r.get("id"), str) or not r["id"]:
            fail("every lane needs a string id: %r" % (r,))
        if r["id"] in lanes:
            fail("duplicate lane id %s" % r["id"])
        deps = r.get("deps", [])
        files = r.get("files", [])
        if not isinstance(deps, list) or not all(isinstance(d, str) for d in deps):
            fail("deps of %s must be a list of ids" % r["id"])
        if not isinstance(files, list) or not all(isinstance(f, str) for f in files):
            fail("files of %s must be a list of paths" % r["id"])
        kind = r.get("kind") if isinstance(r.get("kind"), str) else ""
        if "est_min" in r:
            est = _num(r["est_min"], "est_min of %s" % r["id"])
        elif kind in hist:
            est = median(hist[kind])
        else:
            est = DEFAULT_EST
        lanes[r["id"]] = {"id": r["id"], "est": est, "deps": deps, "files": files, "high": r.get("risk") == "high"}
        seen.append(r["id"])
    for l in lanes.values():
        for d in l["deps"]:
            if d not in lanes:
                fail("lane %s waits for unknown lane %s" % (l["id"], d))
    # longest path from each lane to the end of the batch; a cycle never resolves
    tail, state = {}, {}

    def walk(i):
        if state.get(i) == 1:
            fail("dependency cycle through %s" % i)
        if i in tail:
            return tail[i]
        state[i] = 1
        after = [walk(j) for j in seen if i in lanes[j]["deps"]]
        state[i] = 2
        tail[i] = lanes[i]["est"] + (max(after) if after else 0.0)
        return tail[i]

    for i in seen:
        walk(i)
    for i in seen:
        lanes[i]["tail"] = tail[i]
    return [lanes[i] for i in seen]


def simulate(lanes, n, key):
    """List scheduling on n slots: whenever a slot is free start the ready lane that sorts first by key. -> (rows, makespan)."""
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
        t, i = running.pop(0)
        done[i] = t
    return rows, max(r["end"] for r in rows)


def plan(path, n_slots, as_json):
    lanes = load_lanes(path)
    n = n_slots if n_slots else slots()[0]
    rows, span = simulate(lanes, n, key=lambda l: (-l["tail"], not l["high"], -l["est"]))
    _, naive = simulate(lanes, n, key=lambda l: lanes.index(l))
    # lanes that edit the same file merge with conflicts: say so, keep the union files out of it
    owners = {}
    for l in lanes:
        for f in l["files"]:
            if f not in SHARED:
                owners.setdefault(f, []).append(l["id"])
    overlaps = {f: ids for f, ids in owners.items() if len(ids) > 1}
    merge_order = [r["id"] for r in sorted(rows, key=lambda r: (r["end"], r["id"]))]
    if as_json:
        print(json.dumps({"slots": n, "start_order": [r["id"] for r in rows], "rows": rows, "makespan_min": span,
                          "input_order_makespan_min": naive, "merge_order": merge_order, "overlaps": overlaps}, indent=1))
        return
    print("slots %d (machine now: %s)" % (n, "%d cores, load %.1f" % slots()[1:] if not n_slots else "set by --slots"))
    print("%-24s %8s %8s %8s" % ("start order", "start", "end", "est"))
    est = dict((l["id"], l["est"]) for l in lanes)
    for r in rows:
        print("%-24s %7.0fm %7.0fm %7.0fm" % (r["id"], r["start"], r["end"], est[r["id"]]))
    print("batch ends after %.0f min; the same lanes in input order: %.0f min" % (span, naive))
    print("merge order (earliest finished first): %s" % " ".join(merge_order))
    for f, ids in sorted(overlaps.items()):
        print("WARNING %s is edited by %s: the later merge conflicts, keep one owner" % (f, ", ".join(ids)))
    print("then ONE full gate on the merged result: python3 .agents/devkit/bin/post-fix-gate.py --run-tests --full --diff origin/<branch>")


def record(lane_id, minutes, kind):
    m = _num(minutes, "minutes")
    p = history_path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "a", encoding="utf-8") as fh:
        fh.write(json.dumps({"id": lane_id, "kind": kind, "minutes": m, "at": int(time.time())}) + "\n")
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
        j = int(_num(opt(args, "--jobs-per-lane", JOBS_PER_LANE), "--jobs-per-lane"))
        quiet = "--quiet" in args
        s, cores, load = slots(j)
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
