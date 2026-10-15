#!/usr/bin/env python3
"""stop_hook_times.py [--repo PATH ...] [--projects-dir DIR] [--since-days N] [--json]: how long each Stop hook really takes, per repo.

The hooks log no duration of their own (their logs carry one END time per line), so the numbers come from two records that already exist:
  * Claude Code writes a `system` / `stop_hook_summary` record into the session transcript at every Stop, with hookInfos[] = {command,
    durationMs} per hook: <projects-dir>/<slug of the repo path>/*.jsonl, and <slug>--claude-worktrees-<name>/*.jsonl for its worktrees
    (slug = every character that is not a letter or digit replaced by "-"). Only hookInfos[].command / durationMs, the Stop's time and
    its preventedContinuation flag are read. A command that is not a script (a /goal condition carries the user's own text) is
    never kept: it is counted under one fixed name.
  * <git-common-dir>/postfix-gate/runs.jsonl (bin/post-fix-gate.py), the records with source=hook = the Stop hook's gate run: wall seconds, the
    seconds of each suite that ran, busy=true when the run ended waiting for .claude/audit-gate/test_run.lock.

Prints, per repo and per hook: Stops, p50 / p90 / max seconds (nearest rank, the same rule as gate_runs_report.p90), then the slowest hook of
each Stop (the hooks of a Stop run side by side, so that is the floor of the Stop's wall; a Stop is never faster) and, for the gate runs
of the Stop hook, the share of their wall time spent in suites / waiting for the lock / elsewhere (suite seconds are capped at the run's wall:
suites can run side by side). A hook with a missing, negative, boolean, text or absurd (> 24 h) durationMs is counted as `no-duration` and
is in no percentile. Measured 15/10 on the real transcripts: a hook that BLOCKS (exit 2) has no durationMs, only its message in hookErrors
(OfficeReader: 245 regression_gate records without a duration, each with a hookErrors entry; the preventedContinuation flag is never
set by a block), so the percentiles of a gate are those of its runs that did NOT block; the time of the blocking runs is in the gate
section's by-verdict line (FAIL / UNTESTED). Records written since 2026-10-15 also carry `steps` (seconds per phase of the gate run: git, analysis,
static, select, cache, lock, suites, verdict, receipt, checklist, report, and the vacuity re-runs inside suites): the gate section then prints their
split too, over the runs that have them (an older record, or one whose steps are not finite seconds, only gives the suites / lock / other split).
Read-only; stdlib only; Python 3.9. A missing or odd file is "no data", never a crash.
"""
import argparse
import calendar
import json
import math
import os
import re
import subprocess
import sys
import time

KIT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.dont_write_bytecode = True   # python -I ignores PYTHONDONTWRITEBYTECODE: leave no .pyc in the kit
sys.path.insert(0, os.path.join(KIT, "scripts", "governance"))
import gate_runs_report as grr  # noqa: E402  (the kit's own runs.jsonl reader: strict validation, tail of a big file)

MAX_MS = 24 * 3600 * 1000
LAUNCHERS = ("bash", "sh", "zsh", "python", "python3", "node", "env", "exec")
SCRIPT = re.compile(r"([\w.+-]+\.(?:sh|py))[\"']?(?:\s|$)")
CALLBACK = "(callback)"
NON_SCRIPT = "(non-script hook: /goal text, inline command)"
MARK = b'"stop_hook_summary"'


def slug(path):
    return re.sub(r"[^A-Za-z0-9]", "-", path)


def pct(sorted_values, q):
    """Nearest rank: the smallest value with at least q of the values at or below it."""
    return sorted_values[max(math.ceil(q * len(sorted_values)) - 1, 0)]


def stats(values):
    s = sorted(values)
    if not s:
        return {"n": 0, "p50": None, "p90": None, "max": None}
    return {"n": len(s), "p50": round(pct(s, 0.5), 3), "p90": round(pct(s, 0.9), 3), "max": round(s[-1], 3)}


def epoch_of(ts):
    """Seconds since the epoch of a transcript timestamp (2026-10-15T07:03:13.000Z, UTC), None when absent or odd."""
    if not isinstance(ts, str) or not re.match(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d", ts):
        return None
    try:
        return float(calendar.timegm(time.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S")))
    except (ValueError, OverflowError):
        return None


def hook_name(cmd):
    """The script a hook command runs (`bash "$DIR/.claude/hooks/x.sh"` -> x.sh), else one fixed bucket: a hook that is not a script is a
    /goal condition (its `command` is the user's own text), an SDK callback or an inline command, and that text is never kept."""
    cmd = cmd.strip()
    if cmd == "callback":
        return CALLBACK
    first = cmd.split(None, 1)[0].strip("\"'") if cmd else ""
    if first in LAUNCHERS:
        m = SCRIPT.search(cmd[len(first):].lstrip(" \t") + " ")
        return m.group(1) if m else NON_SCRIPT
    if "/" in first and re.search(r"\.(?:sh|py)$", first):
        return os.path.basename(first)
    return NON_SCRIPT


def good_ms(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) and 0 <= v <= MAX_MS


def transcript_dirs(projects_dir, repo):
    base = slug(repo)
    try:
        names = sorted(os.listdir(projects_dir))
    except OSError:
        return []
    # the repo's own dir and its `.claude/worktrees/<name>` dirs only: another repo whose slug merely starts the same does not match
    return [os.path.join(projects_dir, n) for n in names if (n == base or n.startswith(base + "--")) and os.path.isdir(os.path.join(projects_dir, n))]


def read_stops(dirs, since_epoch):
    """-> list of (epoch or None, prevented, [(hook name, seconds or None)]) for every stop_hook_summary record in the window."""
    out = []
    for d in dirs:
        try:
            files = sorted(f for f in os.listdir(d) if f.endswith(".jsonl"))
        except OSError:
            continue
        for fn in files:
            path = os.path.join(d, fn)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            try:
                fh = open(path, "rb")
            except OSError:
                continue
            with fh:
                for raw in fh:
                    if MARK not in raw:
                        continue
                    try:
                        r = json.loads(raw)
                    except (ValueError, RecursionError):
                        continue
                    if not isinstance(r, dict) or r.get("subtype") != "stop_hook_summary" or not isinstance(r.get("hookInfos"), list):
                        continue
                    ep = epoch_of(r.get("timestamp"))
                    if since_epoch is not None and (ep is None or ep < since_epoch):
                        continue
                    hooks = []
                    for h in r["hookInfos"]:
                        if not isinstance(h, dict):
                            continue
                        hooks.append((hook_name(str(h.get("command", ""))), h["durationMs"] / 1000.0 if good_ms(h.get("durationMs")) else None))
                    errs = r.get("hookErrors")
                    out.append((ep, r.get("preventedContinuation") is True, len(errs) if isinstance(errs, list) else 0, hooks))
    return out


def clean_steps(r):
    """The record's `steps` (seconds per phase of the run, bin/post-fix-gate.py _lap) when it is a non-empty dict of short names and finite
    seconds in 0..24 h, else None: a record with a broken value still counts as a run, it just gives no phase numbers."""
    st = r.get("steps")
    if not isinstance(st, dict) or not st:
        return None
    out = {}
    for k, v in st.items():
        if not isinstance(k, str) or not 0 < len(k) <= 20 or not grr.seconds_ok(v):
            return None
        out[k] = grr.num(v)
    return out


def gate_hook_runs(repo, since_epoch, now):
    """-> (summary dict or None, note). The runs.jsonl records of the Stop hook (source=hook) and where their wall time went."""
    path, _ident, problem = grr.log_file(repo)
    if problem:
        return None, problem
    try:
        data = grr.read_runs(path, since_epoch, now)
    except (OSError, ValueError):
        return None, "no runs.jsonl"
    recs = [r for r in data["recs"] if r["source"] == "hook"]
    walls, suite_s, lock_s, other_s, busy_runs, busy_verdict_runs, by_verdict = [], 0.0, 0.0, 0.0, 0, 0, {}
    steps_total, steps_runs = {}, 0
    for r in recs:
        st = clean_steps(r)
        if st:   # vacuity re-runs happen inside the suites phase: counted apart, so the phases below add up (parallel members can overlap: capped)
            steps_runs += 1
            vac = min(st.get("vacuity", 0.0), st.get("suites", 0.0))
            for k, v in st.items():
                steps_total[k] = steps_total.get(k, 0.0) + (v - vac if k == "suites" else vac if k == "vacuity" else v)
        w = grr.wall(r)
        walls.append(w)
        by_verdict.setdefault(r["verdict"], []).append(w)
        ran = min(sum(s[2] for s in r["suites"] if s[2] is not None), w)   # seconds of suites that really ran are suite time, whatever the flag
        suite_s += ran
        if r["busy"] or r["verdict"] == "BUSY":   # the rest of a run that met the lock: the wait (the busy flag also sits on UNTESTED / FAIL runs)
            busy_runs += 1
            busy_verdict_runs += r["verdict"] == "BUSY"
            lock_s += w - ran
        else:
            other_s += w - ran
    total = suite_s + lock_s + other_s
    pc = (lambda x: round(100.0 * x / total, 1)) if total > 0 else (lambda x: None)
    st = stats(walls)
    return {"runs": len(recs), "busy_runs": busy_runs, "busy_verdict_runs": busy_verdict_runs, "wall_p50": st["p50"], "wall_p90": st["p90"], "wall_max": st["max"],
            "suite_s": round(suite_s, 3), "lock_wait_s": round(lock_s, 3), "other_s": round(other_s, 3),
            "suite_pct": pc(suite_s), "lock_wait_pct": pc(lock_s), "other_pct": pc(other_s),
            "steps_runs": steps_runs, "steps": {k: round(v, 3) for k, v in sorted(steps_total.items())},
            "by_verdict": {v: dict(runs=len(w), wall_s=round(sum(w), 3), wall_p50=stats(w)["p50"], wall_p90=stats(w)["p90"], wall_max=stats(w)["max"])
                           for v, w in by_verdict.items()}}, None


def repo_report(repo, label, projects_dir, since_epoch, now):
    dirs = transcript_dirs(projects_dir, repo)
    stops = read_stops(dirs, since_epoch)
    per_hook, no_dur, slowest = {}, {}, []
    for _ep, _prev, _nerr, hooks in stops:
        valid = []
        for name, secs in hooks:
            per_hook.setdefault(name, [])
            if secs is None:
                no_dur[name] = no_dur.get(name, 0) + 1
            else:
                per_hook[name].append(secs)
                valid.append(secs)
        if valid:
            slowest.append(max(valid))
    hooks = {n: dict(stats(v), no_duration=no_dur.get(n, 0)) for n, v in per_hook.items()}
    wall = dict(stats(slowest), prevented=sum(1 for s in stops if s[1]), with_errors=sum(1 for s in stops if s[2]))
    gate, note = gate_hook_runs(repo, since_epoch, now)
    return {"repo": repo, "label": label, "transcript_dirs": len(dirs), "stops": len(stops), "hooks": hooks, "stop_wall": wall,
            "gate_hook_runs": gate, "gate_note": note}


def fmt(x, w=7):
    return ("%*.2f" % (w, x)) if x is not None else "%*s" % (w, "-")


def render(reports, since_days):
    out = ["Stop hook wall time per hook (transcript stop_hook_summary records; seconds; p50 / p90 nearest rank)",
           "window: %s" % ("last %g days" % since_days if since_days else "everything on disk"), ""]
    out.append("%-34s %-22s %6s %7s %7s %7s  %s" % ("hook", "repo", "Stops", "p50", "p90", "max", "no-duration"))
    for rp in reports:
        for name, h in sorted(rp["hooks"].items(), key=lambda kv: (-(kv[1]["p90"] or 0), kv[0])):
            out.append("%-34s %-22s %6d %s %s %s  %s" % (name[:34], rp["label"][:22], h["n"], fmt(h["p50"]), fmt(h["p90"]), fmt(h["max"]),
                                                         h["no_duration"] or ""))
    out += ["", "Slowest hook of each Stop (hooks of a Stop run side by side: the floor of the Stop's wall time):"]
    for rp in reports:
        w = rp["stop_wall"]
        out.append("  %s: %d Stops%s%s" % (rp["label"], rp["stops"], "" if rp["transcript_dirs"] else " (no transcript dir under the projects dir)",
                                           "" if not w["n"] else ", p50 %.2f / p90 %.2f / max %.2f s, %d with a hook error (a block), %d prevented"
                                           % (w["p50"], w["p90"], w["max"], w["with_errors"], w["prevented"])))
    out += ["", "The Stop hook's gate runs (runs.jsonl, source=hook): where their wall time went:"]
    for rp in reports:
        g = rp["gate_hook_runs"]
        if g is None:
            out.append("  %s: no data (%s)" % (rp["label"], rp["gate_note"]))
        elif not g["runs"]:
            out.append("  %s: no Stop-hook gate run in the window" % rp["label"])
        else:
            out.append("  %s: %d runs, wall p50 %.1f / p90 %.1f / max %.1f s; running suites %s %% (%.0f s), waiting for the lock (test_run.lock) %s %% "
                       "(%.0f s in %d busy-flagged runs, %d of them with the BUSY verdict), other %s %% (%.0f s)"
                       % (rp["label"], g["runs"], g["wall_p50"], g["wall_p90"], g["wall_max"], g["suite_pct"], g["suite_s"], g["lock_wait_pct"],
                          g["lock_wait_s"], g["busy_runs"], g["busy_verdict_runs"], g["other_pct"], g["other_s"]))
            out.append("      by verdict (runs, total minutes, p50 / p90 s): " + "; ".join(
                "%s %d, %.1f min, %.0f / %.0f" % (v, d["runs"], d["wall_s"] / 60.0, d["wall_p50"], d["wall_p90"])
                for v, d in sorted(g["by_verdict"].items(), key=lambda kv: -kv[1]["wall_s"])))
            if g["steps_runs"]:
                tot = sum(g["steps"].values())
                out.append("      steps (%d of %d runs carry them; seconds and share; suites here exclude the vacuity re-runs): " % (g["steps_runs"], g["runs"])
                           + ", ".join("%s %.0f s %.1f %%" % (k, v, 100.0 * v / tot if tot > 0 else 0.0)
                                       for k, v in sorted(g["steps"].items(), key=lambda kv: (-kv[1], kv[0]))))
    return "\n".join(out)


def positive(s):
    v = float(s)
    if not math.isfinite(v) or v <= 0:
        raise argparse.ArgumentTypeError("must be a positive number")
    return v


def default_repo():
    try:
        r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=30)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return os.getcwd()


def main(argv=None):
    ap = argparse.ArgumentParser(description="Real wall time of each Stop hook per repo (read-only)")
    ap.add_argument("--repo", action="append", help="repo path (repeatable; default: the git repo of the cwd)")
    ap.add_argument("--projects-dir", default=os.path.join(os.path.expanduser("~"), ".claude", "projects"), help="Claude Code's transcript root")
    ap.add_argument("--since-days", type=positive, default=None, help="only Stops and gate runs of the last N days")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    a = ap.parse_args(argv)
    now = time.time()
    since = now - a.since_days * 86400 if a.since_days else None
    repos = [os.path.realpath(r) for r in (a.repo or [default_repo()])]
    labels = [os.path.basename(r.rstrip(os.sep)) or r for r in repos]
    labels = [l if labels.count(l) == 1 else r for l, r in zip(labels, repos)]   # two repos with one folder name: show the paths
    reports = [repo_report(r, l, a.projects_dir, since, now) for r, l in zip(repos, labels)]
    if a.json:
        print(json.dumps({"since_days": a.since_days, "repos": reports}, indent=1, sort_keys=True))
    else:
        print(render(reports, a.since_days))
    return 0


if __name__ == "__main__":
    sys.exit(main())
