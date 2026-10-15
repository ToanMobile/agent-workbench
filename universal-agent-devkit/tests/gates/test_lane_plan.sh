#!/usr/bin/env bash
# Regression test: scripts/governance/lane_plan.py orders parallel agent lanes so the batch ends as early as possible (15/10: the riskiest
# lane started after the small ones and was the critical path for five hours; seven agents at once took the load to 37).
#   * `plan`: the ready lane with the longest path to the end of the batch starts first (small lanes first end 10 min later than heavy first),
#     a lane never starts before its dependencies end, the merge order is the order they end, two lanes that edit the same file are
#     warned about while the files every lane touches (impact_map, test_durations, checklist) are not, `plan` writes nothing;
#   * a missing estimate is the median of the recorded lanes of that kind (junk history lines skipped), 30 without history;
#   * `slots`: free CPU / jobs per lane, never below 1, never above 6;
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
"$PYBIN" -I - "$SCRIPT" "$TMP" <<'PY'
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
BASE_ENV = dict((k, v) for k, v in os.environ.items() if not k.startswith("LANE_PLAN_"))
BASE_ENV["LANE_PLAN_HISTORY"] = HIST


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

# 3. a risky lane wins a tie on path length
tie = [{"id": "L", "est_min": 20}, {"id": "H", "est_min": 20, "risk": "high"}]
rc, d, err = plan_json("l3.json", tie, 1)
chk(d is not None and d["start_order"] == ["H", "L"], "equal paths: the high-risk lane first", str(d and d["start_order"]))

# 4. slots
for env, want, why in (
    ({"LANE_PLAN_CORES": "8", "LANE_PLAN_LOAD": "30"}, 1, "overloaded machine still gets one slot"),
    ({"LANE_PLAN_CORES": "16", "LANE_PLAN_LOAD": "2"}, 3, "16 cores, load 2: 14 free / 4 = 3"),
    ({"LANE_PLAN_CORES": "64", "LANE_PLAN_LOAD": "0"}, 6, "never more than 6 lanes"),
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
for lane, mins in (("h1", "10"), ("h2", "90"), ("h3", "50")):
    rc, out, err = run(["record", lane, mins, "--kind", "rules"])
    chk(rc == 0 and "recorded" in out, "record %s" % lane, "%s %r" % (rc, err))
with open(HIST, "a") as fh:
    fh.write("not json\n" + json.dumps({"kind": "rules", "minutes": "x"}) + "\n" + json.dumps({"kind": 5, "minutes": 1}) + "\n"
             + json.dumps({"kind": "rules", "minutes": -4}) + "\n" + json.dumps({"kind": "rules"}) + "\n" + "[1, 2]\n")
rc, d, err = plan_json("l6.json", [{"id": "K", "kind": "rules"}, {"id": "N", "kind": "never-seen"}, {"id": "P"}, {"id": "X", "kind": "rules", "est_min": 7}], 4)
if d:
    est = dict((r["id"], r["end"] - r["start"]) for r in d["rows"])
    chk(est["K"] == 50, "a lane without an estimate takes the median of its kind (10, 50, 90 -> 50)", str(est))
    chk(est["N"] == 30 and est["P"] == 30, "no history for the kind: 30", str(est))
    chk(est["X"] == 7, "an explicit estimate is kept", str(est))
else:
    chk(False, "plan with history runs", err)
rc, out, err = run(["record", "z", "abc"])
chk(rc == 2, "record refuses a non-numeric duration", "%s %r" % (rc, err))
rc, out, err = run(["record", "z", "-3"])
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
chk("batch ends after 10 min" in out and "merge order" in out and "ONE full gate" in out, "the text form carries the makespan, the merge order and the one-gate line", out)
rc2, d2, err2 = plan_json("l7b.json", [{"id": "G1", "files": ["tests/impact_map.txt"]}, {"id": "G2", "files": ["tests/impact_map.txt"]}], 2)
chk(d2 is not None and d2["overlaps"] == {}, "only shared files in common: no overlap", str(d2 and d2["overlaps"]))

# 8. the CLI wiring: `agent-kit lanes ...` reaches the script (a kit copy without bin/agent-kit, as the mutant runs use, skips this)
AK = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(SCRIPT))), "bin", "agent-kit")
if os.path.isfile(AK):
    e = dict(BASE_ENV, LANE_PLAN_CORES="16", LANE_PLAN_LOAD="2")
    r = subprocess.run(["bash", AK, "lanes", "slots", "--quiet"], capture_output=True, text=True, env=e, cwd=TMP, timeout=60)
    chk(r.returncode == 0 and r.stdout.strip() == "3", "agent-kit lanes slots reaches the script", "%s %r %r" % (r.returncode, r.stdout, r.stderr))
    r = subprocess.run(["bash", AK, "lanes", "plan", l7, "--slots", "3"], capture_output=True, text=True, env=e, cwd=TMP, timeout=60)
    chk(r.returncode == 0 and "batch ends after 10 min" in r.stdout, "agent-kit lanes plan reaches the script", "%s %r %r" % (r.returncode, r.stdout, r.stderr))
    r = subprocess.run(["bash", AK, "lanes", "plan", os.path.join(TMP, "nope.json")], capture_output=True, text=True, env=e, cwd=TMP, timeout=60)
    chk(r.returncode == 2, "agent-kit lanes keeps the script's exit code 2 on bad input", "%s %r" % (r.returncode, r.stderr))
    r = subprocess.run(["bash", AK, "help"], capture_output=True, text=True, env=e, cwd=TMP, timeout=60)
    chk("lanes plan <lanes.json>" in (r.stdout + r.stderr), "agent-kit help lists lanes", (r.stdout + r.stderr)[:200])

sys.exit(1 if fails else 0)
PY
exit $?
