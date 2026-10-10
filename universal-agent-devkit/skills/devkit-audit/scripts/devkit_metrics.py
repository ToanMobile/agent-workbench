#!/usr/bin/env python3
"""devkit_metrics.py [--repo PATH ...] [--since-days N] [--json]: the numbers of the daily DevKit audit (skills/devkit-audit), read-only.

Per repo: git state, the session lock, gate wall time from <git-common-dir>/postfix-gate/runs.jsonl (hook share, hook runs that repeat the
previous hook run's state, overhead outside the suites, top suites), the Stop-hook pipeline from <repo>/.claude/audit-gate/*.log (events, real
blocks, releases), the .agents/CHECKLIST.md header and the bytes every session loads. It writes nothing, runs no test, no gate and no git write
(git runs with core.fsmonitor off; a repo's clean/smudge filters, such as LFS, can still run during `git status`); stdlib only; Python 3.9. A missing or odd file is "no data", and a
repo that fails is reported as an error record without losing the others. runs.jsonl is read with the gate_runs_report.py reader (strict
validation, tail of a big file).

STOP EVENT = a distinct (session, second) pair of a [SID=<session>] line in testsourceset_gate.log (one Stop writes several lines, in the same
second); it is the widest Stop log, some hooks exit early without a line, so the count is approximate. A BLOCK is a line a hook wrote and then
really blocked on: lines starting with block/BLOCK (and the test_evidence_gate "reminder", an exit 2), minus the releases: proof_gate and
regression_gate `attempt=N` above their cap of 2 (the hook logs "block" and then lets the stop go), review_gate "BLOCK suppressed", and one
block per RELEASED on re-Stop or release: session cap line (written after a block line); RELEASE after N reminders or attempts (written instead of a block) only counts as a release; a testsourceset_gate `BLOCK re-used` information line is skipped. foreign_repo_gate and
worktree_merge_gate write no log: their blocks are not counted. The count is within a few percent of the real one on the live logs.

A REPEAT is a hook run whose state equals the previous hook run's (BUSY and DEFERRED runs paid no gate cost and are skipped) and which ended
within 30 minutes of it (the record's epoch is the END of the run). State = (exit, suite verdicts) plus the tree fingerprint when either run has
one (matched by time from regression_gate.log, +-15 s; a run with and one without are not the same state), else n_changed. Without fingerprints a repeat is an approximation: another file with the
same count looks like a repeat, and two sessions interleaving hide one.
"""
import argparse
import bisect
import collections
import json
import os
import re
import stat
import statistics
import subprocess
import sys
import time

KIT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.dont_write_bytecode = True   # python -I ignores PYTHONDONTWRITEBYTECODE: do not leave .pyc files in the kit
sys.path.insert(0, os.path.join(KIT, "scripts", "governance"))
import gate_runs_report as grr  # noqa: E402  (the kit's own runs.jsonl reader)

REPEAT_WINDOW_S = 1800
FP_MATCH_S = 15
ATTEMPT_CAP = 2   # proof_gate PROOF_GATE_MAX_BLOCKS and regression_gate MAX_ATTEMPTS default
STOP_LOGS = ("claim_check", "proof_gate", "regression_gate", "review_gate", "security_gate", "test_evidence_gate", "testsourceset_gate")
LOG_MAX_BYTES = 16 * 1024 * 1024
LOG_LINE = re.compile(r"^\[?(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\]?\s+(.*)$")
BLOCK_LINE = re.compile(r"^(?:\[SID=[^\]]*\]\s+)?block\b", re.I)
SID_LINE = re.compile(r"\[SID=([^\]]+)\]")
SID_PREFIX = re.compile(r"^\[SID=[^\]]*\]\s+")
FP_LINE = re.compile(r"^(?:block|pass|untested|busy|tests-touched reminder)\b.*?\bfp=([0-9A-Za-z]+)")


def read_text(path, limit=LOG_MAX_BYTES, tail=True):
    """The text of a regular file (no link followed, no FIFO opened); a file over `limit` gives its tail (or its head with tail=False)."""
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    except OSError:
        return None
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            return None
        cut = st.st_size > limit
        if cut and tail:
            os.lseek(fd, st.st_size - limit, os.SEEK_SET)
        chunks, left = [], min(st.st_size, limit)
        while left > 0:
            b = os.read(fd, min(left, 1 << 20))
            if not b:
                break
            chunks.append(b)
            left -= len(b)
        text = b"".join(chunks).decode("utf-8", "replace")
        return text.split("\n", 1)[1] if cut and tail and "\n" in text else text
    except OSError:
        return None
    finally:
        os.close(fd)


def run_git(repo, *args):
    env = {**os.environ, "GIT_OPTIONAL_LOCKS": "0"}
    try:
        r = subprocess.run(["git", "-c", "core.fsmonitor=false", "-C", repo, *args], capture_output=True, text=True, env=env, timeout=20,
                           errors="replace")
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def git_state(repo):
    status = run_git(repo, "status", "--porcelain")
    lines = status.splitlines() if status else []
    counts = run_git(repo, "rev-list", "--left-right", "--count", "@{u}...HEAD")
    behind, ahead = (int(x) for x in counts.split()) if counts and len(counts.split()) == 2 else (None, None)
    known = status is not None   # git failed (not a repo, a corrupt index): the tree state is unknown, not clean
    return {"branch": run_git(repo, "branch", "--show-current"), "behind": behind, "ahead": ahead,
            "dirty": sum(1 for l in lines if not l.startswith("??")) if known else None,
            "untracked": sum(1 for l in lines if l.startswith("??")) if known else None}


def lock_state(repo):
    """session_lock.py --status: exit 0 free, 3 held. From a subprocess it also reports the CALLER's own session as held (exit 3)."""
    script = os.path.join(KIT, "bin", "session_lock.py")
    try:
        r = subprocess.run([sys.executable, "-I", script, "--status"], cwd=repo, capture_output=True, text=True, timeout=20, errors="replace")
    except (OSError, subprocess.SubprocessError):
        return {"exit": None, "text": "session_lock.py not runnable"}
    out = (r.stdout + r.stderr).strip()
    return {"exit": r.returncode, "text": out.splitlines()[-1][:200] if out else ""}


def pctl(sorted_vals, p):
    """Nearest-rank percentile of an ascending list."""
    if not sorted_vals:
        return None
    k = max(0, min(len(sorted_vals) - 1, int(-(-p * len(sorted_vals) // 100)) - 1))
    return round(sorted_vals[k], 2)


def under(repo, path):
    """True when `path` really lies inside `repo` (links resolved, in every component: .claude itself may be a link out)."""
    rp, p = os.path.realpath(repo), os.path.realpath(path)
    return p == rp or p.startswith(rp + os.sep)


def log_entries(repo, name, since_epoch):
    """(epoch, text after the timestamp) of each line of <repo>/.claude/audit-gate/<name>.log inside the window. A folder that is a link
    out of the repo is not this repo's log folder; a line dated in the future (a forged or broken log) is not an event."""
    folder = os.path.join(repo, ".claude", "audit-gate")
    if not under(repo, folder):
        return
    now = time.time()
    for line in (read_text(os.path.join(folder, name + ".log")) or "").splitlines():
        m = LOG_LINE.match(line)
        if not m:
            continue
        try:
            t = time.mktime(time.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S"))
        except (ValueError, OverflowError):
            continue
        if since_epoch <= t <= now + 86400:
            yield t, m.group(2)


def assign_fingerprints(repo, rows, since_epoch):
    """Give each hook run the fingerprint of the regression_gate.log line written at its end (+-FP_MATCH_S), when there is one."""
    fps = sorted((t, m.group(1)) for t, rest in log_entries(repo, "regression_gate", since_epoch - 3600) for m in [FP_LINE.match(rest)] if m)
    times = [t for t, _ in fps]
    for r in rows:
        r["_fp"] = None
        if r["source"] != "hook" or not fps:
            continue
        i = bisect.bisect_left(times, r["epoch"])
        near = [fps[j] for j in (i - 1, i) if 0 <= j < len(fps) and abs(fps[j][0] - r["epoch"]) <= FP_MATCH_S]
        if near:
            r["_fp"] = min(near, key=lambda x: abs(x[0] - r["epoch"]))[1]


def suite_rows(r):
    """The (id, status, seconds or None) entries of a record that are well formed (the reader accepts a list or a number as a status)."""
    return [s for s in r["suites"] if isinstance(s[0], str) and isinstance(s[1], str)]


def gate_metrics(rows, ignored, first_epoch):
    wall = grr.wall
    total = sum(wall(r) for r in rows)
    hook = [r for r in rows if r["source"] == "hook"]
    hook_wall = sum(wall(r) for r in hook)
    rep_runs, rep_wall, by_exit, prev = 0, 0.0, collections.defaultdict(lambda: [0, 0.0]), None
    for r in hook:
        if grr.excluded(r):   # a BUSY or DEFERRED run waited or ran nothing: it is not a repeated piece of work
            continue
        verdicts = tuple((s[0], s[1]) for s in suite_rows(r))
        cur = {"fp": r["_fp"], "proxy": (r.get("exit"), r.get("n_changed"), verdicts), "exit": r.get("exit"), "verdicts": verdicts, "epoch": r["epoch"]}
        if prev and cur["epoch"] - prev["epoch"] <= REPEAT_WINDOW_S and cur["exit"] == prev["exit"] and cur["verdicts"] == prev["verdicts"]:
            same = cur["fp"] == prev["fp"] if (cur["fp"] or prev["fp"]) else cur["proxy"] == prev["proxy"]
            if same:
                rep_runs += 1
                rep_wall += wall(r)
                by_exit[str(r.get("exit"))][0] += 1
                by_exit[str(r.get("exit"))][1] += wall(r)
        prev = cur
    overhead, negative = [], 0
    for r in rows:
        tw, sw = grr.num(r.get("total_wall_s")), grr.num(r.get("suites_wall_s"))
        if tw is None or sw is None:
            continue
        if tw - sw < 0:   # suites run side by side (parallel_safe) add up to more than the wall time: the subtraction means nothing there
            negative += 1
        else:
            overhead.append(tw - sw)
    overhead.sort()
    suites = collections.defaultdict(lambda: [0, 0.0, collections.Counter()])
    for r in rows:
        for s in suite_rows(r):
            if s[2] is not None:
                suites[s[0]][0] += 1
                suites[s[0]][1] += s[2]
                suites[s[0]][2][s[1]] += 1
    top = sorted(suites.items(), key=lambda kv: -kv[1][1])[:8]
    return {"runs": len(rows), "ignored": ignored, "wall_min": round(total / 60, 2), "hook_runs": len(hook),
            "hook_wall_min": round(hook_wall / 60, 2), "hook_share_pct": round(100 * hook_wall / total) if total else 0,
            "fp_known_runs": sum(1 for r in hook if r["_fp"]),
            "repeat": {"runs": rep_runs, "wall_min": round(rep_wall / 60, 2),
                       "by_exit": {k: {"runs": v[0], "wall_min": round(v[1] / 60, 2)} for k, v in sorted(by_exit.items())}},
            "overhead_s": {"p50": pctl(overhead, 50), "p90": pctl(overhead, 90), "n": len(overhead), "negative": negative},
            "top_suites": [{"id": k, "runs": v[0], "wall_min": round(v[1] / 60, 2), "status": dict(v[2])} for k, v in top],
            "first_run": time.strftime("%Y-%m-%d %H:%M", time.localtime(first_epoch)) if first_epoch else None}


def stop_metrics(repo, since_epoch):
    """Stop events (per day, per session) and real blocks / releases per hook, from the hooks' own logs in the window."""
    pairs = set()
    for t, rest in log_entries(repo, "testsourceset_gate", since_epoch):
        sid = SID_LINE.search(rest)
        if sid:
            pairs.add((sid.group(1), int(t)))
    per_sid, by_day = collections.Counter(), collections.Counter()
    for sid, t in pairs:
        per_sid[sid] += 1
        by_day[time.strftime("%Y-%m-%d", time.localtime(t))] += 1
    blocks, released = {}, {}
    for name in STOP_LOGS:
        logged = rel = 0
        for _t, raw in log_entries(repo, name, since_epoch):
            rest = SID_PREFIX.sub("", raw)
            low = rest.lower()
            attempt = re.search(r"\battempt=(\d+)", rest)
            if low.startswith("block suppressed"):   # a stop the hook had already let go
                rel += 1
            elif low.startswith("block re-used"):   # testsourceset_gate: an information line, its exit-2 line `BLOCK (attempt N, re-used)` follows
                continue
            elif BLOCK_LINE.match(rest) or low.startswith("reminder"):   # block / BLOCK, and a test_evidence_gate reminder (exit 2)
                if name in ("proof_gate", "regression_gate") and attempt and int(attempt.group(1)) > ATTEMPT_CAP:
                    rel += 1   # logged first, then let go
                else:
                    logged += 1
            elif low.startswith(("released on re-stop", "release: session cap")):   # written AFTER a block line that did not block
                rel += 1
                logged -= 1
            elif low.startswith("release"):   # RELEASE after N reminders / attempts: written INSTEAD of a block
                rel += 1
        if logged > 0:
            blocks[name] = logged
        if rel > 0:
            released[name] = rel
    events, total = len(pairs), sum(blocks.values())
    vals = list(per_sid.values())
    return {"events": events, "sessions": len(per_sid),
            "per_session": {"median": statistics.median(vals) if vals else None, "max": max(vals) if vals else None},
            "by_day": dict(sorted(by_day.items())), "blocks": blocks, "released": released, "blocks_total": total,
            "blocks_per_event": round(total / events, 2) if events else None}


def checklist_header(repo):
    text = read_text(os.path.join(repo, ".agents", "CHECKLIST.md"), 65536, tail=False)
    m = re.search(r"\*\*An toàn (\d+)% \((\d+)/(\d+)\)\*\*", text or "")
    if not m:
        return None
    head = (text or "")[:4000]
    w = re.search(r"⏳ (\d+)", head)
    g = re.search(r"Bug không có test hồi quy[^:*]*:\s*(\d+)", head)
    return {"safe_pct": int(m.group(1)), "passed": int(m.group(2)), "total": int(m.group(3)), "waiting": int(w.group(1)) if w else 0,
            "no_guard": int(g.group(1)) if g else None}


def size_of(path):
    try:
        return os.stat(path).st_size
    except OSError:
        return None


def dir_bytes(repo, path):
    if not under(repo, path) or not os.path.isdir(path):   # a link out of the repo is not this repo's log folder
        return None
    total = 0
    for root, _dirs, files in os.walk(path):
        for f in files:
            try:
                total += os.lstat(os.path.join(root, f)).st_size
            except OSError:
                pass
    return total


def sizes(repo):
    ctx = os.path.join(repo, ".agents", "context")
    return {"agents_md": size_of(os.path.join(repo, "AGENTS.md")),
            "profile_rules": size_of(os.path.join(ctx, "profile-rules.md")),
            "rules_index": size_of(os.path.join(ctx, "rules-index.md")),
            "instincts_md": size_of(os.path.join(repo, ".agents", "instincts.md")),
            "checklist_md": size_of(os.path.join(repo, ".agents", "CHECKLIST.md")),
            "regression_status_json": size_of(os.path.join(repo, ".agents", "regression_status.json")),
            "audit_gate_dir": dir_bytes(repo, os.path.join(repo, ".claude", "audit-gate"))}


def gate_for(repo, since_epoch, now):
    path, _ident, _problem = grr.log_file(repo)
    try:
        data = grr.read_runs(path, since_epoch, now) if path else None
    except (OSError, ValueError):
        data = None
    if not data:
        return gate_metrics([], 0, None)
    rows = data["recs"]
    rows.sort(key=lambda r: r["epoch"])
    assign_fingerprints(repo, rows, since_epoch)
    return gate_metrics(rows, data["ignored"], data["first"])


def repo_metrics(repo, since_days):
    repo = os.path.abspath(repo)
    now = time.time()
    since = now - since_days * 86400
    try:
        return {"path": repo, "name": os.path.basename(repo), "git": git_state(repo), "lock": lock_state(repo),
                "gate": gate_for(repo, since, now), "stop": stop_metrics(repo, since), "checklist": checklist_header(repo), "sizes": sizes(repo)}
    except Exception as e:  # noqa: BLE001 - one odd repo must not take the others' numbers with it
        return {"path": repo, "name": os.path.basename(repo), "error": "%s: %s" % (type(e).__name__, str(e)[:200])}


def show(d, since_days):
    if "error" in d:
        print(f"\n== {d['name']}  ({d['path']})\n  ERROR {d['error']}")
        return
    g, gt = d["gate"], d["git"]
    print(f"\n== {d['name']}  ({d['path']})")
    print(f"  git: {gt['branch']}  behind={gt['behind']} ahead={gt['ahead']}  dirty={gt['dirty']} untracked={gt['untracked']}   lock: exit {d['lock']['exit']}")
    if d["checklist"]:
        c = d["checklist"]
        print(f"  checklist: {c['safe_pct']}% ({c['passed']}/{c['total']}), {c['waiting']} waiting, {c['no_guard']} bugs without a guard")
    print(f"  gate, last {since_days} d (log from {g['first_run']}): {g['runs']} runs, {g['wall_min']} min; hook runs {g['hook_runs']} = {g['hook_wall_min']} min ({g['hook_share_pct']}%)")
    print(f"  repeat of the previous hook run's state (<=30 min, {g['fp_known_runs']} runs have a fingerprint): {g['repeat']['runs']} runs, {g['repeat']['wall_min']} min; "
          + ", ".join(f"exit {k}: {v['runs']} / {v['wall_min']} min" for k, v in g["repeat"]["by_exit"].items()))
    st = d["stop"]
    print(f"  Stop pipeline, last {since_days} d: {st['events']} events in {st['sessions']} sessions (median {st['per_session']['median']}, max {st['per_session']['max']} per session); "
          f"{st['blocks_total']} real blocks = {st['blocks_per_event']} per event: " + ", ".join(f"{k} {v}" for k, v in sorted(st["blocks"].items(), key=lambda kv: -kv[1]))
          + ("; released: " + ", ".join(f"{k} {v}" for k, v in sorted(st["released"].items())) if st["released"] else ""))
    print("  Stop events by day: " + ", ".join(f"{k[5:]}={v}" for k, v in list(st["by_day"].items())[-7:]))
    o = g["overhead_s"]
    print(f"  overhead outside the suites: p50 {o['p50']} s, p90 {o['p90']} s (n={o['n']}, {o['negative']} parallel runs left out)")
    for s in g["top_suites"][:5]:
        print(f"  suite {s['id']:24} {s['runs']:4} runs {s['wall_min']:8} min {s['status']}")
    print("  bytes: " + "  ".join(f"{k}={v}" for k, v in d["sizes"].items() if v is not None))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--repo", action="append", help="a repo to measure (repeatable; default: the current directory)")
    ap.add_argument("--since-days", type=float, default=7.0)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    if not (0 < args.since_days < 36500):   # nan, inf, 0 and negatives made a window of nothing, or invalid JSON
        ap.error("--since-days must be a number above 0 (and below 36500)")
    repos = [repo_metrics(r, args.since_days) for r in (args.repo or ["."])]
    if args.json:
        print(json.dumps({"v": 1, "window_days": args.since_days, "at": time.strftime("%Y-%m-%dT%H:%M:%S"), "repos": repos}, indent=1))
    else:
        for d in repos:
            show(d, args.since_days)
    return 0


if __name__ == "__main__":
    sys.exit(main())
