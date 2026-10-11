#!/usr/bin/env python3
"""review_log.py: a log of who reviewed what, with which model, and how the review turned out (stdlib only).

Why (user, 2026-10-11): /giao reviews ran on gemini-3.1-pro-low until the tier was switched to flash (gemini-3.8-flash-tiered) and nobody knew;
to judge whether a model is worth its time there must be numbers: reviews, findings, how many were real, how many were wrong, what it missed that
another reviewer found later, and the stray files it left behind.

  review_log.py collect [--project DIR]     one line per Antigravity dispatch not yet in the log: task, kind, round, tier, the concrete model read
                                            from the conversation file, verdict and findings of its result file. A later run fills the fields an
                                            earlier one could not know (a result that was not written yet, a conversation still open).
  review_log.py note --source antigravity|claude --task T0028 --kind audit [--conversation ID] [--model M] [--verdict V] [--findings N] [--real N]
                     [--nit N] [--false-positive N] [--missed N] [--stray-files N] [--note TEXT]
                                            the outcome of a review once known. With --conversation it REPLACES those fields of the collected line
                                            of that conversation (an unknown id is an error: run collect first; --model and --verdict are not accepted
                                            there, collect reads them). Without it, a manual line (a Claude reviewer, with its --model and --verdict);
                                            the identical line given twice (every word and number the same) is one line, any difference is another review.
  review_log.py summary [--json]            per (source, model): reviews, findings, real, nit, false positive, missed, stray files, precision

Fields of a line: ts, source, task, kind, round, tier, model, conversation, verdict, findings, real, nit, false_positive, missed, stray_files, note.
  real           a defect that mattered, reproduced by whoever tallies
  nit            true but trivial (a typo in a plan, pseudo-code that the real code does not share)
  false_positive wrong
  missed         defects that existed in what this review looked at and that another reviewer found later
Only plan_review, audit and manual `review` lines count as reviews in the summary; implement / proof / custom dispatches are logged but not counted.
The log is one JSON object per line in <git root>/.agents/local/memory/claude-auto/reviewer-log.jsonl (REVIEW_LOG overrides). A line that is not
a JSON object is kept untouched when the file is rewritten. Every command that writes holds a lock (<log>.lock) around read, change and write.
Roots for tests: PM_HOME (default ~/.antigravity-pm), CONV_DIR (default ~/.gemini/antigravity/conversations).
"""
import argparse, collections, contextlib, datetime, fcntl, glob, json, os, re, sqlite3, subprocess, sys, tempfile

HOME = os.path.expanduser("~")
PM_HOME = os.environ.get("PM_HOME") or os.path.join(HOME, ".antigravity-pm")
CONV_DIR = os.environ.get("CONV_DIR") or os.path.join(HOME, ".gemini", "antigravity", "conversations")
NUM = ("findings", "real", "nit", "false_positive", "missed", "stray_files")
RESULT_FILE = {"plan_review": "plan-review.json", "audit": "audit-agent.json"}
REVIEW_KINDS = ("plan_review", "audit", "review")
MODEL_RX = re.compile(rb"gemini-[0-9][0-9a-z._-]*")


def project_root(given):
    """--project, else the git root of the working directory, else the working directory."""
    if given:
        return os.path.realpath(given)
    try:
        top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        top = ""
    return os.path.realpath(top or os.getcwd())


def default_log(project):
    return os.path.abspath(os.environ.get("REVIEW_LOG") or os.path.join(project, ".agents", "local", "memory", "claude-auto", "reviewer-log.jsonl"))


def same_dir(a, b):
    try:
        return os.path.samefile(a, b)
    except OSError:
        return os.path.realpath(a) == os.path.realpath(b)


def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def read_log(path):
    """Entries in file order: a dict per JSON-object line, the raw text for anything else (kept as it is when the file is rewritten)."""
    entries = []
    try:
        with open(path, encoding="utf-8", errors="surrogateescape") as f:
            for line in f:
                text = line.rstrip("\n")
                if not text.strip():
                    continue
                try:
                    obj = json.loads(text)
                except ValueError:
                    obj = None
                entries.append(obj if isinstance(obj, dict) else text)
    except OSError:
        pass
    return entries


def write_log(path, entries):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".reviewer-log.", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8", errors="surrogateescape") as f:
            for e in entries:
                f.write((e if isinstance(e, str) else json.dumps(e, ensure_ascii=False)) + "\n")
        os.replace(tmp, path)
    except BaseException:
        with contextlib.suppress(OSError):
            os.remove(tmp)
        raise


@contextlib.contextmanager
def locked(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".lock", "a") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        yield


def rows_of(entries):
    return [e for e in entries if isinstance(e, dict)]


def model_of(conversation):
    """The gemini-* id the conversation ran on, from the executor_metadata table of its file (the most frequent one when it changed model),
    or None: no file, no table, an empty one. Counting the strings of the whole file named a model that was only mentioned in the talk."""
    if not conversation or "/" in conversation or conversation.startswith("."):
        return None
    path = os.path.join(CONV_DIR, conversation + ".db")
    if not os.path.isfile(path):
        return None
    hits = collections.Counter()
    try:
        con = sqlite3.connect("file:%s?mode=ro&immutable=1" % path, uri=True)
        try:
            for (blob,) in con.execute("select data from executor_metadata"):
                if isinstance(blob, (bytes, bytearray)):
                    hits.update(MODEL_RX.findall(bytes(blob)))
        finally:
            con.close()
    except sqlite3.Error:
        return None
    return hits.most_common(1)[0][0].decode() if hits else None


def short_task(task_id):
    m = re.match(r"(T\d+)", task_id or "")
    return m.group(1) if m else task_id


def parse_ts(text):
    try:
        return datetime.datetime.fromisoformat(str(text).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def result_of(project, task_id, kind, dispatched_at):
    """(verdict, findings) of the result file of a dispatch kind, or (None, None). The file holds the LAST dispatch of that kind only, and it
    belongs to this dispatch only if it was written after it: an older one (a dispatch still running) must not be taken for its result."""
    name = RESULT_FILE.get(kind)
    if not name:
        return None, None
    path = os.path.join(project, ".antigravity-pm", "tasks", task_id, name)
    try:
        at = parse_ts(dispatched_at)
        if at is None or os.stat(path).st_mtime < at:       # no time of dispatch: the result file cannot be told from an older one
            return None, None
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        return None, None
    findings = d.get("findings") if isinstance(d, dict) else None
    return (d.get("verdict") if isinstance(d, dict) else None), len(findings) if isinstance(findings, list) else None


def project_tasks(project):
    """(task.json path, task) of every Antigravity PM task of this project."""
    found = []
    for tj in sorted(glob.glob(os.path.join(PM_HOME, "projects", "*", "tasks", "*", "task.json"))):
        try:
            with open(tj, encoding="utf-8") as f:
                t = json.load(f)
        except (OSError, ValueError):
            continue
        if isinstance(t, dict) and t.get("project") and same_dir(t["project"], project):
            found.append((tj, t))
    return found


def cmd_collect(args):
    project = project_root(args.project)
    log = os.path.abspath(args.log) if args.log else default_log(project)
    tasks = project_tasks(project)
    if not tasks:
        print("collect: no Antigravity task found for project %s (PM_HOME %s): wrong --project?" % (project, PM_HOME), file=sys.stderr)
        print("collect: nothing to do, the log was not touched")
        return 0
    matched = added = filled = 0
    with locked(log):
        entries = read_log(log)
        by_conv = {r.get("conversation"): r for r in rows_of(entries) if r.get("conversation")}
        for tj, t in tasks:
            matched += 1
            task_id = t.get("id") or os.path.basename(os.path.dirname(tj))
            dispatches = [d for d in t.get("dispatches") or [] if isinstance(d, dict)]
            last_of_kind = {d.get("kind"): d.get("conversationId") for d in dispatches}
            for d in dispatches:
                cid = d.get("conversationId")
                if not cid:
                    continue
                verdict = findings = None
                if last_of_kind.get(d.get("kind")) == cid:      # only the last dispatch of a kind has its result file still on disk
                    verdict, findings = result_of(project, task_id, d.get("kind"), d.get("at"))
                model = model_of(cid)
                row = by_conv.get(cid)
                if row is None:
                    row = {"ts": d.get("at"), "source": "antigravity", "task": short_task(task_id), "kind": d.get("kind"), "round": d.get("round"),
                           "tier": d.get("model"), "model": model, "conversation": cid, "verdict": verdict, "findings": findings,
                           "real": None, "nit": None, "false_positive": None, "missed": None, "stray_files": None, "note": None}
                    entries.append(row)
                    by_conv[cid] = row
                    added += 1
                    continue
                for key, new in (("model", model), ("verdict", verdict), ("findings", findings)):
                    if new is not None and row.get(key) != new and (row.get(key) is None or key == "model"):
                        row[key] = new
                        filled += 1
        if added or filled:
            write_log(log, entries)
    print("collect: %d new line(s), %d field(s) filled, %d line(s) in the log (%s)" % (added, filled, len(rows_of(entries)), log))
    return 0


def cmd_note(args):
    project = project_root(args.project)
    log = os.path.abspath(args.log) if args.log else default_log(project)
    given = {k: getattr(args, k) for k in NUM if getattr(args, k) is not None}
    if args.conversation and (args.verdict or args.model):
        print("note: --verdict and --model of a collected line come from `collect` (the result file and the conversation file); they cannot be set here", file=sys.stderr)
        return 2
    with locked(log):
        entries = read_log(log)
        rows = rows_of(entries)
        if args.conversation:
            target = next((r for r in rows if r.get("conversation") == args.conversation), None)
            if target is None:
                print("note: conversation %s is not in the log: run `collect` first (or drop --conversation for a manual line)" % args.conversation, file=sys.stderr)
                return 2
            action = "replaced the outcome of conversation %s" % args.conversation
        else:
            # a manual line is identified by everything it says: the same words AND numbers again is the same line, anything else is another review
            want = {"source": args.source, "task": short_task(args.task), "kind": args.kind, "round": args.round, "model": args.model, "note": args.note,
                    "verdict": args.verdict, **{k: given.get(k) for k in NUM}}
            target = next((r for r in rows if not r.get("conversation") and all(r.get(k) == v for k, v in want.items())), None)
            action = "same manual line again, nothing added"
            if target is None:
                target = {"ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"), "source": args.source,
                          "task": short_task(args.task), "kind": args.kind, "round": args.round, "tier": None, "model": args.model, "conversation": None,
                          "verdict": args.verdict, "findings": None, "real": None, "nit": None, "false_positive": None, "missed": None,
                          "stray_files": None, "note": args.note}
                entries.append(target)
                action = "new manual line"
        target.update(given)
        if args.note and args.conversation:
            target["note"] = args.note
        if args.model and not target.get("model"):
            target["model"] = args.model
        write_log(log, entries)
    print("note: %s (%d in the log)" % (action, len(rows_of(entries))))
    return 0


def cmd_summary(args):
    project = project_root(args.project)
    entries = read_log(os.path.abspath(args.log) if args.log else default_log(project))
    rows = rows_of(entries)
    groups = collections.OrderedDict()
    uncounted = 0
    for r in rows:
        if r.get("kind") not in REVIEW_KINDS:
            uncounted += 1
            continue
        model = r.get("model") or ("(tier %s)" % r["tier"] if r.get("tier") else "?")
        g = groups.setdefault((r.get("source") or "?", model), {"reviews": 0, **{k: 0 for k in NUM}})
        g["reviews"] += 1
        for k in NUM:
            if is_int(r.get(k)):
                g[k] += r[k]
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
    pending = sum(1 for r in rows if r.get("kind") in REVIEW_KINDS and not any(is_int(r.get(k)) for k in ("real", "nit", "false_positive")))
    skipped = sum(1 for e in entries if isinstance(e, str))
    print("%d review line(s) without an outcome yet (`note --conversation ID --real N ...`); %d other dispatch(es) not counted%s"
          % (pending, uncounted, "; %d unreadable line(s) kept in the file" % skipped if skipped else ""))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("collect", "note", "summary"):
        p = sub.add_parser(name)
        p.add_argument("--project")
        p.add_argument("--log")
        if name == "note":
            p.add_argument("--source", choices=("antigravity", "claude"), default="claude")
            p.add_argument("--task", default="")
            p.add_argument("--kind", default="review", choices=("review", "plan_review", "audit", "implement", "proof", "custom"))
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
