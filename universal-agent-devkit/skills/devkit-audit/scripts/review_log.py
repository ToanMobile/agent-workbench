#!/usr/bin/env python3
"""review_log.py: a log of who reviewed what, with which model, and how the review turned out (stdlib only).

Why (user, 2026-10-11): /giao reviews ran on gemini-3.1-pro-low until the tier was switched to flash (gemini-3.8-flash-tiered) and nobody knew;
to judge whether a model is worth its time there must be numbers: reviews, findings, how many were real, how many were wrong, what it missed that
another reviewer found later, and the stray files it left behind.

  review_log.py collect [--project DIR]     one line per Antigravity dispatch (plan_review, audit, ...) not yet in the log: task, kind, round,
                                            tier, the concrete model read from the conversation file, verdict and findings of its result file
  review_log.py note --source antigravity|claude --task T0028 --kind audit [--conversation ID] [--model M] [--findings N] [--real N]
                     [--nit N] [--false-positive N] [--missed N] [--stray-files N] [--note TEXT]
                                            a manual line: a Claude reviewer, or the outcome of an Antigravity review once known (it is merged
                                            into the collected line of the same --conversation, the numbers it carries replace the empty ones)
  review_log.py summary [--json]            per (source, model): reviews, findings, real, nit, false positive, missed, stray files, precision

Fields of a line: ts, source, task, kind, round, tier, model, conversation, verdict, findings, real, nit, false_positive, missed, stray_files, note.
  real           a defect that mattered, reproduced by whoever tallies
  nit            true but trivial (a typo in a plan, pseudo-code that the real code does not share)
  false_positive wrong
  missed         defects that existed in what this review looked at and that another reviewer found later
The log is one JSON object per line in .agents/local/memory/claude-auto/reviewer-log.jsonl (REVIEW_LOG overrides). Roots for tests:
PM_HOME (default ~/.antigravity-pm), CONV_DIR (default ~/.gemini/antigravity/conversations).
"""
import argparse, collections, glob, json, os, re, sys

HOME = os.path.expanduser("~")
PM_HOME = os.environ.get("PM_HOME") or os.path.join(HOME, ".antigravity-pm")
CONV_DIR = os.environ.get("CONV_DIR") or os.path.join(HOME, ".gemini", "antigravity", "conversations")
NUM = ("findings", "real", "nit", "false_positive", "missed", "stray_files")
RESULT_FILE = {"plan_review": "plan-review.json", "audit": "audit-agent.json"}
MODEL_RX = re.compile(rb"gemini-[0-9][0-9a-z._-]*")


def default_log(project):
    return os.environ.get("REVIEW_LOG") or os.path.join(project, ".agents", "local", "memory", "claude-auto", "reviewer-log.jsonl")


def read_log(path):
    rows = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        rows.append(json.loads(line))
                    except ValueError:
                        pass
    except OSError:
        pass
    return rows


def write_log(path, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    os.replace(tmp, path)


def model_of(conversation):
    """The most frequent gemini-* id in the conversation file, or None (no file, or none named)."""
    if not conversation:
        return None
    try:
        with open(os.path.join(CONV_DIR, conversation + ".db"), "rb") as f:
            hits = collections.Counter(MODEL_RX.findall(f.read()))
    except OSError:
        return None
    return hits.most_common(1)[0][0].decode() if hits else None


def short_task(task_id):
    m = re.match(r"(T\d+)", task_id or "")
    return m.group(1) if m else task_id


def result_of(project, task_id, kind):
    """(verdict, findings) of the result file of a dispatch kind, or (None, None). The file holds the LAST dispatch of that kind only."""
    name = RESULT_FILE.get(kind)
    if not name:
        return None, None
    try:
        with open(os.path.join(project, ".antigravity-pm", "tasks", task_id, name), encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        return None, None
    findings = d.get("findings")
    return d.get("verdict"), len(findings) if isinstance(findings, list) else None


def cmd_collect(args):
    project = os.path.realpath(args.project)
    log = args.log or default_log(project)
    rows = read_log(log)
    seen = {r.get("conversation") for r in rows if r.get("conversation")}
    added = 0
    for tj in sorted(glob.glob(os.path.join(PM_HOME, "projects", "*", "tasks", "*", "task.json"))):
        try:
            with open(tj, encoding="utf-8") as f:
                t = json.load(f)
        except (OSError, ValueError):
            continue
        if os.path.realpath(t.get("project") or "") != project:
            continue
        task_id = t.get("id") or os.path.basename(os.path.dirname(tj))
        last_of_kind = {}
        for d in t.get("dispatches") or []:
            last_of_kind[d.get("kind")] = d.get("conversationId")
        for d in t.get("dispatches") or []:
            cid = d.get("conversationId")
            if not cid or cid in seen:
                continue
            verdict = findings = None
            if last_of_kind.get(d.get("kind")) == cid:      # only the last dispatch of a kind has its result file still on disk
                verdict, findings = result_of(project, task_id, d.get("kind"))
            rows.append({"ts": d.get("at"), "source": "antigravity", "task": short_task(task_id), "kind": d.get("kind"), "round": d.get("round"),
                         "tier": d.get("model"), "model": model_of(cid), "conversation": cid, "verdict": verdict, "findings": findings,
                         "real": None, "nit": None, "false_positive": None, "missed": None, "stray_files": None, "note": None})
            seen.add(cid)
            added += 1
    write_log(log, rows)
    print("collect: %d new line(s), %d in the log (%s)" % (added, len(rows), log))
    return 0


def cmd_note(args):
    project = os.path.realpath(args.project)
    log = args.log or default_log(project)
    rows = read_log(log)
    given = {k: getattr(args, k) for k in NUM if getattr(args, k) is not None}
    target = next((r for r in rows if args.conversation and r.get("conversation") == args.conversation), None)
    if target is not None:
        target.update(given)
        if args.note:
            target["note"] = args.note
        if args.model and not target.get("model"):
            target["model"] = args.model
        action = "merged into the line of conversation %s" % args.conversation
    else:
        import datetime
        row = {"ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"), "source": args.source, "task": short_task(args.task),
               "kind": args.kind, "round": args.round, "tier": None, "model": args.model, "conversation": args.conversation, "verdict": args.verdict,
               "findings": None, "real": None, "nit": None, "false_positive": None, "missed": None, "stray_files": None, "note": args.note}
        row.update(given)
        rows.append(row)
        action = "new line"
    write_log(log, rows)
    print("note: %s (%d in the log)" % (action, len(rows)))
    return 0


def cmd_summary(args):
    project = os.path.realpath(args.project)
    rows = read_log(args.log or default_log(project))
    groups = collections.OrderedDict()
    for r in rows:
        key = (r.get("source") or "?", r.get("model") or r.get("tier") or "?")
        g = groups.setdefault(key, {"reviews": 0, **{k: 0 for k in NUM}, "annotated": 0})
        g["reviews"] += 1
        for k in NUM:
            if isinstance(r.get(k), int):
                g[k] += r[k]
        if any(isinstance(r.get(k), int) for k in ("real", "nit", "false_positive")):
            g["annotated"] += 1
    out = []
    for (source, model), g in groups.items():
        judged = g["real"] + g["false_positive"]
        out.append({"source": source, "model": model, **g, "precision": round(g["real"] / judged, 2) if judged else None})
    if args.json:
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return 0
    print("%-12s %-26s %7s %8s %5s %4s %6s %7s %6s %9s" % ("source", "model", "reviews", "findings", "real", "nit", "wrong", "missed", "stray", "precision"))
    for g in out:
        print("%-12s %-26s %7d %8d %5d %4d %6d %7d %6d %9s" % (g["source"], g["model"][:26], g["reviews"], g["findings"], g["real"], g["nit"],
                                                            g["false_positive"], g["missed"], g["stray_files"], "-" if g["precision"] is None else g["precision"]))
    unannotated = sum(1 for r in rows if not any(isinstance(r.get(k), int) for k in ("real", "nit", "false_positive")))
    print("%d line(s), %d without an outcome yet (real / nit / false_positive unset): `note --conversation ID --real N ...`" % (len(rows), unannotated))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("collect", "note", "summary"):
        p = sub.add_parser(name)
        p.add_argument("--project", default=os.getcwd())
        p.add_argument("--log")
        if name == "note":
            p.add_argument("--source", choices=("antigravity", "claude"), default="claude")
            p.add_argument("--task", default="")
            p.add_argument("--kind", default="review")
            p.add_argument("--round", type=int, default=0)
            p.add_argument("--conversation")
            p.add_argument("--model")
            p.add_argument("--verdict")
            p.add_argument("--note")
            for k in NUM:
                p.add_argument("--" + k.replace("_", "-"), dest=k, type=int)
        if name == "summary":
            p.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    return {"collect": cmd_collect, "note": cmd_note, "summary": cmd_summary}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
