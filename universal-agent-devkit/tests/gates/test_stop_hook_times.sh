#!/usr/bin/env bash
# Regression test: scripts/governance/stop_hook_times.py answers "is Stop stuck, and on which hook?" from data that already exists:
#   * Claude Code writes a `system` / `stop_hook_summary` record into the session transcript at EVERY Stop, with
#     hookInfos[] = {command, durationMs} per hook (the hooks log no duration of their own: their logs only carry an end time);
#   * bin/post-fix-gate.py writes <git-common-dir>/postfix-gate/runs.jsonl, one record per gate run, source=hook for the Stop hook:
#     total_wall_s, the seconds of each suite that ran, busy=true when the run ended waiting for test_run.lock.
# The script prints, per repo and per hook, the number of Stops and the p50 / p90 / max seconds (nearest rank), the slowest hook of each
# Stop, and for the Stop hook's gate runs the share of wall time spent in suites / waiting for the lock / elsewhere. Read-only, stdlib.
#
# Synthetic transcripts and runs.jsonl in a throw-away projects dir: exact numbers for two hooks over four Stops of one repo (one of them
# a worktree transcript, `<slug>--claude-worktrees-<name>`), a hook with no / junk durationMs (counted apart, never in the percentiles),
# a repo whose slug merely STARTS with another's (must not leak in), garbage lines, --since-days (a 10-day-old Stop), a repo with no
# transcripts, a path that is not a git repo (the gate section says no data), the shares of the gate runs, and a read-only guarantee.
#   STT_KIT=<devkit dir>   test another copy of the kit (one without the script: RED; a mutant: must go red)
#   STT_PY=<python>        interpreter (default python3; try /usr/bin/python3 = 3.9)
# bash 3.2 and Python 3.9 compatible; python stdlib only.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${STT_KIT:-$DEVKIT_DIR}"
PYBIN="${STT_PY:-python3}"
SCRIPT="$KIT/scripts/governance/stop_hook_times.py"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
"$PYBIN" -I - "$SCRIPT" "$TMP" <<'PYEND'
import hashlib, json, os, re, subprocess, sys, time

SCRIPT, TMP = sys.argv[1], sys.argv[2]
PY = sys.executable
fails = 0
print("python %s, script %s" % (sys.version.split()[0], SCRIPT), flush=True)


def chk(cond, good, why=""):
    global fails
    if cond:
        print("✔ " + good, flush=True)
    else:
        fails += 1
        print("✖ %s: %s" % (good, why), flush=True)
    return bool(cond)


def git(root, *args):
    return subprocess.run(["git", "-C", root] + list(args), check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60).stdout.decode().strip()


def make_repo(name):
    root = os.path.realpath(os.path.join(TMP, name))
    os.makedirs(root)
    git(root, "init", "-q", ".")
    git(root, "config", "user.email", "t@t")
    git(root, "config", "user.name", "t")
    with open(root + "/f", "w") as f:
        f.write("x\n")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "init")
    return root


def slug(path):
    return re.sub(r"[^A-Za-z0-9]", "-", path)


def iso(epoch):
    return time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(epoch))


NOW = time.time()
PROJ = os.path.join(TMP, "projects")


def put(dirname, fname, lines):
    d = os.path.join(PROJ, dirname)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, fname), "w") as f:
        f.write("".join(l if isinstance(l, str) else json.dumps(l) + "\n" for l in lines))


def stop(ts, infos, prevented=False, errors=()):
    return {"type": "system", "subtype": "stop_hook_summary", "timestamp": iso(ts), "hookCount": len(infos), "hookInfos": infos,
            "hookErrors": list(errors), "preventedContinuation": prevented, "sessionId": "s"}


def hook(name, ms=None, raw=None, command=None):
    h = {"command": command if command is not None else 'bash "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/%s"' % name}
    if raw is not None:
        h["durationMs"] = raw
    elif ms is not None:
        h["durationMs"] = ms
    return h


def run(*args):
    r = subprocess.run([PY, "-I", SCRIPT] + list(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    return r.returncode, r.stdout.decode("utf-8", "replace"), r.stderr.decode("utf-8", "replace")


def jsn(*args):
    rc, out, err = run(*(list(args) + ["--json"]))
    try:
        return rc, json.loads(out), err
    except ValueError:
        return rc, None, out + err


chk(os.path.isfile(SCRIPT), "the script exists", SCRIPT)
if not os.path.isfile(SCRIPT):
    print("❌ test_stop_hook_times: 1 failed (no script)")
    sys.exit(1)

# ── fixtures ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
A = make_repo("repoA")
B = make_repo("repoB")
NOGIT = os.path.realpath(os.path.join(TMP, "plain"))
os.makedirs(NOGIT)
EMPTY = make_repo("repoE")   # a repo no session ever ran in: no transcript dir at all
T = NOW - 60
# repo A, main transcript: 3 recent Stops + garbage + a record of another type + a 10-day-old Stop
put(slug(A), "s1.jsonl", [
    "this is not json\n",
    "{\"type\": \"user\", \"timestamp\": \"%s\"}\n" % iso(T),
    stop(T - 30, [hook("A.sh", 100), hook("B.sh", 4000)]),
    # C.sh: no durationMs. Seen on the real transcripts: a hook that BLOCKS (exit 2) has none, only its message in hookErrors
    stop(T - 20, [hook("A.sh", 300), hook("B.sh", 2000), hook("C.sh")], errors=["[bash .../C.sh]: blocked"]),
    stop(T - 10, [hook("A.sh", 200), hook("B.sh", 10000), hook("D.sh", raw=-5), hook("E.sh", raw=True), hook("F.sh", raw="abc")]),
    stop(NOW - 10 * 86400, [hook("A.sh", 9000), hook("B.sh", 9000)]),
    # a Stop with no timestamp: its age is unknown, so a window cannot vouch for it (out with --since-days, in without)
    {"type": "system", "subtype": "stop_hook_summary", "hookInfos": [hook("A.sh", 8000)], "hookErrors": [], "preventedContinuation": False},
    "{\"type\": \"system\", \"subtype\": \"stop_hook_summary\", \"hookInfos\": \"not a list\"}\n",
    "{\"type\": \"system\", \"subtype\": \"stop_hook_summary\"\n",                                     # truncated line
])
# a worktree of repo A (Claude names its project dir <slug>--claude-worktrees-<name>): its Stop counts for A
put(slug(A) + "--claude-worktrees-w1", "s2.jsonl", [stop(T, [hook("A.sh", 400), hook("B.sh", 6000)])])
# a repo whose slug starts with A's slug but is another repo: must NOT count
put(slug(A) + "2", "x.jsonl", [stop(T, [hook("A.sh", 123456), hook("B.sh", 123456)])])
put(slug(A) + "-sub", "y.jsonl", [stop(T, [hook("A.sh", 654321)])])
# repo B: one Stop
put(slug(B), "b.jsonl", [stop(T, [hook("A.sh", 50), hook("Z.sh", 70)])])
# repo C: every shape of `command` a hook can have. A /goal condition carries the USER'S TEXT as its command (it may even name a script):
# it must land in one fixed bucket and never be printed. Launchers: bash with a relative path, python3 -I, a bare absolute script.
C = make_repo("repoC")
GOAL = "/giao chạy .agents/devkit/bin/post-fix-gate.py cho xong rồi báo cáo"
put(slug(C), "c.jsonl", [stop(T, [
    hook("A.sh", 1000),
    hook("x", 7000, command=GOAL),
    hook("x", 30, command="🛠️ Kiểm tra nguồn — rebuild dist/ nếu cần ..."),
    hook("x", command="callback"),
    hook("x", 10, command="bash .claude/hooks/session-stop.sh"),
    hook("x", 20, command="python3 -I /opt/kit/scripts/red_proof.py --pending"),
    hook("x", 40, command="/abs/path/direct.sh"),
])])

# runs.jsonl of repo A: two Stop-hook runs (one ran suites, one ended BUSY on the lock), one CLI run that is not a Stop
os.makedirs(os.path.join(A, ".git", "postfix-gate"))


def rec(**kw):
    r = {"v": 1, "ts": "2026-10-15T07:00:00+07:00", "epoch": int(NOW - 120), "project": "x", "mode": "full", "source": "hook", "exit": 0,
         "verdict": "PASS", "deferred": False, "busy": False, "reused_full_pass": False, "n_changed": 1, "n_docs": 0, "docs_only": False,
         "no_test_only": False, "suites": [], "suites_wall_s": 0, "force_full": False, "impacted_run": False}
    r.update(kw)
    return json.dumps(r) + "\n"


with open(os.path.join(A, ".git", "postfix-gate", "runs.jsonl"), "w") as f:
    f.write(rec(total_wall_s=100.0, suites=[["S1", "PASS", 60.0], ["S2", "PASS", 20.0], ["S3", "PASS", None]], suites_wall_s=80.0))
    f.write(rec(total_wall_s=50.0, busy=True, verdict="BUSY", exit=4, suites=[["S1", "BUSY", None]], suites_wall_s=0))
    # busy-flagged but NOT a BUSY verdict, and one suite really ran: its 30 s are suite time, only the other 70 s were spent on the lock
    f.write(rec(total_wall_s=100.0, busy=True, verdict="UNTESTED", exit=2, suites=[["S1", "PASS", 30.0], ["S2", "BUSY", None]], suites_wall_s=30.0))
    f.write(rec(source="cli", total_wall_s=999.0, suites=[["S1", "PASS", 900.0]], suites_wall_s=900.0))
    f.write(rec(epoch=int(NOW - 10 * 86400), total_wall_s=7777.0, suites=[["S1", "PASS", 7000.0]], suites_wall_s=7000.0))
    f.write("garbage line\n")


def snapshot():
    h = hashlib.sha256()
    for base in (PROJ, os.path.join(A, ".git", "postfix-gate")):
        for dp, dn, fn in sorted(os.walk(base)):
            for n in sorted(fn):
                p = os.path.join(dp, n)
                h.update(p.encode())
                h.update(open(p, "rb").read())
                h.update(str(os.stat(p).st_mtime_ns).encode())
    return h.hexdigest()


before = snapshot()
rc, data, err = jsn("--repo", A, "--repo", B, "--projects-dir", PROJ, "--since-days", "2")
ok = chk(rc == 0 and isinstance(data, dict), "json run exits 0 and prints one JSON object", "rc=%s %r" % (rc, err[:300]))
repos = {r["label"]: r for r in (data or {}).get("repos", [])} if ok else {}
ra = repos.get("repoA")
if chk(ra is not None, "repo A is reported under its folder name", str(list(repos))):
    chk(ra["stops"] == 4, "4 Stops in the window (3 main + 1 worktree transcript; the 10-day-old one and the look-alike slugs are out)",
        "stops=%s" % ra["stops"])
    h = ra["hooks"]
    chk(h.get("A.sh", {}).get("n") == 4 and h["A.sh"].get("p50") == 0.2 and h["A.sh"].get("p90") == 0.4 and h["A.sh"].get("max") == 0.4,
        "A.sh over [0.1, 0.2, 0.3, 0.4] s: n 4, p50 0.2, p90 0.4, max 0.4 (nearest rank)", str(h.get("A.sh")))
    chk(h.get("B.sh", {}).get("n") == 4 and h["B.sh"].get("p50") == 4.0 and h["B.sh"].get("p90") == 10.0 and h["B.sh"].get("max") == 10.0,
        "B.sh over [2, 4, 6, 10] s: p50 4, p90 10, max 10", str(h.get("B.sh")))
    chk("C.sh" in h and h["C.sh"].get("n") == 0 and h["C.sh"].get("no_duration") == 1,
        "a hook with no durationMs is counted apart (no_duration 1), not as 0 s", str(h.get("C.sh")))
    chk(all(h.get(k, {}).get("n") == 0 and h[k].get("no_duration") == 1 for k in ("D.sh", "E.sh", "F.sh")),
        "a negative, boolean or text durationMs is junk: counted apart, never in a percentile", str({k: h.get(k) for k in "DEF"}))
    w = ra["stop_wall"]
    chk(w.get("n") == 4 and w.get("p50") == 4.0 and w.get("p90") == 10.0 and w.get("max") == 10.0,
        "slowest hook of each Stop [4, 2, 10, 6] s: p50 4, p90 10, max 10", str(w))
    chk(w.get("with_errors") == 1 and w.get("prevented") == 0, "one Stop carries a hook error (a block), none prevented the continuation", str(w))
    g = ra["gate_hook_runs"]
    chk(g.get("runs") == 3 and g.get("wall_p50") == 100.0 and g.get("wall_p90") == 100.0 and g.get("wall_max") == 100.0,
        "Stop-hook gate runs in the window: 3 (the CLI run and the 10-day-old one are out), wall [50, 100, 100]: p50 100 / p90 100 / max 100", str(g))
    chk(g.get("suite_s") == 110.0 and g.get("lock_wait_s") == 120.0 and g.get("other_s") == 20.0,
        "of 250 s: 110 in suites (80 + the 30 s suite of the busy-flagged run), 120 on the lock (50 + the other 70 s of that run), 20 elsewhere", str(g))
    chk(g.get("busy_runs") == 2 and g.get("busy_verdict_runs") == 1,
        "2 runs carry the busy flag, 1 of them has the BUSY verdict (counted apart: the flag alone does not make a BUSY verdict)", str(g))
    chk(g.get("suite_pct") == 44.0 and g.get("lock_wait_pct") == 48.0 and g.get("other_pct") == 8.0,
        "shares 44.0 % / 48.0 % / 8.0 %", str(g))
    bv = g.get("by_verdict", {})
    chk(bv.get("PASS", {}).get("runs") == 1 and bv["PASS"].get("wall_s") == 100.0 and bv.get("BUSY", {}).get("runs") == 1 and bv["BUSY"].get("wall_s") == 50.0
        and bv.get("UNTESTED", {}).get("runs") == 1 and sorted(bv) == ["BUSY", "PASS", "UNTESTED"],
        "runs by verdict: PASS 1 run / 100 s, BUSY 1 / 50 s, UNTESTED 1 (a hook that blocks has no durationMs, its time is here)", str(bv))
rb = repos.get("repoB") if ok else None
chk(rb is not None and rb["stops"] == 1 and rb["hooks"].get("A.sh", {}).get("max") == 0.05 and rb["hooks"].get("Z.sh", {}).get("max") == 0.07,
    "repo B has its own Stop and its own A.sh (not mixed with repo A's)", str(rb))

rc, out, err = run("--repo", C, "--projects-dir", PROJ)
rc2, dc, err2 = jsn("--repo", C, "--projects-dir", PROJ)
rcc = {r["label"]: r for r in (dc or {}).get("repos", [])}.get("repoC") if dc else None
if chk(rcc is not None, "repo C is reported", str(err2[:200])):
    hc = rcc["hooks"]
    chk(sorted(hc) == ["(callback)", "(non-script hook: /goal text, inline command)", "A.sh", "direct.sh", "red_proof.py", "session-stop.sh"],
        "launchers resolve to the script (bash rel path, python3 -I, bare absolute path); the rest fall into two fixed buckets", str(sorted(hc)))
    ns = hc.get("(non-script hook: /goal text, inline command)", {})
    chk(ns.get("n") == 2 and ns.get("p50") == 0.03 and ns.get("p90") == 7.0 and ns.get("max") == 7.0,
        "the non-script bucket holds the /goal hook and the inline command", str(ns))
    chk(hc.get("(callback)", {}).get("n") == 0 and hc["(callback)"].get("no_duration") == 1, "a callback hook with no duration is counted apart",
        str(hc.get("(callback)")))
leaks = [w for w in ("post-fix-gate", "Kiểm tra", "/giao", "báo cáo") if w in out or w in json.dumps(dc)]
chk(not leaks, "no hook command text other than a script name is ever printed (a /goal hook's text is the user's own)", str(leaks))

# without --since-days the old Stop and the old gate run are in
rc, data, err = jsn("--repo", A, "--projects-dir", PROJ)
ra = {r["label"]: r for r in (data or {}).get("repos", [])}.get("repoA") if data else None
chk(ra is not None and ra["stops"] == 6 and ra["hooks"]["A.sh"]["max"] == 9.0 and ra["hooks"]["A.sh"]["n"] == 6 and ra["gate_hook_runs"]["runs"] == 4
    and ra["gate_hook_runs"]["wall_max"] == 7777.0,
    "no --since-days: all 6 Stops (the old one and the one with no timestamp too) and 4 Stop-hook gate runs",
    str(ra and (ra["stops"], ra["hooks"]["A.sh"], ra["gate_hook_runs"])))

# a repo with no transcript dir, a path that is not a git repo
rc, data, err = jsn("--repo", EMPTY, "--repo", NOGIT, "--projects-dir", PROJ)
rr = {r["label"]: r for r in (data or {}).get("repos", [])} if data else {}
chk(rc == 0 and rr.get("repoE", {}).get("stops") == 0 and rr.get("plain", {}).get("stops") == 0,
    "repos with no transcripts report 0 Stops and exit 0", "rc=%s %s" % (rc, str(rr)[:200]))
chk(rr.get("plain", {}).get("gate_hook_runs") is None and rr.get("plain", {}).get("gate_note"),
    "a path that is not a git repo has no gate section, with a reason", str(rr.get("plain")))
rc, out, err = run("--repo", A, "--projects-dir", os.path.join(TMP, "no-such-dir"))
chk(rc == 0 and "0 Stops" in out, "a missing projects dir is no data, not a crash", "rc=%s %r" % (rc, (out + err)[:200]))

# the text table: header, one row per hook with the repo, numbers in seconds
rc, out, err = run("--repo", A, "--repo", B, "--projects-dir", PROJ, "--since-days", "2")
chk(rc == 0 and re.search(r"^hook\s+repo\s+Stops\s+p50\s+p90\s+max", out, re.M) is not None, "text table has the header hook / repo / Stops / p50 / p90 / max",
    out[:300])
chk(re.search(r"^B\.sh\s+repoA\s+4\s+4\.00\s+10\.00\s+10\.00", out, re.M) is not None,
    "row `B.sh repoA 4 4.00 10.00 10.00`", "\n".join(l for l in out.splitlines() if "B.sh" in l))
chk(re.search(r"waiting for the lock \(test_run\.lock\) 48\.0 % \(120 s in 2 busy-flagged runs, 1 of them with the BUSY verdict\)", out) is not None,
    "the text names the lock-wait share (48.0 %, 120 s, 2 busy-flagged runs, 1 BUSY verdict)", out[-700:])

# bad arguments
rc, out, err = run("--since-days", "abc")
chk(rc == 2, "a bad --since-days is a usage error (exit 2)", "rc=%s" % rc)

# read-only: nothing under the projects dir or the repo's gate dir changed
chk(snapshot() == before, "no file read was written (transcripts and runs.jsonl byte-identical, mtimes unchanged)")

print(("❌ test_stop_hook_times: %d failed" % fails) if fails else "✅ test_stop_hook_times: all checks passed")
sys.exit(1 if fails else 0)
PYEND
