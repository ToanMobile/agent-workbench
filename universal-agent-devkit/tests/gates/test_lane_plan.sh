#!/usr/bin/env bash
# Regression test: scripts/governance/lane_plan.py orders parallel agent lanes so the batch ends as early as possible (15/10: the riskiest
# lane started after the small ones and was the critical path for five hours; seven agents at once took the load to 37).
#   * `plan`: the ready lane with the longest path to the end of the batch starts first (small lanes first end 10 min later than heavy first),
#     a lane never starts before its dependencies end, the merge order is the order they end, two lanes that edit the same file are
#     warned about while the files every lane touches (impact_map, test_durations, checklist) are not, `plan` writes nothing;
#   * a missing estimate is the median of the recorded lanes of that kind (junk history lines skipped), 30 without history;
#   * `slots`: free CPU / jobs per lane, never below 1, never above capacity lane_slots_max (T0052: bin/capacity.py, lõi/3 × DEVKIT_CAPACITY;
#     kit thiếu capacity.py thì 4);
#   * bad input (unknown dependency, cycle, duplicate id, negative or non-numeric estimate, --slots 0) exits 2 and says why.
#   LP_KIT=<devkit dir>   test another copy of the kit (one without the script: RED; a mutant: must go red)
#   LP_PY=<python>        interpreter (default python3; try /usr/bin/python3 = 3.9)
# bash 3.2 and Python 3.9 compatible; python stdlib only.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${LP_KIT:-$DEVKIT_DIR}"
PYBIN="${LP_PY:-python3}"
SCRIPT="$KIT/scripts/governance/lane_plan.py"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
"$PYBIN" -I - "$SCRIPT" "$TMP" <<'PYEND'
import json, os, subprocess, sys

SCRIPT, TMP = sys.argv[1], sys.argv[2]
PY = sys.executable
fails = 0
print("python %s, script %s" % (sys.version.split()[0], SCRIPT), flush=True)
if not os.path.isfile(SCRIPT):
    print("✖ the script does not exist: nothing to test", flush=True)
    sys.exit(1)


def chk(cond, good, why=""):
    global fails
    if cond:
        print("✔ " + good, flush=True)
    else:
        fails += 1
        print("✖ " + good + (" — " + why if why else ""), flush=True)


HIST = os.path.join(TMP, "hist", "lane_times.jsonl")
# LANE_PLAN_* và DEVKIT_CAPACITY* (nút / móc test của bin/capacity.py) của người gọi không được lái test; ca nào cần thì tự đặt
BASE_ENV = dict((k, v) for k, v in os.environ.items() if not k.startswith(("LANE_PLAN_", "DEVKIT_CAPACITY")))
BASE_ENV["LANE_PLAN_HISTORY"] = HIST
BASE_ENV["LANE_PLAN_CORES"] = "16"   # the machine reading is pinned: a plan without --slots must not depend on the host
BASE_ENV["LANE_PLAN_LOAD"] = "0"


def run(args, **env):
    e = dict(BASE_ENV)
    e.update(env)
    r = subprocess.run([PY, SCRIPT] + args, capture_output=True, text=True, env=e, cwd=TMP, timeout=60)
    return r.returncode, r.stdout, r.stderr


def lanes_file(name, lanes):
    p = os.path.join(TMP, name)
    with open(p, "w") as fh:
        json.dump(lanes, fh)
    return p


def plan_json(name, lanes, slots):
    rc, out, err = run(["plan", lanes_file(name, lanes), "--slots", str(slots), "--json"])
    if rc != 0:
        return rc, None, err
    return rc, json.loads(out), err


# 1. heavy first: three 10-minute lanes listed before one 60-minute lane, two slots
small_first = [{"id": "A", "est_min": 10}, {"id": "B", "est_min": 10}, {"id": "C", "est_min": 10}, {"id": "D", "est_min": 60}]
rc, d, err = plan_json("l1.json", small_first, 2)
chk(rc == 0 and d is not None, "plan runs on four lanes", err)
if d:
    chk(d["start_order"][0] == "D", "the 60-minute lane starts first although it is listed last", str(d["start_order"]))
    chk(d["makespan_min"] == 60 and d["input_order_makespan_min"] == 70,
        "batch ends after 60 min where the input order needs 70", "%s / %s" % (d["makespan_min"], d["input_order_makespan_min"]))
    chk(d["merge_order"][-1] == "D", "the lane that ends last merges last", str(d["merge_order"]))

# 2. dependencies and the critical path: E waits for D, F is independent and shorter than D + E
dep = [{"id": "D", "est_min": 60}, {"id": "E", "est_min": 5, "deps": ["D"]}, {"id": "F", "est_min": 40}]
rc, d, err = plan_json("l2.json", dep, 1)
if d:
    rows = dict((r["id"], r) for r in d["rows"])
    chk(d["start_order"] == ["D", "F", "E"], "one slot: D (path 65) before F (40) before E", str(d["start_order"]))
    chk(rows["E"]["start"] >= rows["D"]["end"], "E never starts before D ends", str(rows["E"]))
else:
    chk(False, "plan with dependencies runs", err)
rc, d, err = plan_json("l2b.json", [{"id": "E", "est_min": 5, "deps": ["D"]}, {"id": "D", "est_min": 60}], 4)
if d:
    rows = dict((r["id"], r) for r in d["rows"])
    chk(rows["E"]["start"] >= rows["D"]["end"] and d["makespan_min"] == 65, "four slots do not run E in parallel with D (65 min)", str(d["rows"]))
else:
    chk(False, "plan with a listed-before dependency runs", err)

# the chain behind a lane counts, not its own length alone: D (30) is shorter than F (50) but E (40) waits for D
chain = [{"id": "F", "est_min": 50}, {"id": "D", "est_min": 30}, {"id": "E", "est_min": 40, "deps": ["D"]}]
rc, d, err = plan_json("l2c.json", chain, 1)
chk(d is not None and d["start_order"] == ["D", "F", "E"], "the lane with a chain behind it (30 + 40) starts before a lone 50", str(d and d["start_order"]))
# merge order is the order the lanes end, not the alphabet
rc, d, err = plan_json("l2d.json", [{"id": "Z", "est_min": 10}, {"id": "A", "est_min": 60}], 2)
chk(d is not None and d["merge_order"] == ["Z", "A"], "merge order follows the end times (Z ends at 10, A at 60)", str(d and d["merge_order"]))

rc, d, err = plan_json("l3c.json", [{"id": "A", "est_min": 5, "kind": None, "risk": None}], 1)
chk(d is not None, "null kind and null risk are the same as not given", err)
rc, d, err = plan_json("l3d.json", [{"id": "A", "est_min": None}], 1)
chk(d is not None and d["makespan_min"] == 30, "a null est_min is the same as not given (30 min)", "%s %s" % (d and d["makespan_min"], err))
# a tie on path length and risk keeps the listed order (S: 10 + 10 behind it = 20 = Lg, and Lg is listed first although it is the longer lane)
rc, d, err = plan_json("l3b.json", [{"id": "Lg", "est_min": 20}, {"id": "S", "est_min": 10}, {"id": "T", "est_min": 10, "deps": ["S"]}], 1)
chk(d is not None and d["start_order"] == ["Lg", "S", "T"], "equal paths and equal risk: the listed order (Lg before S)", str(d and d["start_order"]))

# lanes that end at the same moment, written as sums of fractions (0.1 + 0.2 is 0.30000000000000004, not 0.3), still end together
frac = [{"id": "P", "est_min": 0.1}, {"id": "Q", "est_min": 0.2, "deps": ["P"]}, {"id": "R", "est_min": 0.3},
        {"id": "X", "est_min": 10, "deps": ["Q", "R"]}, {"id": "X2", "est_min": 10, "deps": ["Q", "R"]}, {"id": "L", "est_min": 5}]
rc, d, err = plan_json("l9k.json", frac, 2)
rows = dict((r["id"], r) for r in d["rows"]) if d else {}
chk(d is not None and rows["X"]["start"] < 1 and rows["X2"]["start"] < 1 and rows["L"]["start"] >= 10,
    "fractions that sum to the same end time end together: X and X2 (waiting for Q and R) start before the short L", str(d and d["rows"]))
chk(d is not None and rows["X"]["start"] >= max(rows["Q"]["end"], rows["R"]["end"]) and rows["X2"]["start"] >= max(rows["Q"]["end"], rows["R"]["end"]),
    "and X starts no earlier than the later of Q and R ends (not a float ULP before it)", str(d and d["rows"]))

# 3. a risky lane wins a tie on path length
tie = [{"id": "L", "est_min": 20}, {"id": "H", "est_min": 20, "risk": "high"}]
rc, d, err = plan_json("l3.json", tie, 1)
chk(d is not None and d["start_order"] == ["H", "L"], "equal paths: the high-risk lane first", str(d and d["start_order"]))

# 4. slots
for env, want, why in (
    ({"LANE_PLAN_CORES": "8", "LANE_PLAN_LOAD": "30"}, 1, "overloaded machine still gets one slot"),
    ({"LANE_PLAN_CORES": "16", "LANE_PLAN_LOAD": "2"}, 3, "16 cores, load 2: 14 free / 4 = 3"),
    ({"LANE_PLAN_CORES": "64", "LANE_PLAN_LOAD": "0"}, 16, "64 idle cores: 64 / 4 = 16 (T0052: no fixed cap of 4, capacity cap 64/3 = 21)"),
    ({"LANE_PLAN_CORES": "8", "LANE_PLAN_LOAD": "7.5"}, 1, "half a core free: one slot"),
):
    rc, out, err = run(["slots", "--quiet"], **env)
    chk(rc == 0 and out.strip() == str(want), "slots: " + why, "%s -> rc=%s out=%r err=%r" % (env, rc, out, err))
rc, out, err = run(["slots", "--quiet", "--jobs-per-lane", "8"], LANE_PLAN_CORES="16", LANE_PLAN_LOAD="0")
chk(rc == 0 and out.strip() == "2", "slots: --jobs-per-lane 8 on 16 idle cores = 2", "%r %r" % (out, err))
rc, out, err = run(["slots"], LANE_PLAN_CORES="16", LANE_PLAN_LOAD="2")
chk("slots=3" in out and "cores=16" in out and "load=2.0" in out, "slots: the long form names the reading", out)
rc, out, err = run(["slots", "--quiet"], LANE_PLAN_CORES="8", LANE_PLAN_LOAD="nan")
chk(rc == 2, "slots: a NaN load is refused, not read as free CPU", "%s %r" % (rc, out))

# 5. bad input exits 2 with a reason
bad = (
    ("unknown dependency", [{"id": "A", "deps": ["Z"]}], "unknown"),
    ("cycle", [{"id": "A", "deps": ["B"]}, {"id": "B", "deps": ["A"]}], "cycle"),
    ("self dependency", [{"id": "A", "deps": ["A"]}], "cycle"),
    ("duplicate id", [{"id": "A"}, {"id": "A"}], "duplicate"),
    ("negative estimate", [{"id": "A", "est_min": -5}], "est_min"),
    ("text estimate", [{"id": "A", "est_min": "soon"}], "est_min"),
    ("NaN estimate", [{"id": "A", "est_min": "NaN"}], "est_min"),
    ("lane without id", [{"est_min": 5}], "id"),
    ("empty list", [], "non-empty"),
)
for name, lanes, word in bad:
    rc, out, err = run(["plan", lanes_file("bad.json", lanes), "--slots", "2"])
    chk(rc == 2 and word in err and "Traceback" not in err, "bad input is refused: " + name, "rc=%s err=%r" % (rc, err))
for bad_slots in ("0", "-1", "2.5", "many"):
    rc, out, err = run(["plan", lanes_file("ok.json", [{"id": "A"}]), "--slots", bad_slots])
    chk(rc == 2 and "Traceback" not in err, "--slots %s is refused" % bad_slots, "rc=%s %r %r" % (rc, out, err))
rc, out, err = run(["plan", lanes_file("ok.json", [{"id": "A"}])], LANE_PLAN_CORES="16", LANE_PLAN_LOAD="2")
chk(rc == 0 and "slots 3 (machine now: 16 cores, load 2.0)" in out, "without --slots the plan uses the machine reading", out)
rc, out, err = run(["plan", lanes_file("ok.json", [{"id": "A"}])], LANE_PLAN_CORES="16", LANE_PLAN_LOAD="2", HOME="/nonexistent")
chk(rc == 0, "plan does not need the user's home", err)
rc, out, err = run(["plan", os.path.join(TMP, "missing.json")])
chk(rc == 2 and "cannot read" in err, "a missing file is refused", "rc=%s %r" % (rc, err))
with open(os.path.join(TMP, "junk.json"), "w") as fh:
    fh.write("{not json")
rc, out, err = run(["plan", os.path.join(TMP, "junk.json")])
chk(rc == 2 and "Traceback" not in err, "a file that is not JSON is refused", "rc=%s %r" % (rc, err))

# 6. history: median of the recorded lanes of the kind, junk skipped, 30 by default
chk(not os.path.exists(HIST), "no history file yet")
for lane, mins in (("h3", "50"), ("h2", "90"), ("h1", "10")):
    rc, out, err = run(["record", lane, mins, "--kind", "rules"])
    chk(rc == 0 and "recorded" in out, "record %s" % lane, "%s %r" % (rc, err))
with open(HIST) as fh:
    chk(len(fh.read().splitlines()) == 3, "three records are three lines (each one is appended, none replaces the file)")
with open(HIST, "a") as fh:
    fh.write("not json\n" + json.dumps({"kind": "rules", "minutes": "x"}) + "\n" + json.dumps({"kind": 5, "minutes": 1}) + "\n"
             + json.dumps({"kind": "rules", "minutes": -4}) + "\n" + json.dumps({"kind": "rules"}) + "\n" + "[1, 2]\n"
             + json.dumps({"kind": "rules", "minutes": 2000000}) + "\n")
rc, d, err = plan_json("l6.json", [{"id": "K", "kind": "rules"}, {"id": "N", "kind": "never-seen"}, {"id": "P"}, {"id": "X", "kind": "rules", "est_min": 7}], 4)
if d:
    est = dict((r["id"], r["end"] - r["start"]) for r in d["rows"])
    chk(est["K"] == 50, "a lane without an estimate takes the median of its kind (10, 50, 90 -> 50)", str(est))
    chk(est["N"] == 30 and est["P"] == 30, "no history for the kind: 30", str(est))
    chk(est["X"] == 7, "an explicit estimate is kept", str(est))
else:
    chk(False, "plan with history runs", err)
rc, out, err = run(["record", "z", "5"], LANE_PLAN_HISTORY=os.path.join(TMP, "nokind.jsonl"))
chk(rc == 2 and "--kind" in err and not os.path.exists(os.path.join(TMP, "nokind.jsonl")), "record without --kind is refused and writes nothing (it could never be used as an estimate)", "%s %r" % (rc, err[-200:]))
rc, out, err = run(["record", "z", "abc", "--kind", "k"])
chk(rc == 2, "record refuses a non-numeric duration", "%s %r" % (rc, err))
rc, out, err = run(["record", "z", "-3", "--kind", "k"])
chk(rc == 2, "record refuses a negative duration", "%s %r" % (rc, err))

# 7. overlapping files: warned, except the files every lane touches
def snapshot():
    snap = {}
    for root, dirs, files in os.walk(TMP):
        for f in files:
            p = os.path.join(root, f)
            with open(p, "rb") as fh:
                snap[p] = fh.read()
    return snap


l7 = lanes_file("l7.json", [
    {"id": "G1", "est_min": 10, "files": ["hooks/a.sh", "tests/impact_map.txt", ".agents/CHECKLIST.md"]},
    {"id": "G2", "est_min": 10, "files": ["hooks/a.sh", "tests/impact_map.txt", "tests/lib/test_durations.txt"]},
    {"id": "G3", "est_min": 10, "files": ["tests/lib/test_durations.txt", ".agents/regression_status.json"]},
])
before = snapshot()
rc, out, err = run(["plan", l7, "--slots", "3"])
chk(snapshot() == before, "plan writes nothing (no file created, none changed, history included)")
chk(rc == 0 and "WARNING hooks/a.sh is edited by G1, G2" in out, "two lanes on one file: warned", out)
chk("WARNING tests/" not in out and "WARNING .agents/" not in out, "the union-merged files are not warned about", out)
chk("batch ends after 20 min" in out and "merge order" in out and "ONE full gate" in out, "the text form carries the makespan (G2 waits for G1: both edit hooks/a.sh), the merge order and the one-gate line", out)
rc2, d2, err2 = plan_json("l7b.json", [{"id": "G1", "files": ["tests/impact_map.txt"]}, {"id": "G2", "files": ["tests/impact_map.txt"]}], 2)
chk(d2 is not None and d2["overlaps"] == {}, "only shared files in common: no overlap", str(d2 and d2["overlaps"]))

# 9. the schedule itself (review of 15/10: found by reading the code AND by Antigravity; each row below has a mutant that turns it red)
def peak(rows):
    return max(sum(1 for q in rows if q["start"] <= r["start"] < q["end"]) for r in rows)


# two lanes that end at the same moment are BOTH done before the next start is chosen: L3 (path 30) must not wait for the lone L1 (15)
simul = [{"id": "L0", "est_min": 40}, {"id": "L1", "est_min": 15}, {"id": "L2", "est_min": 40},
         {"id": "L3", "est_min": 20, "deps": ["L0", "L2"]}, {"id": "L4", "est_min": 10, "deps": ["L2"]},
         {"id": "L5", "est_min": 10, "deps": ["L3", "L4"]}]
rc, d, err = plan_json("l9a.json", simul, 2)
if d:
    rows = dict((r["id"], r) for r in d["rows"])
    chk(d["makespan_min"] == 70 and rows["L3"]["start"] == 40 and rows["L1"]["start"] >= 50,
        "lanes ending together: L3 starts at 40 before the lone L1, the batch ends after 70 min (75 when one of them is handled at a time)", str(d["rows"]))
    chk(peak(d["rows"]) <= 2, "never more lanes at once than slots (2)", str(d["rows"]))
else:
    chk(False, "plan with lanes that end together runs", err)
for n in (1, 3):
    rc, d, err = plan_json("l9a%d.json" % n, simul, n)
    chk(d is not None and peak(d["rows"]) <= n, "never more lanes at once than slots (%d)" % n, str(d and d["rows"]))
# a lane with two dependencies waits for the LONGER one
rc, d, err = plan_json("l9b.json", [{"id": "A", "est_min": 10}, {"id": "B", "est_min": 30}, {"id": "J", "est_min": 5, "deps": ["A", "B"]}], 4)
chk(d is not None and dict((r["id"], r) for r in d["rows"])["J"]["start"] >= 30, "a lane with two dependencies starts after the longer one (30)", str(d and d["rows"]))
# the path behind a lane is the LONGEST chain after it (not the sum, not the shortest): X (10) has two lanes waiting for it
rc, d, err = plan_json("l9c.json", [{"id": "W", "est_min": 40}, {"id": "X", "est_min": 10}, {"id": "Y", "est_min": 20, "deps": ["X"]}, {"id": "Z", "est_min": 20, "deps": ["X"]}], 1)
chk(d is not None and d["start_order"][0] == "W", "paths: X + max(20, 20) = 30 is shorter than W = 40, so W starts first (a sum would put X first)", str(d and d["start_order"]))
rc, d, err = plan_json("l9d.json", [{"id": "W", "est_min": 45}, {"id": "X", "est_min": 10}, {"id": "Y", "est_min": 5, "deps": ["X"]}, {"id": "Z", "est_min": 40, "deps": ["X"]}], 1)
chk(d is not None and d["start_order"][0] == "X", "paths: X + max(5, 40) = 50 is longer than W = 45, so X starts first (the shortest chain would put W first)", str(d and d["start_order"]))
# risk: only high wins a tie, in any case
rc, d, err = plan_json("l9e.json", [{"id": "L", "est_min": 20}, {"id": "M", "est_min": 20, "risk": "medium"}], 1)
chk(d is not None and d["start_order"] == ["L", "M"], "equal paths: medium risk is not high (listed order stays)", str(d and d["start_order"]))
rc, d, err = plan_json("l9f.json", [{"id": "L", "est_min": 20}, {"id": "H", "est_min": 20, "risk": "HIGH"}], 1)
chk(d is not None and d["start_order"] == ["H", "L"], "risk HIGH counts as high", str(d and d["start_order"]))
# the longest-path rule is a heuristic: when the listed order ends sooner the plan uses it and says so
lst = [{"id": "L1", "est_min": 45}, {"id": "L0", "est_min": 10}, {"id": "L2", "est_min": 60}, {"id": "L3", "est_min": 30, "deps": ["L0"]}]
rc, d, err = plan_json("l9g.json", lst, 2)
chk(d is not None and d["makespan_min"] == 75 and d["start_order"][0] == "L1" and d.get("order") == "input",
    "the listed order (75 min) beats the longest-path rule (85): the plan uses it", str(d))
rc, out, err = run(["plan", lanes_file("l9g.json", lst), "--slots", "2"])
chk("the listed order ends sooner" in out and "batch ends after 75 min" in out and "set by --slots" in out, "the text form says the listed order is used and that --slots set the count", out)
rc, d, err = plan_json("l9h.json", small_first, 2)
chk(d is not None and d.get("order") == "critical-path", "when the longest-path rule is as good or better it stays", str(d and d.get("order")))
# lanes that end together merge in the order they started: a lane never merges before the lane it waited for
rc, d, err = plan_json("l9i.json", [{"id": "B", "est_min": 0}, {"id": "A", "est_min": 0, "deps": ["B"]}], 2)
chk(d is not None and d["merge_order"] == ["B", "A"], "merge order: B before the A that waited for it, although A sorts first", str(d and d["merge_order"]))
# a long chain listed root first (a recursion per lane would hit the interpreter limit on 3.9)
chain_big = [{"id": "C%d" % i, "est_min": 1, "deps": (["C%d" % (i - 1)] if i else [])} for i in range(1200)]
rc, d, err = plan_json("l9j.json", chain_big, 1)
chk(d is not None and d["makespan_min"] == 1200, "a chain of 1200 lanes plans (no recursion limit, on either Python)", "%s %s" % (rc, err[-200:]))

# 10. input that must be refused with exit 2 and a reason, never a traceback
bad2 = (
    ("estimate true", [{"id": "A", "est_min": True}], "est_min"),
    ("estimate of 400 digits", [{"id": "A", "est_min": int("9" * 400)}], "est_min"),
    ("estimate 1e308", [{"id": "A", "est_min": 1e308}], "est_min"),
    ("empty file path", [{"id": "A", "files": [""]}], "files"),
    ("absolute file path", [{"id": "A", "files": ["/etc/hosts"]}], "files"),
    ("file path .", [{"id": "A", "files": ["."]}], "files"),
    ("file path outside the repo", [{"id": "A", "files": ["../x.sh"]}], "files"),
    ("a lane that is a list", [[1, 2]], "id"),
    ("kind that is a number", [{"id": "A", "kind": 5}], "kind"),
    ("risk that is a bool", [{"id": "A", "risk": True}], "risk"),
)
for name, lanes, word in bad2:
    rc, out, err = run(["plan", lanes_file("bad2.json", lanes), "--slots", "2"])
    chk(rc == 2 and word in err and "Traceback" not in err, "bad input is refused: " + name, "rc=%s err=%r" % (rc, err[-200:]))
with open(os.path.join(TMP, "deep.json"), "w") as fh:
    fh.write("[" * 100000 + "]" * 100000)
rc, out, err = run(["plan", os.path.join(TMP, "deep.json")])
chk(rc == 2 and "Traceback" not in err, "JSON nested 100000 deep is refused, not a RecursionError", "rc=%s %r" % (rc, err[-200:]))
for flag, value in (("--slots", "9" * 400), ("--slots", "True")):
    rc, out, err = run(["plan", lanes_file("ok.json", [{"id": "A"}]), flag, value])
    chk(rc == 2 and "Traceback" not in err, "%s %s... is refused" % (flag, value[:6]), "rc=%s %r" % (rc, err[-200:]))
for args in (["slots", "--jobs-per-lane", "0"], ["slots", "--jobs-per-lane", "0.5"], ["slots", "--bogus"]):
    rc, out, err = run(args, LANE_PLAN_CORES="16", LANE_PLAN_LOAD="0")
    chk(rc == 2 and "Traceback" not in err, "refused: lane_plan.py " + " ".join(args), "rc=%s %r %r" % (rc, out, err))
rc, out, err = run(["slots", "--quiet", "--jobs-per-lane", "1"], LANE_PLAN_CORES="64", LANE_PLAN_LOAD="0")
chk(rc == 0 and out.strip() == "21", "slots: capacity lane_slots_max caps --jobs-per-lane 1 on 64 idle cores at 64/3 = 21", "%r %r" % (out, err))
rc, out, err = run(["slots", "--quiet", "--jobs-per-lane", "1"], LANE_PLAN_CORES="64", LANE_PLAN_LOAD="0", DEVKIT_CAPACITY="0.5")
chk(rc == 0 and out.strip() == "10", "slots: DEVKIT_CAPACITY=0.5 halves the cap (64 cores: 10)", "%r %r" % (out, err))
rc, out, err = run(["slots", "--quiet", "--jobs-per-lane", "1"], LANE_PLAN_CORES="12", LANE_PLAN_LOAD="0")
chk(rc == 0 and out.strip() == "4", "slots: 12 idle cores, --jobs-per-lane 1: cap 12/3 = 4 (as the old fixed 4)", "%r %r" % (out, err))
# kit thiếu bin/capacity.py (bản cũ): trần cố định MAX_SLOTS = 4, không traceback
nokit = os.path.join(TMP, "nokit", "scripts", "governance")
os.makedirs(nokit)
with open(SCRIPT, "rb") as src, open(os.path.join(nokit, "lane_plan.py"), "wb") as dst:
    dst.write(src.read())
e = dict(BASE_ENV, LANE_PLAN_CORES="64", LANE_PLAN_LOAD="0")
r = subprocess.run([PY, os.path.join(nokit, "lane_plan.py"), "slots", "--quiet", "--jobs-per-lane", "1"], capture_output=True, text=True, env=e,
                   cwd=TMP, timeout=60)
chk(r.returncode == 0 and r.stdout.strip() == "4" and "Traceback" not in r.stderr, "slots: kit without bin/capacity.py keeps the fixed cap of 4",
    "%r %r" % (r.stdout, r.stderr[-200:]))
# capacity.py hỏng lúc nạp (lỗi runtime, không chỉ ImportError): vẫn trần 4, không traceback
os.makedirs(os.path.join(TMP, "nokit", "bin"))
with open(os.path.join(TMP, "nokit", "bin", "capacity.py"), "w") as fh:
    fh.write("raise RuntimeError('capacity hỏng lúc nạp')\n")
r = subprocess.run([PY, os.path.join(nokit, "lane_plan.py"), "slots", "--quiet", "--jobs-per-lane", "1"], capture_output=True, text=True, env=e,
                   cwd=TMP, timeout=60)
chk(r.returncode == 0 and r.stdout.strip() == "4" and "Traceback" not in r.stderr, "slots: a capacity.py that raises at import keeps the fixed cap of 4",
    "%r %r" % (r.stdout, r.stderr[-200:]))
# capacity.py nạp được nhưng hỏng khi gọi (Antigravity audit 23/10): file 0 byte (thiếu hàm), hàm ném lỗi, hay trả ngoài miền (0, bool,
# chuỗi, nan, âm) → đọc máy cũ (os.cpu_count / os.getloadavg) và trần MAX_SLOTS = 4, không traceback. Ca A ghim lõi (512) để tải thật
# không làm đổi kết quả và cap.load() / lane_slots_max() hỏng bị gọi; ca B ghim tải 0 để cap.cores() hỏng bị gọi.
BROKEN = ("", "def cores():\n    raise RuntimeError('x')\ndef load():\n    raise RuntimeError('y')\ndef lane_slots_max(c):\n    raise RuntimeError('z')\n",
          "def cores():\n    return 0\ndef load():\n    return 'abc'\ndef lane_slots_max(c):\n    return 0\n",
          "def cores():\n    return True\ndef load():\n    return float('nan')\ndef lane_slots_max(c):\n    return -3\n")
want_b = str(min(4, max(1, os.cpu_count() or 1)))
# BASE_ENV ghim cả LANE_PLAN_CORES lẫn LANE_PLAN_LOAD: bỏ cả hai rồi mới đặt đúng một cái, không thì cap.cores() / cap.load() hỏng không
# bao giờ được gọi (OCR 23/10)
UNPINNED = dict((k, v) for k, v in BASE_ENV.items() if k not in ("LANE_PLAN_CORES", "LANE_PLAN_LOAD"))
bad = []
for body in BROKEN:
    with open(os.path.join(TMP, "nokit", "bin", "capacity.py"), "w") as fh:
        fh.write(body)
    for tag, extra, want in (("A", {"LANE_PLAN_CORES": "512"}, "4"), ("B", {"LANE_PLAN_LOAD": "0"}, want_b)):
        r = subprocess.run([PY, os.path.join(nokit, "lane_plan.py"), "slots", "--quiet", "--jobs-per-lane", "1"], capture_output=True,
                           text=True, env=dict(UNPINNED, **extra), cwd=TMP, timeout=60)
        if not (r.returncode == 0 and r.stdout.strip() == want and "Traceback" not in r.stderr):
            bad.append("%s %r: rc=%s out=%r err=%r" % (tag, body[:24], r.returncode, r.stdout.strip(), r.stderr.strip()[-120:]))
chk(not bad, "slots: capacity.py rỗng / hàm ném lỗi / trả 0, bool, chuỗi, nan, âm: đọc máy cũ, trần 4, không traceback", "; ".join(bad[:3]))

# 11. history: a bad line is skipped, an odd file is refused or ignored, never a hang or a traceback
H2 = os.path.join(TMP, "h2.jsonl")
with open(H2, "wb") as fh:
    fh.write(b"\xff\xfe not utf-8\n" + json.dumps({"kind": "u8", "minutes": 10}).encode() + b"\n"
             + b'{"kind": "u8", "minutes": ' + b"9" * 400 + b"}\n" + b"[" * 100000 + b"\n"
             + json.dumps({"kind": "u8", "minutes": True}).encode() + b"\n" + json.dumps({"kind": "u8", "minutes": 30}).encode() + b"\n"
             + json.dumps({"kind": "", "minutes": 240}).encode() + b"\n" + json.dumps({"minutes": 300}).encode() + b"\n")
kinds = lanes_file("l11.json", [{"id": "K", "kind": "u8"}, {"id": "N"}])
r = subprocess.run([PY, SCRIPT, "plan", kinds, "--slots", "2", "--json"], capture_output=True, text=True, timeout=60, cwd=TMP, env=dict(BASE_ENV, LANE_PLAN_HISTORY=H2))
est = dict((x["id"], x["end"] - x["start"]) for x in json.loads(r.stdout)["rows"]) if r.returncode == 0 else {}
chk(est.get("K") == 20, "history: bytes that are not UTF-8, a 400-digit number, a 100000-deep line and a bool are skipped; the even median of 10 and 30 is 20", "%s %s %r" % (r.returncode, est, r.stderr[-200:]))
chk(est.get("N") == 30, "history: a lane without a kind is not given the median of the rows recorded without a kind (30, not 240/300)", str(est))
os.mkdir(os.path.join(TMP, "histdir"))
rc, out, err = run(["plan", lanes_file("ok.json", [{"id": "A", "est_min": 5}]), "--slots", "1"], LANE_PLAN_HISTORY=os.path.join(TMP, "histdir"))
chk(rc == 0, "a history path that is a directory does not matter when every lane has an estimate", "rc=%s %r" % (rc, err[-200:]))
rc, out, err = run(["plan", lanes_file("nok.json", [{"id": "A"}]), "--slots", "1"], LANE_PLAN_HISTORY=os.path.join(TMP, "histdir"))
chk(rc == 0, "a lane with neither estimate nor kind does not read the history at all (30 min, a broken history file does not matter)", "rc=%s %r" % (rc, err[-200:]))
rc, out, err = run(["plan", lanes_file("k.json", [{"id": "A", "kind": "x"}]), "--slots", "1"], LANE_PLAN_HISTORY=os.path.join(TMP, "histdir"))
chk(rc == 2 and "history" in err and "Traceback" not in err, "a lane that needs the history and finds a directory: refused with the reason", "rc=%s %r" % (rc, err[-200:]))
rc, out, err = run(["record", "z", "5", "--kind", "k"], LANE_PLAN_HISTORY=os.path.join(TMP, "histdir"))
chk(rc == 2 and "Traceback" not in err, "record to a directory is refused with the reason", "rc=%s %r" % (rc, err[-200:]))
FIFO = os.path.join(TMP, "fifo.jsonl")
os.mkfifo(FIFO)
for args, name in ((["plan", lanes_file("k.json", [{"id": "A", "kind": "x"}]), "--slots", "1"], "plan"), (["record", "z", "5", "--kind", "k"], "record")):
    try:
        rc, out, err = run(args, LANE_PLAN_HISTORY=FIFO)
        chk(rc == 2 and "Traceback" not in err, "a FIFO as the history file: %s is refused at once, not hung" % name, "rc=%s %r" % (rc, err[-200:]))
    except subprocess.TimeoutExpired:
        chk(False, "a FIFO as the history file: %s is refused at once, not hung" % name, "it hung")
TARGET = os.path.join(TMP, "precious.txt")
with open(TARGET, "w") as fh:
    fh.write("precious\n")
os.symlink(TARGET, os.path.join(TMP, "link.jsonl"))
rc, out, err = run(["record", "z", "5", "--kind", "k"], LANE_PLAN_HISTORY=os.path.join(TMP, "link.jsonl"))
chk(rc == 2 and "Traceback" not in err and open(TARGET).read() == "precious\n", "a link at the history path is refused, the file behind it is not written", "rc=%s %r" % (rc, err[-200:]))
rc, out, err = run(["plan", lanes_file("k.json", [{"id": "A", "kind": "x"}]), "--slots", "1"], LANE_PLAN_HISTORY=os.path.join(TMP, "link.jsonl"))
chk(rc == 2 and "Traceback" not in err, "a link at the history path is not read either", "rc=%s %r" % (rc, err[-200:]))
rc, out, err = run(["record", "z", "7", "--kind", "k"], LANE_PLAN_HISTORY="bare.jsonl")
chk(rc == 0 and os.path.isfile(os.path.join(TMP, "bare.jsonl")), "a bare file name as the history file is created in the current directory", "rc=%s %r" % (rc, err[-200:]))

# 12. overlaps: paths are compared as paths, the union-merged files are recognised wherever the kit sits
def overlaps_of(name, lanes):
    rc, d, err = plan_json(name, lanes, 4)
    return d["overlaps"] if d else err


kit = "universal-agent-devkit/"
shared = overlaps_of("l12a.json", [
    {"id": "P1", "files": [kit + "tests/lib/test_durations.txt", kit + "tests/impact_map.txt", ".agents/CHECKLIST.md", ".agents/regression_status.json"]},
    {"id": "P2", "files": [kit + "tests/lib/test_durations.txt", kit + "tests/impact_map.txt", ".agents/CHECKLIST.md", ".agents/regression_status.json"]}])
chk(shared == {}, "the union-merged files are not warned about, with the kit folder in front or not (each of the four, in two lanes)", str(shared))
chk(overlaps_of("l12b.json", [{"id": "Q1", "files": ["xtests/impact_map.txt"]}, {"id": "Q2", "files": ["xtests/impact_map.txt"]}]) == {"xtests/impact_map.txt": ["Q1", "Q2"]},
    "control: xtests/impact_map.txt is not tests/impact_map.txt (the match is on a path boundary)")
chk(overlaps_of("l12c.json", [{"id": "R1", "files": ["./hooks/a.sh"]}, {"id": "R2", "files": ["hooks/a.sh"]}]) == {"hooks/a.sh": ["R1", "R2"]},
    "./hooks/a.sh and hooks/a.sh are one file")
chk(overlaps_of("l12d.json", [{"id": "R1", "files": ["hooks/"]}, {"id": "R2", "files": ["hooks/a.sh"]}]) == {"hooks/a.sh": ["R1", "R2"]},
    "a folder and a file inside it overlap (reported on the file)")
chk(overlaps_of("l12d2.json", [{"id": "A", "files": ["hooks"]}, {"id": "B", "files": ["hooks/a.sh"]}, {"id": "C", "files": ["hooks/b.sh"]}])
    == {"hooks/a.sh": ["A", "B"], "hooks/b.sh": ["A", "C"]}, "one folder owner and two lanes inside it: B and C do not conflict with each other")
chk(overlaps_of("l12d4.json", [{"id": "A", "files": ["hooks"]}, {"id": "B", "files": ["hooks/sub/a.sh"]}]) == {"hooks/sub/a.sh": ["A", "B"]},
    "a folder two levels above a file still overlaps with it")
chk(overlaps_of("l12d3.json", [{"id": "A", "files": [" hooks/a.sh "]}, {"id": "B", "files": ["hooks/a.sh"]}]) == {"hooks/a.sh": ["A", "B"]},
    "a path with spaces around it is the same path")
chk(overlaps_of("l12e.json", [{"id": "R1", "files": ["hooks/a.sh", "hooks/a.sh"]}, {"id": "R2", "files": ["hooks/b.sh"]}]) == {},
    "a lane that lists a file twice does not overlap with itself; hooks/a.sh and hooks/b.sh are different files")
chk(overlaps_of("l12e2.json", [{"id": "R1", "files": ["hooks/", "hooks/a.sh"]}, {"id": "R2", "files": ["tests/b.sh"]}]) == {},
    "a lane that names a folder and a file inside it does not overlap with itself")
chk(overlaps_of("l12f.json", [{"id": "R1", "files": ["hooks/a.sh"]}, {"id": "R2", "files": ["hooks/ab.sh", "tests/a.sh"]}]) == {},
    "controls: hooks/ab.sh is not inside hooks/a.sh, tests/a.sh is not hooks/a.sh")
chk(overlaps_of("l12g.json", [{"id": "S1", "files": ["a.sh", "b.sh"]}, {"id": "S2", "files": ["c.sh", "b.sh"]}]) == {"b.sh": ["S1", "S2"]},
    "an overlap on the second file of a lane is found")
chk(overlaps_of("l12i.json", [{"id": "Z", "files": ["x.sh"]}, {"id": "A", "files": ["x.sh"]}]) == {"x.sh": ["Z", "A"]}, "the lanes of an overlap are named in the listed order, not alphabetically")
chk(overlaps_of("l12h.json", [{"id": "S1", "files": ["a.sh"]}, {"id": "S2", "files": ["a.sh"]}, {"id": "S3", "files": ["a.sh"]}]) == {"a.sh": ["S1", "S2", "S3"]},
    "three lanes on one file are named in the listed order")

# 13. the default history file lives in the git common dir: shared by every worktree, never tracked, never swept into a merge
import shutil
REPO, WT = os.path.join(TMP, "repo"), os.path.join(TMP, "wt")
GITENV = dict((k, v) for k, v in os.environ.items() if not k.startswith("GIT_"))
GITENV["GIT_CONFIG_GLOBAL"] = os.devnull   # the host's ~/.gitconfig (hooksPath, templates, signing) must not decide this test
GITENV["GIT_CONFIG_NOSYSTEM"] = "1"
GIT = ["git", "-c", "user.name=lane", "-c", "user.email=lane@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=" + os.devnull]


def git(*args, **kw):
    return subprocess.run(GIT + list(args), capture_output=True, text=True, env=GITENV, timeout=60, **kw)


os.mkdir(REPO)
ok = git("init", "-q", cwd=REPO).returncode == 0 and git("commit", "-q", "--allow-empty", "-m", "x", cwd=REPO).returncode == 0 \
    and git("worktree", "add", "-q", "--detach", WT, cwd=REPO).returncode == 0
chk(ok, "a scratch repo with a linked worktree for the history location test")
if ok:
    NOH = dict((k, v) for k, v in BASE_ENV.items() if k != "LANE_PLAN_HISTORY")
    r = subprocess.run([PY, SCRIPT, "record", "lane1", "12", "--kind", "gitk"], capture_output=True, text=True, env=NOH, cwd=WT, timeout=60)
    common = os.path.join(REPO, ".git", "devkit", "lane_times.jsonl")
    chk(r.returncode == 0 and os.path.isfile(common), "record from a linked worktree writes into the main repo's git dir", "%s %r %s" % (r.returncode, r.stderr, os.listdir(WT)))
    chk(not os.path.exists(os.path.join(WT, ".agents")) and git("status", "--porcelain", cwd=WT).stdout == "" and git("status", "--porcelain", cwd=REPO).stdout == "",
        "the history is no untracked file in the worktree nor in the main checkout (nothing for an auto-merge to sweep in)",
        "%r %r" % (git("status", "--porcelain", cwd=WT).stdout, git("status", "--porcelain", cwd=REPO).stdout))
    r = subprocess.run([PY, SCRIPT, "plan", lanes_file("l13.json", [{"id": "G", "kind": "gitk"}]), "--slots", "1", "--json"], capture_output=True, text=True, env=NOH, cwd=REPO, timeout=60)
    est = json.loads(r.stdout)["rows"][0] if r.returncode == 0 else {}
    chk(est.get("end") == 12, "plan run from the main checkout reads what a worktree recorded", "%s %r" % (r.returncode, r.stderr[-200:]))
    # a git older than 2.31 prints the unknown --path-format option back and exits 0: the history must still land in the git dir
    REALGIT = shutil.which("git")
    OLDBIN = os.path.join(TMP, "oldgit")
    os.mkdir(OLDBIN)
    with open(os.path.join(OLDBIN, "git"), "w") as fh:
        fh.write('#!/bin/sh\nif [ "$1" = rev-parse ] && [ "$2" = "--path-format=absolute" ]; then\n  echo "--path-format=absolute"; shift 2; exec "%s" rev-parse "$@"\nfi\nexec "%s" "$@"\n' % (REALGIT, REALGIT))
    os.chmod(os.path.join(OLDBIN, "git"), 0o755)
    subprocess.run([os.path.join(OLDBIN, "git"), "--version"], capture_output=True, timeout=60)   # the first exec of a fresh wrapper can be slow
    OLDENV = dict(NOH, PATH=OLDBIN + os.pathsep + NOH.get("PATH", os.defpath))
    r = subprocess.run([PY, SCRIPT, "record", "lane9", "9", "--kind", "oldgit"], capture_output=True, text=True, env=OLDENV, cwd=WT, timeout=60)
    recorded = open(common).read() if os.path.isfile(common) else ""   # a failed record above must show as a ✖, not stop the script here
    chk(r.returncode == 0 and '"lane9"' in recorded and os.listdir(WT) == [".git"],
        "with a git that prints --path-format back (older than 2.31) the history still goes into the git dir, nothing is created in the worktree", "%s %r %s" % (r.returncode, r.stderr[-200:], os.listdir(WT)))
    NOGIT = os.path.join(TMP, "nogit")
    os.mkdir(NOGIT)
    r = subprocess.run([PY, SCRIPT, "record", "lane2", "3", "--kind", "k"], capture_output=True, text=True, env=NOH, cwd=NOGIT, timeout=60)
    chk(r.returncode == 2 and "git" in r.stderr and os.listdir(NOGIT) == [], "outside a git repository record refuses and creates nothing", "%s %r %s" % (r.returncode, r.stderr[-200:], os.listdir(NOGIT)))
    r = subprocess.run([PY, SCRIPT, "plan", lanes_file("l13n.json", [{"id": "K", "kind": "gitk"}]), "--slots", "1", "--json"], capture_output=True, text=True, env=NOH, cwd=NOGIT, timeout=60)
    chk(r.returncode == 0 and json.loads(r.stdout)["rows"][0]["end"] == 30.0, "outside a git repository a plan goes on without history (30 min)", "%s %r" % (r.returncode, r.stderr[-200:]))
    TRAIL = os.path.join(TMP, "trailgd ")   # a git dir whose name ends in a space: the path must not be stripped
    WORK = os.path.join(TMP, "trailwork")
    os.mkdir(WORK)
    if git("init", "-q", "--separate-git-dir", TRAIL, WORK).returncode == 0:
        r = subprocess.run([PY, SCRIPT, "record", "lane3", "4", "--kind", "k"], capture_output=True, text=True, env=NOH, cwd=WORK, timeout=60)
        chk(r.returncode == 0 and os.path.isfile(os.path.join(TRAIL, "devkit", "lane_times.jsonl")) and not os.path.exists(os.path.join(TMP, "trailgd")),
            "a git dir whose name ends in a space gets the history inside it, no sibling folder", "%s %r" % (r.returncode, r.stderr[-200:]))
    else:
        chk(False, "git init --separate-git-dir for the trailing-space test")

# the machine reading is taken once: the cores and load printed are the ones that set the slot count (a second read would print another load)
import contextlib, importlib.util, io
spec = importlib.util.spec_from_file_location("lane_plan_under_test", SCRIPT)
lp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lp)
readings = iter([(3, 16, 2.0), (1, 8, 30.0), (1, 8, 30.0)])
lp.slots = lambda *a, **k: next(readings)
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    lp.plan(lanes_file("l13r.json", [{"id": "A", "est_min": 5}]), None, False)
chk("slots 3 (machine now: 16 cores, load 2.0)" in buf.getvalue(), "the reading printed is the one that set the slot count", buf.getvalue())

# 14. lanes that edit one file never run at the same time (18/10: several agents edited one file and the merges conflicted): the later
# lane in dependency-then-listed order waits for the earlier one; the files every lane touches stay parallel
rc, d, err = plan_json("l14a.json", [{"id": "A", "est_min": 10, "files": ["hooks/a.sh"]}, {"id": "B", "est_min": 10, "files": ["hooks/a.sh"]},
                                     {"id": "C", "est_min": 10, "files": ["hooks/c.sh"]}], 3)
if d:
    rows = dict((r["id"], r) for r in d["rows"])
    chk(rows["B"]["start"] >= rows["A"]["end"], "B waits for A: both edit hooks/a.sh", str(d["rows"]))
    chk(rows["C"]["start"] == 0, "C (its own file) still starts at once", str(d["rows"]))
    chk(d["makespan_min"] == 20, "two lanes on one file take 20 min, not 10", str(d["makespan_min"]))
    chk(d.get("serialized") == [{"id": "B", "after": "A", "files": ["hooks/a.sh"]}], "the JSON names the added wait and the file behind it", str(d.get("serialized")))
    chk(d["overlaps"] == {"hooks/a.sh": ["A", "B"]}, "the overlaps key keeps its shape", str(d["overlaps"]))
else:
    chk(False, "plan with two lanes on one file runs", err)
# three lanes on one file form a chain, not three waits on the first (B and C would still run together)
rc, d, err = plan_json("l14b.json", [{"id": "A", "est_min": 5, "files": ["x.py"]}, {"id": "B", "est_min": 5, "files": ["x.py"]},
                                     {"id": "C", "est_min": 5, "files": ["x.py"]}], 4)
if d:
    rows = dict((r["id"], r) for r in d["rows"])
    chk(rows["B"]["start"] >= rows["A"]["end"] and rows["C"]["start"] >= rows["B"]["end"] and d["makespan_min"] == 15,
        "three lanes on one file run as a chain (15 min)", str(d["rows"]))
else:
    chk(False, "plan with three lanes on one file runs", err)
# a folder and a file inside it: serialized as well
rc, d, err = plan_json("l14c.json", [{"id": "F", "est_min": 10, "files": ["hooks"]}, {"id": "G", "est_min": 10, "files": ["hooks/sub/a.sh"]}], 2)
chk(d is not None and d["makespan_min"] == 20, "a lane on a folder and a lane on a file inside it never run together", str(d and d["rows"]))
# the order follows the explicit deps, so the added wait never makes a cycle: Y is listed first but waits for X
rc, d, err = plan_json("l14d.json", [{"id": "Y", "est_min": 10, "deps": ["X"], "files": ["s.sh"]}, {"id": "X", "est_min": 10, "files": ["s.sh"]}], 2)
chk(rc == 0 and d is not None and d["makespan_min"] == 20 and d.get("serialized") == [],
    "a shared file between lanes already in a dependency chain adds no wait and no cycle", "%s %s %s" % (rc, err, d and d.get("serialized")))
# only the union-merged files in common: no wait
rc, d, err = plan_json("l14e.json", [{"id": "U", "est_min": 10, "files": ["tests/impact_map.txt"]}, {"id": "V", "est_min": 10, "files": ["tests/impact_map.txt"]}], 2)
chk(d is not None and d["makespan_min"] == 10 and d.get("serialized") == [], "lanes that share only union-merged files still run together", str(d and d["rows"]))
# the text form says what it did and what the agent can do instead
rc, out, err = run(["plan", lanes_file("l14f.json", [{"id": "A", "est_min": 10, "files": ["hooks/a.sh"]}, {"id": "B", "est_min": 10, "files": ["hooks/a.sh"]}]), "--slots", "2"])
chk(rc == 0 and "B starts after A is merged, from the merged trunk (both edit hooks/a.sh)" in out and "one lane" in out, "the text form names the serialized pair and the merge option", out)
# the tail (critical path) counts the added wait: P (5) with Q (50) waiting on its file must start before a lone R (40) on one slot
rc, d, err = plan_json("l14g.json", [{"id": "R", "est_min": 40}, {"id": "P", "est_min": 5, "files": ["k.sh"]}, {"id": "Q", "est_min": 50, "files": ["k.sh"]}], 2)
chk(d is not None and d["start_order"][0] == "P", "a lane another lane waits on for a file starts first (path 5 + 50)", str(d and d["start_order"]))

# the lane that can start earlier edits first (OCR 18/10): D is free at once, C waits for A then B, so D goes first and nobody waits (15 min)
rc, d, err = plan_json("l14h.json", [{"id": "A", "est_min": 5}, {"id": "B", "est_min": 5, "deps": ["A"]}, {"id": "C", "est_min": 5, "deps": ["B"], "files": ["x.sh"]},
                                     {"id": "D", "est_min": 5, "files": ["x.sh"]}], 2)
chk(d is not None and d["makespan_min"] == 15 and d.get("serialized") == [{"id": "C", "after": "D", "files": ["x.sh"]}],
    "the editor that can start first takes the file first (15 min, C after D)", str(d and (d["makespan_min"], d.get("serialized"))))
# a lane that already waits for the other editor through a chain of deps gets no extra wait (no noise in the SERIAL lines)
rc, d, err = plan_json("l14i.json", [{"id": "A", "est_min": 5, "files": ["x.sh"]}, {"id": "B", "est_min": 5, "deps": ["A"]},
                                     {"id": "C", "est_min": 5, "deps": ["B"], "files": ["x.sh"]}], 2)
chk(d is not None and d.get("serialized") == [] and d["makespan_min"] == 15, "a wait already implied by a chain of deps is not added again", str(d and d.get("serialized")))

# 8. the CLI wiring: `agent-kit lanes ...` reaches the script (a kit copy without bin/agent-kit, as the mutant runs use, skips this)
AK = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(SCRIPT))), "bin", "agent-kit")
if os.path.isfile(AK):
    e = dict(BASE_ENV, LANE_PLAN_CORES="16", LANE_PLAN_LOAD="2")
    r = subprocess.run(["bash", AK, "lanes", "slots", "--quiet"], capture_output=True, text=True, env=e, cwd=TMP, timeout=60)
    chk(r.returncode == 0 and r.stdout.strip() == "3", "agent-kit lanes slots reaches the script", "%s %r %r" % (r.returncode, r.stdout, r.stderr))
    r = subprocess.run(["bash", AK, "lanes", "plan", l7, "--slots", "3"], capture_output=True, text=True, env=e, cwd=TMP, timeout=60)
    chk(r.returncode == 0 and "batch ends after 20 min" in r.stdout, "agent-kit lanes plan reaches the script", "%s %r %r" % (r.returncode, r.stdout, r.stderr))
    r = subprocess.run(["bash", AK, "lanes", "plan", os.path.join(TMP, "nope.json")], capture_output=True, text=True, env=e, cwd=TMP, timeout=60)
    chk(r.returncode == 2, "agent-kit lanes keeps the script's exit code 2 on bad input", "%s %r" % (r.returncode, r.stderr))
    r = subprocess.run(["bash", AK, "help"], capture_output=True, text=True, env=e, cwd=TMP, timeout=60)
    chk("lanes plan <lanes.json>" in (r.stdout + r.stderr), "agent-kit help lists lanes", (r.stdout + r.stderr)[:200])
    chk(r.stderr == "", "agent-kit help prints nothing on stderr (no backtick of the lanes text runs in the unquoted heredoc)", r.stderr[:200])
    r = subprocess.run(["bash", "-c", 'eval "$("$0" completion bash)" || exit 3; COMP_WORDS=(agent-kit lanes ""); COMP_CWORD=2; _agent_kit; printf "%s\\n" "${COMPREPLY[@]}" | LC_ALL=C sort | tr "\\n" " "', AK], capture_output=True, text=True, env=e, cwd=TMP, timeout=60)
    chk(r.stdout == "plan record slots ", "agent-kit completion offers the three lanes sub-actions", "%r %r" % (r.stdout, r.stderr[:200]))

sys.exit(1 if fails else 0)
PYEND
exit $?
