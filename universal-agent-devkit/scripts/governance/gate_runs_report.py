#!/usr/bin/env python3
"""Report on the post-fix gate's run log: how often is a --full run triggered by a documentation-only change, and what does it cost?

    python3 gate_runs_report.py [--since DAYS] [--repo PATH ...]

Reads <git-common-dir>/postfix-gate/runs.jsonl of each repo (default: the repo of the current directory; --repo may repeat; the same repo
given twice, through a link, or as one of its worktrees counts once), written by bin/post-fix-gate.py for every `--run-tests` run (one JSON
line, data only: nothing reads it for a decision). Read-only; stdlib only; Python 3.9. It never blocks (a FIFO or a link-to-nothing at the
path is "no data") and never crashes on a malformed file: lines that are not JSON, not an object, v != 1, of the wrong field types, with an
epoch outside 2000..tomorrow, or with a time that is not finite or above 24 h are ignored and counted.

For each repo it prints: the covered date range of the file, warnings (--since asks for more than the file covers; the file is near the
gate's rotation cap, so older runs were probably dropped), runs per mode and source, and for the --full runs: how many were docs_only
(every changed file, a rename's source included, is documentation: .md/.rst/.adoc, LICENSE-type names), no_test_only (every changed file
needs no test: docs, agent state, proof images, logs) and the rest; for the docs_only --full runs: the total, median and p90 wall
seconds, the hours they cost, which suites ran in them (count per id), how many were re-used (the full receipt served) and the count per
day. A run that was DEFERRED (a sibling session was active: only impacted suites ran) or BUSY (the test lock was held) did not pay the
full cost: it is counted apart and is in no total.

DECISION RULE (fixed thresholds; the script prints ONE decision line at the end and decides nothing else):
  a "counted" run = a docs_only --full run that is not deferred and not BUSY, with verdict PASS / FAIL / UNTESTED (not REUSED) and at least
  one suite with seconds (a suite that really ran in that run); its cost = total_wall_s (suites_wall_s when absent).
  RECOMMEND W1-g/rule change   if  counted runs >= MIN_RUNS (10)  AND  their summed wall >= MIN_WALL_S (1800 s = 30 min)  over the window
  NOT WORTH IT YET             otherwise, with the numbers.
With several repos the decision uses the sums over all of them. The totals are a LOWER bound: runs killed by the hook timeout, argument
errors, "nothing to audit" (exit 3) and --staged are never logged.
"""
import argparse
import json
import math
import os
import stat
import statistics
import subprocess
import sys
import time

MIN_RUNS = 10
MIN_WALL_S = 30 * 60
COUNTED_VERDICTS = ("PASS", "FAIL", "UNTESTED")
MAX_RUN_S = 24 * 3600            # a gate run longer than this in a record is forged or broken: the record is ignored
EPOCH_MIN = 946684800            # 2000-01-01
MAX_READ_BYTES = 16 * 1024 * 1024  # the gate keeps the file under ~1.25 MiB; a bigger one is read from its tail only
ROTATION_HINT_BYTES = 1000000    # the gate cuts the file from 1.25 MiB to <= 1 MiB: a file this big has probably been rotated
REQUIRED = {"mode": str, "source": str, "verdict": str, "docs_only": bool, "no_test_only": bool, "deferred": bool, "busy": bool,
            "reused_full_pass": bool, "suites": list}


def num(x):
    """A finite number or None (bool, NaN, inf and anything else are not numbers here)."""
    if isinstance(x, bool) or not isinstance(x, (int, float)):
        return None
    try:
        return float(x) if math.isfinite(x) else None
    except OverflowError:
        return None


def seconds_ok(x):
    v = num(x)
    return v is not None and 0 <= v <= MAX_RUN_S


def parse_line(raw, now):
    """The record, or None when the line is malformed or absurd."""
    try:
        r = json.loads(raw)
    except (ValueError, RecursionError):
        return None
    if not isinstance(r, dict) or r.get("v") != 1:
        return None
    for key, typ in REQUIRED.items():
        if not isinstance(r.get(key), typ):
            return None
    epoch = num(r.get("epoch"))
    if epoch is None or not EPOCH_MIN <= epoch <= now + 86400:
        return None
    for key in ("total_wall_s", "suites_wall_s"):
        if key in r and not seconds_ok(r[key]):
            return None
    for s in r["suites"]:
        if not (isinstance(s, list) and len(s) == 3 and isinstance(s[0], str) and (s[2] is None or seconds_ok(s[2]))):
            return None
    return r


def log_file(repo):
    """(path of runs.jsonl, identity of the common git dir, problem) for a repo path (git rev-parse --git-common-dir: a worktree and the
    repo it belongs to give the same dir). The identity is (st_dev, st_ino): a link or another spelling of the path is the same repo."""
    try:
        res = subprocess.run(["git", "-C", repo, "rev-parse", "--git-common-dir"], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as e:
        return None, None, "cannot run git (%s)" % e.__class__.__name__
    out = res.stdout.strip()
    if res.returncode != 0 or not out:
        return None, None, "not a git repository"
    common = os.path.abspath(os.path.join(repo, out))
    try:
        st = os.stat(common)
        ident = (st.st_dev, st.st_ino)
    except OSError:
        ident = os.path.realpath(common)
    return os.path.join(common, "postfix-gate", "runs.jsonl"), ident, None


def read_runs(path, since_epoch, now):
    """dict: recs (valid records in the window), valid, ignored, first / last epoch of ALL valid records, size, capped.
    Raises OSError / ValueError when the path is not a regular file (never opened blocking)."""
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0))
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            raise ValueError("not a regular file")
        f = os.fdopen(fd, "rb")
    except BaseException:
        os.close(fd)
        raise
    out = {"recs": [], "valid": 0, "ignored": 0, "first": None, "last": None, "size": st.st_size, "capped": False}
    with f:
        if st.st_size > MAX_READ_BYTES:
            f.seek(st.st_size - MAX_READ_BYTES)
            f.readline()   # the first line of a tail read starts mid-line
            out["capped"] = True
        for raw in f:
            if not raw.strip():
                continue
            r = parse_line(raw.decode("utf-8", "replace"), now)
            if r is None:
                out["ignored"] += 1
                continue
            out["valid"] += 1
            e = num(r["epoch"])
            out["first"] = e if out["first"] is None else min(out["first"], e)
            out["last"] = e if out["last"] is None else max(out["last"], e)
            if since_epoch is None or e >= since_epoch:
                out["recs"].append(r)
    return out


def wall(r):
    w = num(r.get("total_wall_s"))
    return w if w is not None else (num(r.get("suites_wall_s")) or 0.0)


def excluded(r):
    """Deferred (only impacted suites ran) and BUSY (the lock was held) runs did not pay the full cost."""
    return r["deferred"] or r["busy"] or r["verdict"] in ("DEFERRED", "BUSY")


def counted(r):
    """r is a docs_only --full run that is not excluded: did it pay for suites (see the decision rule above)?"""
    return r["verdict"] in COUNTED_VERDICTS and any(s[2] is not None for s in r["suites"])


def p90(values):
    s = sorted(values)
    return s[max(math.ceil(0.9 * len(s)) - 1, 0)]


def stamp(epoch):
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(epoch))


def day(r):
    return time.strftime("%Y-%m-%d", time.localtime(num(r["epoch"])))


def fmt_counts(counter):
    return ", ".join("%s %d" % (k, counter[k]) for k in sorted(counter)) or "none"


def report_repo(label, data, since_days, now, out):
    """Prints one repo's section; returns (counted runs, their summed wall seconds)."""
    recs = data["recs"]
    out.append("== %s ==" % label)
    out.append("lines: %d valid, %d ignored (malformed), %d in the window; file %d KB%s"
               % (data["valid"], data["ignored"], len(recs), data["size"] // 1024, " (only its last %d MB was read)" % (MAX_READ_BYTES >> 20) if data["capped"] else ""))
    if data["first"] is not None:
        span = (data["last"] - data["first"]) / 86400.0
        out.append("covered: %s .. %s (%.1f days of runs in the file)" % (stamp(data["first"]), stamp(data["last"]), span))
        if since_days is not None and data["first"] > now - since_days * 86400 + 3600:
            out.append("WARNING: --since %g asks for runs since %s, but the file starts at %s: the window is shorter than asked (%.1f days)"
                       % (since_days, stamp(now - since_days * 86400), stamp(data["first"]), (now - data["first"]) / 86400.0))
    else:
        out.append("covered: no valid run in the file")
    if data["size"] >= ROTATION_HINT_BYTES or data["capped"]:
        out.append("WARNING: the file is %d KB, at the size the gate cuts it to (it rotates from 1.25 MiB to <= 1 MiB): older runs were probably dropped,"
                   " so the covered range above is all that is left" % (data["size"] // 1024))
    by_mode = {}
    for r in recs:
        by_mode.setdefault(r["mode"], {}).setdefault(r["source"], 0)
        by_mode[r["mode"]][r["source"]] += 1
    out.append("runs per mode and source: " + (", ".join("%s %d (%s)" % (m, sum(by_mode[m].values()), fmt_counts(by_mode[m]))
                                                       for m in sorted(by_mode)) or "none"))
    full_all = [r for r in recs if r["mode"] == "full"]
    skipped = [r for r in full_all if excluded(r)]
    full = [r for r in full_all if not excluded(r)]
    docs = [r for r in full if r["docs_only"]]
    no_test = [r for r in full if r["no_test_only"] and not r["docs_only"]]
    out.append("full-mode runs: %d, of which deferred %d and BUSY %d (not full-cost runs: in no total below); the other %d = docs_only %d + other"
               " no-test-only %d + code or mixed %d" % (len(full_all), sum(1 for r in skipped if r["deferred"] or r["verdict"] == "DEFERRED"),
                                                       sum(1 for r in skipped if r["busy"] or r["verdict"] == "BUSY"), len(full), len(docs),
                                                       len(no_test), len(full) - len(docs) - len(no_test)))
    verdicts = {}
    for r in docs:
        key = "reused" if r["verdict"] == "REUSED" or r["reused_full_pass"] else r["verdict"].lower()
        verdicts[key] = verdicts.get(key, 0) + 1
    counted_runs = [r for r in docs if counted(r)]
    walls = [wall(r) for r in counted_runs]
    out.append("docs_only --full runs: %d (outcome: %s)" % (len(docs), fmt_counts(verdicts)))
    out.append("  re-used %d; suites actually run in %d of them"
               % (sum(1 for r in docs if r["verdict"] == "REUSED" or r["reused_full_pass"]), len(counted_runs)))
    if walls:
        out.append("  wall seconds of those %d: total %.0f (%.2f h), median %.0f, p90 %.0f"
                   % (len(walls), sum(walls), sum(walls) / 3600.0, statistics.median(walls), p90(walls)))
    else:
        out.append("  wall seconds: no docs_only --full run that ran suites")
    suite_counts = {}
    for r in counted_runs:
        for s in r["suites"]:
            if s[2] is not None:
                suite_counts[s[0]] = suite_counts.get(s[0], 0) + 1
    out.append("  suites run: " + fmt_counts(suite_counts))
    days = {}
    for r in docs:
        days[day(r)] = days.get(day(r), 0) + 1
    out.append("  per day: " + fmt_counts(days))
    out.append("")
    return len(counted_runs), sum(walls)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Report on the post-fix gate run log (runs.jsonl): docs-only --full runs and their cost")
    ap.add_argument("--since", type=float, metavar="DAYS", help="only runs of the last DAYS days (default: the whole log)")
    ap.add_argument("--repo", action="append", metavar="PATH", help="a repo to read (repeatable; default: the repo of the current directory)")
    args = ap.parse_args(argv)
    if args.since is not None and not (math.isfinite(args.since) and 0 <= args.since <= 36500):
        ap.error("--since must be a number of days between 0 and 36500")
    now = time.time()
    since_epoch = None if args.since is None else now - args.since * 86400
    out, seen = [], set()
    total_runs, total_wall = 0, 0.0
    out.append("Gate run log report, window: " + ("the whole log" if args.since is None else "last %g days" % args.since))
    out.append("")
    for repo in args.repo or ["."]:
        path, ident, problem = log_file(repo)
        if path is None:
            out.append("== %s ==\n%s: no data\n" % (repo, problem))
            continue
        if ident in seen:
            continue
        seen.add(ident)
        try:
            data = read_runs(path, since_epoch, now)
        except (OSError, ValueError) as e:
            out.append("== %s ==\n%s: no data (%s)\n" % (repo, path, (getattr(e, "strerror", None) or str(e) or e.__class__.__name__)))
            continue
        try:
            n, w = report_repo(repo, data, args.since, now, out)
        except Exception as e:  # noqa: BLE001 - one unreadable repo must not hide the others
            out.append("== %s ==\ncannot be summarised (%s): no data\n" % (repo, e.__class__.__name__))
            continue
        total_runs += n
        total_wall += w
    numbers = ("docs-only --full runs that ran suites: %d (need >= %d), their wall: %.1f min (need >= %.0f min)"
               % (total_runs, MIN_RUNS, total_wall / 60.0, MIN_WALL_S / 60.0))
    out.append("NOTE: runs killed by the hook timeout, exit 2/3 before the verdict (argument errors, nothing to audit) and --staged are NOT logged:"
               " the totals are a LOWER bound")
    out.append(("RECOMMEND W1-g/rule change - " if total_runs >= MIN_RUNS and total_wall >= MIN_WALL_S else "NOT WORTH IT YET - ") + numbers)
    sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
