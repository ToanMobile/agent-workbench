#!/usr/bin/env bash
# Regression test: scripts/governance/gate_runs_report.py reads <git-common-dir>/postfix-gate/runs.jsonl (written by
# bin/post-fix-gate.py, see test_gate_run_log.sh) and prints, per repo, the docs-only --full runs and their cost, then ONE decision line:
#   RECOMMEND W1-g/rule change   when >= 10 docs-only --full runs RAN suites and their wall time sums to >= 30 min
#   NOT WORTH IT YET             otherwise (with the numbers)
# Round 2: deferred and BUSY runs are in no total (10 deferred FAIL docs-only runs must not RECOMMEND); the covered date range, the
# --since and the rotation warnings; one repo through a link counts once; a FIFO as runs.jsonl does not block; absurd records (epoch 1e300,
# a 1e9-second run, NaN, negative) are ignored, never crash; the "totals are a LOWER bound" note.
# Synthetic data in throw-away repos: the thresholds both ways and exactly at the edge (10 runs / 1800 s), runs that must NOT count
# (re-used, deferred, BUSY, impacted, code, no suite run), median / p90 / hours, malformed lines of every kind (garbage, truncated, wrong
# types, NaN, invalid UTF-8, 100000-deep nesting) ignored and counted, two repos (the decision sums them; one repo given twice counts
# once), an empty / missing log, a repo that is not a git repo, --since, per-day counts, suites per id, the default repo (cwd), a linked
# worktree (its runs live in the common dir), a bad --since.
#   RPT_KIT=<devkit dir>   test another copy of the kit (one without the script: RED; a mutant: must go red)
#   RPT_PY=<python>        interpreter (default python3; try /usr/bin/python3 = 3.9)
# bash 3.2 and Python 3.9 compatible; python stdlib only.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KIT="${RPT_KIT:-$DEVKIT_DIR}"
PYBIN="${RPT_PY:-python3}"
SCRIPT="$KIT/scripts/governance/gate_runs_report.py"
TMP="$(mktemp -d)"
case "$TMP" in /?*) [ -d "$TMP" ] || TMP="" ;; *) TMP="" ;; esac
if [ -z "$TMP" ]; then echo "✖ no temp dir (mktemp failed): nothing was run" >&2; exit 1; fi
trap 'rm -rf "$TMP"' EXIT
"$PYBIN" -I - "$SCRIPT" "$TMP" <<'PY'
import json, os, re, subprocess, sys, time

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
    root = os.path.join(TMP, name)
    os.makedirs(root)
    git(root, "init", "-q", ".")
    git(root, "config", "user.email", "t@t")
    git(root, "config", "user.name", "t")
    with open(root + "/f", "w") as f:
        f.write("x\n")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "init")
    return root


def log_path(root):
    d = os.path.join(root, git(root, "rev-parse", "--git-common-dir"), "postfix-gate")
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, "runs.jsonl")


NOW = time.time()


def rec(wall=100.0, **kw):
    """A valid line: a docs-only --full run that ran two suites (override anything with kw)."""
    r = {"v": 1, "ts": "2026-10-06T09:00:00+07:00", "epoch": int(NOW - 3600), "project": "p", "mode": "full", "source": "cli", "exit": 0,
         "verdict": "PASS", "deferred": False, "busy": False, "reused_full_pass": False, "n_changed": 1, "n_docs": 1, "docs_only": True,
         "no_test_only": True, "n_code": 0, "suites": [["REG-A", "PASS", wall * 0.4], ["REG-B", "PASS", wall * 0.5]],
         "suites_wall_s": wall * 0.9, "total_wall_s": wall, "force_full": True, "impacted_run": False}
    r.update(kw)
    return r


def write(root, records, raw=()):
    with open(log_path(root), "wb") as f:
        for r in records:
            f.write((json.dumps(r) + "\n").encode())
        for b in raw:
            f.write(b + b"\n")


def report(*args, cwd=None):
    p = subprocess.run([PY, SCRIPT] + list(args), cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")


def decision(out):
    lines = [l for l in out.splitlines() if l.startswith(("RECOMMEND", "NOT WORTH IT YET"))]
    return lines


def verdict_of(out):
    d = decision(out)
    return (d[0].split(" - ")[0] if len(d) == 1 else "ZERO-OR-MANY:%r" % d)


if not os.path.exists(SCRIPT):
    chk(False, "the report script exists", SCRIPT)
    print("\ngate runs report: %d FAILED" % fails)
    sys.exit(1)

# ── thresholds, both ways and at the edge ────────────────────────────────────────────────────────────────────
for i, (label, n, wall, want) in enumerate((("10 runs of 180 s = exactly 30 min", 10, 180.0, "RECOMMEND W1-g/rule change"),
                             ("10 runs of 179.9 s = 29.98 min", 10, 179.9, "NOT WORTH IT YET"),
                             ("9 runs of 1000 s (long, but 9)", 9, 1000.0, "NOT WORTH IT YET"),
                             ("12 runs of 300 s", 12, 300.0, "RECOMMEND W1-g/rule change"),
                             ("10 runs of 10 s (many, cheap)", 10, 10.0, "NOT WORTH IT YET"))):
    root = make_repo("thr%d" % i)
    write(root, [rec(wall=wall) for _ in range(n)])
    rc, out, err = report("--repo", root)
    chk(rc == 0 and verdict_of(out) == want and decision(out)[-1] == out.rstrip("\n").splitlines()[-1], "%s: %s, as the last line" % (label, want),
        "rc %s, %r\n%s" % (rc, decision(out), out[-400:]))

# ── what must NOT count ─────────────────────────────────────────────────────────────────────────────────────
root = make_repo("noise")
good = [rec(wall=200.0) for _ in range(9)]                                                  # 9 counted: one short of the threshold
noise = ([rec(wall=900.0, verdict="REUSED", reused_full_pass=True, suites=[["REG-A", "PASS", None], ["REG-B", "PASS", None]]) for _ in range(5)]
         + [rec(wall=900.0, verdict="DEFERRED", deferred=True, exit=5) for _ in range(5)]
         + [rec(wall=900.0, verdict="BUSY", busy=True, exit=4, suites=[["REG-A", "UNTESTED", None]]) for _ in range(5)]
         + [rec(wall=900.0, mode="impacted", force_full=False) for _ in range(5)]
         + [rec(wall=900.0, docs_only=False, no_test_only=False, n_code=2) for _ in range(5)]
         + [rec(wall=900.0, suites=[["REG-A", "PASS", None]]) for _ in range(5)])               # a full docs-only run where no suite ran
write(root, good + noise)
rc, out, err = report("--repo", root)
chk(verdict_of(out) == "NOT WORTH IT YET" and "docs-only --full runs that ran suites: 9 " in out,
    "re-used, deferred, BUSY, impacted, code and no-suite-ran runs do not count: 9 counted, NOT WORTH IT YET", out[-500:])
chk("docs_only 19 + " in out and "docs_only --full runs: 19 (" in out, "the docs_only --full total is 9 + 5 re-used + 5 no-suite = 19 (deferred and BUSY are in no total)", out)
chk("deferred 5 and BUSY 5 (not full-cost runs: in no total below)" in out and "re-used 5; suites actually run in 9 of them" in out,
    "deferred and BUSY runs are counted apart; re-used runs are counted", out)
write(root, good + [rec(wall=200.0)] + noise)
rc, out, err = report("--repo", root)
chk(verdict_of(out) == "RECOMMEND W1-g/rule change", "the 10th counted run (1800 s) flips the decision, noise or not", out[-300:])

# ── median / p90 / hours / suites / per day ───────────────────────────────────────────────────────────────
root = make_repo("stats")
d1, d2 = int(NOW - 10 * 3600), int(NOW - 3 * 86400 - 3600)
write(root, [rec(wall=w, epoch=(d1 if i < 7 else d2)) for i, w in enumerate(range(10, 101, 10))]
      + [rec(wall=5.0, epoch=d1, suites=[["REG-C", "PASS", 2.0]])])
rc, out, err = report("--repo", root)
m = re.search(r"wall seconds of those (\d+): total (\d+) \(([\d.]+) h\), median (\d+), p90 (\d+)", out)
chk(m and m.groups() == ("11", "555", "0.15", "50", "90"), "11 runs [5,10..100]: total 555 s = 0.15 h, median 50, p90 90 (nearest rank)", repr(m and m.groups()) + out)
chk("suites run: REG-A 10, REG-B 10, REG-C 1" in out, "suites run: count per id", out)
chk(time.strftime("%Y-%m-%d", time.localtime(d1)) + " 8" in out and time.strftime("%Y-%m-%d", time.localtime(d2)) + " 3" in out,
    "per-day counts of the docs-only --full runs (8 and 3)", out)
rc, out, err = report("--repo", root, "--since", "2")
chk("docs_only --full runs: 8 (" in out and "docs_only --full runs: 11" not in out, "--since 2 keeps the runs of the last 2 days only (8 of 11)", out)

# ── malformed lines are ignored and counted, the rest still reads ──────────────────────────────────────────
root = make_repo("bad")
raw = [b"not json", b'{"v":1', b"[]", b"null", b"42", b'"x"', b"", b"   ", json.dumps(rec(v=2)).encode(), b'{"v":1}',
       json.dumps(rec(mode=5)).encode(), json.dumps(rec(suites="x")).encode(), json.dumps(rec(epoch="now")).encode(),
       json.dumps(rec(suites=[["a", "PASS", "x"]])).encode(), json.dumps(rec(docs_only="yes")).encode(),
       json.dumps(rec()).replace('"epoch": ', '"epoch": NaN, "e2": ').encode(), b"\xff\xfe invalid utf8 \x80",
       b"[" * 100000, json.dumps(rec(suites=[["a", "PASS", True]])).encode(), json.dumps(rec(suites=[[1, "PASS", 2.0]])).encode()]
write(root, [rec(wall=300.0) for _ in range(3)], raw)
rc, out, err = report("--repo", root)
chk(rc == 0 and not err.strip() and "3 valid, 18 ignored" in out and verdict_of(out) == "NOT WORTH IT YET",
    "malformed lines (garbage, truncated, wrong types, NaN, invalid UTF-8, deep nesting) ignored: 3 valid, 18 ignored, no crash", "rc %s err %r\n%s" % (rc, err[-200:], out[:300]))

# ── two repos, the same repo twice, empty / missing / not a repo ────────────────────────────────────────────
a, b = make_repo("two_a"), make_repo("two_b")
write(a, [rec(wall=100.0) for _ in range(6)])    # 10 min
write(b, [rec(wall=250.0) for _ in range(6)])    # 25 min: alone each is short of both thresholds, together 12 runs and 35 min
rc, out, err = report("--repo", a)
chk(verdict_of(out) == "NOT WORTH IT YET", "one repo with 6 runs: NOT WORTH IT YET", out[-200:])
for order in ((a, b), (b, a)):
    rc, out, err = report("--repo", order[0], "--repo", order[1])
    chk(verdict_of(out) == "RECOMMEND W1-g/rule change" and sum(1 for l in out.splitlines() if l.startswith("== ")) == 2 and "runs that ran suites: 12 " in out
        and "35.0 min" in out, "two repos (%s first): each section printed, the decision sums both (12 runs, 35 min)" % os.path.basename(order[0]), out[-300:])
rc, out, err = report("--repo", a, "--repo", a)
chk(verdict_of(out) == "NOT WORTH IT YET" and "runs that ran suites: 6 " in out, "the same repo twice counts once", out[-300:])
empty = make_repo("empty")
write(empty, [])
rc, out, err = report("--repo", empty)
chk(rc == 0 and verdict_of(out) == "NOT WORTH IT YET" and "runs that ran suites: 0 " in out, "an empty log: NOT WORTH IT YET with 0 runs", out)
nolog = make_repo("nolog")
rc, out, err = report("--repo", nolog)
chk(rc == 0 and verdict_of(out) == "NOT WORTH IT YET" and "no data" in out, "no runs.jsonl yet: no data, NOT WORTH IT YET", out)
notgit = os.path.join(TMP, "notgit")
os.makedirs(notgit)
rc, out, err = report("--repo", notgit, "--repo", a)
chk(rc == 0 and "not a git repository" in out and "runs that ran suites: 6 " in out, "a directory that is not a repo is reported, the others still read", out)

# ── default repo = cwd, a linked worktree, bad arguments ───────────────────────────────────────────────────
rc, out, err = report(cwd=a)
chk(rc == 0 and "runs that ran suites: 6 " in out, "no --repo: the repo of the current directory", out[-300:])
wt = os.path.join(TMP, "two_a_wt")
git(a, "worktree", "add", "-q", "-b", "wt", wt)
rc, out, err = report("--repo", wt)
chk(rc == 0 and "runs that ran suites: 6 " in out, "a linked worktree reads the common dir's log", out[-300:])
for bad in ("-1", "nan", "inf", "abc"):
    rc, out, err = report("--repo", a, "--since", bad)
    chk(rc == 2, "--since %s is refused (exit 2)" % bad, "rc %s" % rc)

# ── round 2 ───────────────────────────────────────────────────────────────────────────────────────────────────────────
NOWI = int(NOW)

# deferred and BUSY runs pay no full cost: 10 deferred FAIL docs-only runs (suites with seconds: impacted only) must not recommend anything
root = make_repo("deferred")
write(root, [rec(wall=400.0, verdict="FAIL", exit=1, deferred=True) for _ in range(10)])
rc, out, err = report("--repo", root)
chk(verdict_of(out) == "NOT WORTH IT YET" and "runs that ran suites: 0 " in out and "docs_only --full runs: 0 " in out,
    "10 deferred FAIL docs-only runs: counted nowhere, NOT WORTH IT YET", out[-500:])
write(root, [rec(wall=400.0, verdict="FAIL", exit=1, busy=True) for _ in range(10)])
rc, out, err = report("--repo", root)
chk(verdict_of(out) == "NOT WORTH IT YET" and "runs that ran suites: 0 " in out, "10 BUSY-flagged FAIL docs-only runs: counted nowhere", out[-500:])

# the covered range, the --since warning, the rotation warning
root = make_repo("range")
t_first, t_last = NOWI - 2 * 86400, NOWI - 3600
write(root, [rec(wall=100.0, epoch=t_first), rec(wall=100.0, epoch=t_last)])
rc, out, err = report("--repo", root)
want_first, want_last = time.strftime("%Y-%m-%d %H:%M", time.localtime(t_first)), time.strftime("%Y-%m-%d %H:%M", time.localtime(t_last))
chk("covered: %s .. %s (2.0 days of runs in the file)" % (want_first, want_last) in out, "the covered date range of the file is printed", out)
rc, out, err = report("--repo", root, "--since", "10")
chk("WARNING: --since 10 asks for runs since" in out and "the window is shorter than asked" in out, "--since 10 on a log of 2 days: a warning", out)
rc, out, err = report("--repo", root, "--since", "1.5")
chk("WARNING: --since" not in out, "--since 1.5 on a log that covers it: no warning", out)
chk("WARNING: the file is" not in out, "a small file: no rotation warning", out)
big = []
pad = rec(wall=100.0, epoch=NOWI - 7200)
pad["project"] = "p" * 60
line_len = len(json.dumps(pad)) + 1
write(root, [pad for _ in range(1000000 // line_len + 10)])
rc, out, err = report("--repo", root)
chk("WARNING: the file is" in out and "older runs were probably dropped" in out, "a file at the rotation size: the truncation warning", out[:600])

# one repo through a link or as a worktree counts once
a2 = make_repo("dedupe")
write(a2, [rec(wall=100.0) for _ in range(6)])
link = os.path.join(TMP, "dedupe_link")
os.symlink(a2, link)
rc, out, err = report("--repo", a2, "--repo", link)
chk(sum(1 for l in out.splitlines() if l.startswith("== ")) == 1 and "runs that ran suites: 6 " in out, "the same repo through a symlink counts once", out[-400:])
wt2 = os.path.join(TMP, "dedupe_wt")
git(a2, "worktree", "add", "-q", "-b", "wt2", wt2)
rc, out, err = report("--repo", a2, "--repo", wt2, "--repo", link)
chk(sum(1 for l in out.splitlines() if l.startswith("== ")) == 1 and "runs that ran suites: 6 " in out, "a repo, its worktree and a link to it count once", out[-400:])

# a FIFO (or a directory) as runs.jsonl: no block, no crash
fifo_repo = make_repo("fifo")
os.mkfifo(log_path(fifo_repo))
try:
    p = subprocess.run([PY, SCRIPT, "--repo", fifo_repo], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    chk(p.returncode == 0 and b"no data" in p.stdout and decision(p.stdout.decode()), "a FIFO as runs.jsonl: reported as no data, does not block", p.stdout.decode()[-300:])
except subprocess.TimeoutExpired:
    chk(False, "a FIFO as runs.jsonl: reported as no data, does not block", "the report hung")
dir_repo = make_repo("dirlog")
os.makedirs(log_path(dir_repo))
rc, out, err = report("--repo", dir_repo)
chk(rc == 0 and "no data" in out, "a directory as runs.jsonl: no data", out[-200:])

# absurd records are ignored and counted, never a crash
root = make_repo("absurd")
bad_records = [rec(epoch=1e300), rec(epoch=-5), rec(epoch=NOWI + 10 * 86400), rec(wall=1e9), rec(wall=86401.0), rec(wall=-3.0),
               rec(suites=[["A", "PASS", 1e9]]), rec(suites=[["A", "PASS", -1.0]]), rec(total_wall_s=float("inf")), rec(total_wall_s=float("nan")),
               rec(suites_wall_s=1e12), rec(total_wall_s="9"), rec(total_wall_s=True)]
write(root, [rec(wall=100.0)] + bad_records)
rc, out, err = report("--repo", root)
chk(rc == 0 and not err.strip() and "1 valid, %d ignored" % len(bad_records) in out, "absurd records (epoch 1e300 / past / future, a run of 1e9 s, NaN, inf, negative, wrong type) are ignored and counted: no crash",
    "rc %s err %r\n%s" % (rc, err[-300:], out[:300]))
# field-by-field junk: whatever one field holds, the report ends with rc 0 and no traceback
junk = [None, -1, 2 ** 70, 1e999, "x", [], {}, True, [[]], {"a": 1}]
fields = ["v", "epoch", "mode", "source", "exit", "verdict", "deferred", "busy", "reused_full_pass", "docs_only", "no_test_only", "suites",
          "suites_wall_s", "total_wall_s"]
lines = []
for f in fields:
    for j in junk:
        r = rec()
        r[f] = j
        lines.append(r)
write(root, [rec(wall=100.0)] + lines)
rc, out, err = report("--repo", root)
chk(rc == 0 and "Traceback" not in err and decision(out), "%d single-field junk records: rc 0, no traceback" % len(lines), "rc %s err %r" % (rc, err[-300:]))

# the lower-bound note is printed, just above the decision
rc, out, err = report("--repo", root)
ls = out.rstrip("\n").splitlines()
chk(len(ls) >= 2 and ls[-2].startswith("NOTE: runs killed by the hook timeout") and "are NOT logged" in ls[-2] and "LOWER bound" in ls[-2],
    "one NOTE line: runs killed by the hook timeout, exit 2/3 and --staged are NOT logged, the totals are a LOWER bound", ls[-3:])

print()
if fails:
    print("gate runs report: %d FAILED" % fails)
    sys.exit(1)
print("gate runs report: all checks passed")
PY
