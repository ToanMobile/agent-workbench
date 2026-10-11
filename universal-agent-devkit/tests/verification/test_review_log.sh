#!/usr/bin/env bash
# Regression test: skills/devkit-audit/scripts/review_log.py, the log of who reviewed what with which model and how the review turned out
# (user 2026-10-11: "ghi log để lấy số liệu"). Fake PM_HOME, CONV_DIR and log under a temp dir (removed at the end): nothing of the real
# Antigravity data is touched. A fresh-context review (same day) reproduced 9 defects of the first version; each has a case here:
#   lost lines when collect and note run together, a damaged line erased by the next write, the model taken from a name mentioned in the
#   talk, a result of an older dispatch given to a newer one and never corrected, implement runs counted as reviews, note on an unknown
#   conversation creating a stray line, note twice doubling a manual line, the working directory used as the project, and a test that let
#   8 of 12 mutants live. RL_SCRIPT=<copy> runs the same cases against a mutated copy.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${RL_SCRIPT:-$DEVKIT_DIR/skills/devkit-audit/scripts/review_log.py}"
python3 -I - "$SCRIPT" <<'PY'
import atexit, json, os, shutil, sqlite3, subprocess, sys, tempfile, time

SCRIPT = sys.argv[1]
TMP = tempfile.mkdtemp()
atexit.register(lambda: shutil.rmtree(TMP, ignore_errors=True))      # also when a case crashes
PROJECT = os.path.join(TMP, "proj"); os.makedirs(os.path.join(PROJECT, ".antigravity-pm", "tasks"))
OTHER = os.path.join(TMP, "other"); os.makedirs(OTHER)
PM = os.path.join(TMP, "pm"); CONV = os.path.join(TMP, "conv"); os.makedirs(CONV)
LOG = os.path.join(TMP, "log", "reviewer-log.jsonl")
ENV = dict(os.environ, PM_HOME=PM, CONV_DIR=CONV, REVIEW_LOG=LOG)
ENV.pop("PYTHONPATH", None)
fails = 0


def check(name, cond, detail=""):
    global fails
    print(("✔ " if cond else "✖ ") + name + ("" if cond else "  — " + str(detail)[:300]))
    if not cond:
        fails += 1


def run(*args, project=True, cwd=None, env=None):
    cmd = [sys.executable, "-I", SCRIPT, *args] + (["--project", PROJECT] if project is True else (["--project", project] if project else []))
    r = subprocess.run(cmd, capture_output=True, text=True, env=env or ENV, cwd=cwd)
    return r.returncode, r.stdout, r.stderr


def rows():
    try:
        return [json.loads(l) for l in open(LOG, encoding="utf-8", errors="surrogateescape") if l.strip().startswith("{") and l.strip().endswith("}") and ", }" not in l]
    except OSError:
        return []


def raw_lines():
    try:
        return [l.rstrip("\n") for l in open(LOG, encoding="utf-8", errors="surrogateescape") if l.strip()]
    except OSError:
        return []


def task(task_id, project, dispatches, results=None, result_mtime=None):
    d = os.path.join(PM, "projects", "x-1", "tasks", task_id); os.makedirs(d, exist_ok=True)
    json.dump({"id": task_id, "project": project, "dispatches": dispatches}, open(os.path.join(d, "task.json"), "w"))
    for name, body in (results or {}).items():
        rd = os.path.join(project, ".antigravity-pm", "tasks", task_id); os.makedirs(rd, exist_ok=True)
        p = os.path.join(rd, name)
        json.dump(body, open(p, "w"))
        if result_mtime is not None:
            os.utime(p, (result_mtime, result_mtime))


def conv(cid, ids, noise=b"", empty_table=False, no_table=False):
    """A conversation file as Antigravity writes it: a sqlite db whose executor_metadata rows hold the model ids; `noise` is extra text in
    another table (a model name that was only talked about)."""
    p = os.path.join(CONV, cid + ".db")
    con = sqlite3.connect(p)
    con.execute("create table steps (idx integer, data blob)")
    con.execute("insert into steps values (0, ?)", (noise,))
    if not no_table:
        con.execute("create table executor_metadata (idx integer, data blob)")
        if not empty_table:
            for i, mid in enumerate(ids):
                con.execute("insert into executor_metadata values (?, ?)", (i, b"\x08\x04\x1a" + mid.encode() + b"\x22\x01"))
    con.commit(); con.close()


NOW = time.time()
def iso(offset):
    return time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(NOW + offset))


# a conversation names its model in executor_metadata; the most frequent id wins; the first id seen is a minority here (M1)
conv("c-plan", ["gemini-3.8-flash-tiered"] + ["gemini-3.1-pro-low"] * 3)
conv("c-audit", ["gemini-3.8-flash-tiered"] * 2, noise=b"gemini-2.5-flash " * 40)       # the talk mentions another model 40 times
conv("c-old", [], no_table=True, noise=b"gemini-3.1-pro-low " * 5)                       # no metadata: unknown, never a vote on the text
conv("c-emptytab", [], empty_table=True)
conv("c-shared", ["gemini-3.1-pro-low"])
task("T0100-demo-task", PROJECT,
     [{"kind": "plan_review", "conversationId": "c-old", "model": "pro", "round": 0, "at": iso(-900)},
      {"kind": "plan_review", "conversationId": "c-plan", "model": "pro", "round": 1, "at": iso(-800)},
      {"kind": "audit", "conversationId": "c-audit", "model": "flash", "round": 1, "at": iso(-700)},
      {"kind": "audit", "conversationId": "c-nofile", "model": "flash", "round": 2, "at": iso(-600)},
      {"kind": "implement", "conversationId": "c-shared", "model": "pro", "round": 1, "at": iso(-500)},
      {"kind": "custom", "conversationId": "c-shared", "model": "pro", "round": 1, "at": iso(-400)}],      # same conversation twice (M3)
     {"plan-review.json": {"verdict": "co_van_de", "findings": [{"severity": "major"}, {"severity": "minor"}, {"severity": "minor"}]},
      "audit-agent.json": {"verdict": "pass", "findings": []}}, result_mtime=NOW)
task("T0101-other-project", OTHER, [{"kind": "audit", "conversationId": "c-other", "model": "pro", "round": 0, "at": iso(-300)}])

# ── collect ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
rc, out, err = run("collect")
r = rows(); by = {x["conversation"]: x for x in r}
check("collect: one line per conversation of THIS project, none of the other project, a shared conversation once", rc == 0 and len(r) == 5 and "c-other" not in by, (rc, len(r), err))
check("collect: the model is the most frequent id of executor_metadata, not the first (M1)", by["c-plan"]["model"] == "gemini-3.1-pro-low", by["c-plan"])
check("collect: a model named only in the talk is no vote", by["c-audit"]["model"] == "gemini-3.8-flash-tiered", by["c-audit"])
check("collect: no metadata table, or no file: the model is unknown, never guessed from the text",
      by["c-old"]["model"] is None and by["c-nofile"]["model"] is None, (by["c-old"], by["c-nofile"]))
check("collect: the tier that was asked is kept next to the model that ran", by["c-plan"]["tier"] == "pro" and by["c-audit"]["tier"] == "flash")
check("collect: verdict and finding count come from the result file of the LAST dispatch of a kind",
      by["c-plan"]["verdict"] == "co_van_de" and by["c-plan"]["findings"] == 3 and by["c-nofile"]["verdict"] == "pass" and by["c-nofile"]["findings"] == 0)
check("collect: an earlier dispatch of the same kind has no result to read", by["c-old"]["verdict"] is None and by["c-old"]["findings"] is None)
check("collect: the short task id and the round are stored", by["c-plan"]["task"] == "T0100" and by["c-plan"]["round"] == 1)
rc, out, err = run("collect")
check("collect is idempotent: a second run adds nothing", rc == 0 and len(rows()) == 5 and "0 new" in out, out)

# the project may be given through a symlink or another spelling of the path (M2)
link = os.path.join(TMP, "proj-link"); os.symlink(PROJECT, link)
rc, out, err = run("collect", project=link)
check("collect: a symlink to the project is the same project", rc == 0 and len(rows()) == 5 and "no Antigravity task found" not in err, (out, err))

# ── a result that is older than the dispatch is not its result; a later collect fills what was unknown ───────────────────────
RES = os.path.join(PROJECT, ".antigravity-pm", "tasks", "T0102-running", "audit-agent.json")
task("T0102-running", PROJECT, [{"kind": "audit", "conversationId": "c-run1", "model": "flash", "round": 1, "at": iso(-200)},
                                {"kind": "audit", "conversationId": "c-run2", "model": "flash", "round": 2, "at": iso(60)}],
     {"audit-agent.json": {"verdict": "co_van_de", "findings": [{}, {}, {}]}}, result_mtime=NOW - 100)       # written by the first audit, before the second
conv("c-run1", ["gemini-3.8-flash-tiered"])
rc, out, err = run("collect")
by = {x["conversation"]: x for x in rows()}
check("collect: the running second audit does not inherit the finished first one's verdict (it was counted twice before)",
      by["c-run2"]["verdict"] is None and by["c-run2"]["findings"] is None, by["c-run2"])
json.dump({"verdict": "pass", "findings": []}, open(RES, "w")); os.utime(RES, (NOW + 120, NOW + 120))
conv("c-run2", ["gemini-3.8-flash-tiered"])
rc, out, err = run("collect")
by = {x["conversation"]: x for x in rows()}
check("collect: a later run fills the verdict, the count and the model that were unknown",
      by["c-run2"]["verdict"] == "pass" and by["c-run2"]["findings"] == 0 and by["c-run2"]["model"] == "gemini-3.8-flash-tiered", by["c-run2"])

# a dispatch without a time cannot claim a result file: it could be any older one
task("T0103-notime", PROJECT, [{"kind": "audit", "conversationId": "c-notime", "model": "flash", "round": 2}],
     {"audit-agent.json": {"verdict": "fail", "findings": [{}]}}, result_mtime=NOW - 3600)
conv("c-notime", ["gemini-3.8-flash-tiered"])
rc, out, err = run("collect")
check("collect: a dispatch with no time does not take an old result file for its own", {x["conversation"]: x for x in rows()}["c-notime"]["verdict"] is None)

# a conversation id is a file name, never a path: ../x must not read a file outside the conversation folder
conv_outside = os.path.join(TMP, "x.db")
con = sqlite3.connect(conv_outside); con.execute("create table executor_metadata (idx integer, data blob)")
con.execute("insert into executor_metadata values (0, ?)", (b"\x1agemini-9.9-outside\x22",)); con.commit(); con.close()
task("T0104-dots", PROJECT, [{"kind": "audit", "conversationId": "../x", "model": "pro", "round": 0, "at": iso(-100)}])
rc, out, err = run("collect")
check("collect: a conversation id with ../ is not followed out of the conversation folder", rc == 0 and [x["model"] for x in rows() if x["conversation"] == "../x"] == [None], rows()[-1])

# a conversation that is still open (sqlite WAL with a writer): reading it creates and changes nothing in the folder
wal = os.path.join(CONV, "c-wal.db")
wcon = sqlite3.connect(wal); wcon.execute("pragma journal_mode=wal"); wcon.execute("create table executor_metadata (idx integer, data blob)")
wcon.execute("insert into executor_metadata values (0, ?)", (b"\x1agemini-3.8-flash-tiered\x22",)); wcon.commit()
task("T0105-wal", PROJECT, [{"kind": "audit", "conversationId": "c-wal", "model": "flash", "round": 0, "at": iso(-90)}])
def listing():
    return sorted((f, os.stat(os.path.join(CONV, f)).st_size) for f in os.listdir(CONV))
before = listing()
rc, out, err = run("collect")
after = listing()
check("collect: reading an open (WAL) conversation adds no file and changes none in the conversation folder", rc == 0 and before == after, (set(after) ^ set(before)))
wcon.close()
# a conversation whose writer is gone (WAL mode, files closed): a plain read-only open would CREATE -shm and -wal in Antigravity's folder
cwal = os.path.join(CONV, "c-walclosed.db")
w2 = sqlite3.connect(cwal); w2.execute("pragma journal_mode=wal"); w2.execute("create table executor_metadata (idx integer, data blob)")
w2.execute("insert into executor_metadata values (0, ?)", (b"\x1agemini-3.8-flash-tiered\x22",)); w2.commit(); w2.close()
task("T0106-walclosed", PROJECT, [{"kind": "audit", "conversationId": "c-walclosed", "model": "flash", "round": 0, "at": iso(-80)}])
before = listing()
rc, out, err = run("collect")
after = listing()
check("collect: reading a closed WAL conversation creates no -shm / -wal file in the conversation folder, and still reads the model",
      rc == 0 and [f for f in after if f not in before and f[0] != "c-walclosed.db"] == [] and not [f for f, _ in after if f.endswith(("-shm", "-wal")) and f.startswith("c-walclosed")]
      and {x["conversation"]: x for x in rows()}["c-walclosed"]["model"] == "gemini-3.8-flash-tiered", (set(after) ^ set(before)))

# nothing to collect for the folder it was started in: no lock file, no folder, no log created there
bare = os.path.join(TMP, "bare"); os.makedirs(bare)
env3 = dict(ENV); env3.pop("REVIEW_LOG")
rc, out, err = run("collect", project=bare, env=env3)
check("collect for a project with no task creates nothing in that project (no .agents folder, no lock file)", rc == 0 and not os.path.exists(os.path.join(bare, ".agents")), os.listdir(bare))
rc, out, err = run("summary", "--log", "rel-log.jsonl", cwd=bare)
check("a relative --log path works", rc == 0, (rc, err))

# ── note ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────
n_before = len(rows())
rc, out, err = run("note", "--conversation", "c-plan", "--real", "0", "--nit", "3", "--false-positive", "0", "--note", "first text")
by = {x["conversation"]: x for x in rows()}
check("note --conversation merges the outcome into the collected line (no new line)", rc == 0 and len(rows()) == n_before and by["c-plan"]["nit"] == 3 and by["c-plan"]["real"] == 0, (rc, err))
check("note keeps what collect knew", by["c-plan"]["model"] == "gemini-3.1-pro-low" and by["c-plan"]["findings"] == 3)
run("note", "--conversation", "c-plan", "--nit", "1", "--note", "second text")
by = {x["conversation"]: x for x in rows()}
check("note on the same conversation REPLACES the numbers and the text it carries (documented) and keeps the ones it does not",
      by["c-plan"]["nit"] == 1 and by["c-plan"]["real"] == 0 and by["c-plan"]["note"] == "second text", by["c-plan"])
run("note", "--conversation", "c-audit", "--missed", "1", "--stray-files", "1")
by = {x["conversation"]: x for x in rows()}
check("note sets missed and stray_files on another line and leaves the first line alone", by["c-audit"]["missed"] == 1 and by["c-audit"]["stray_files"] == 1 and by["c-plan"]["real"] == 0, by["c-audit"])
snapshot = raw_lines()
rc, out, err = run("note", "--conversation", "c-typo", "--real", "1")
check("note on a conversation that is not in the log is an error and writes nothing (no stray line)", rc == 2 and "collect" in err and raw_lines() == snapshot, (rc, err))
manual = ("note", "--source", "claude", "--task", "T0100", "--kind", "review", "--model", "claude-test", "--findings", "2", "--real", "2", "--false-positive", "0", "--note", "reviewer one")
run(*manual); run(*manual)
claude = [x for x in rows() if x["source"] == "claude" and x.get("model") == "claude-test"]
check("the same manual line given twice is one line, not two", len(claude) == 1 and claude[0]["real"] == 2, claude)
run("note", "--source", "claude", "--task", "T0100", "--kind", "review", "--model", "claude-test", "--real", "1", "--note", "reviewer two")
n_rows = len(rows())
run("collect")
check("collect after manual lines still adds nothing (a manual line has no conversation to match)", len(rows()) == n_rows, (n_rows, len(rows())))
check("another manual line (other note) is a second line", len([x for x in rows() if x["source"] == "claude" and x.get("model") == "claude-test"]) == 2)
run("note", "--source", "claude", "--task", "T0401", "--kind", "review", "--model", "claude-y", "--findings", "5", "--real", "4")
run("note", "--source", "claude", "--task", "T0401", "--kind", "review", "--model", "claude-y", "--findings", "2", "--real", "1")
two = [x for x in rows() if x.get("model") == "claude-y"]
check("two different reviews of one task with the same words but other numbers stay two lines (they were merged and (5,4) lost)",
      sorted((x["findings"], x["real"]) for x in two) == [(2, 1), (5, 4)], two)
snap2 = raw_lines()
rc, out, err = run("note", "--conversation", "c-plan", "--model", "claude-x")
rc2, out2, err2 = run("note", "--conversation", "c-plan", "--verdict", "fail")
check("note --conversation with --model or --verdict is refused (collect reads them) and writes nothing", rc == 2 and rc2 == 2 and raw_lines() == snap2, (rc, rc2, err))
rc, out, err = run("note", "--kind", "plan-review", "--task", "T0500", "--real", "1")
check("a mistyped --kind is refused, not silently left out of the summary", rc == 2 and "invalid choice" in err, (rc, err))

# ── summary ───────────────────────────────────────────────────────────────────────────────────────────────────────────────
run("note", "--conversation", "c-old", "--real", "1", "--false-positive", "1", "--nit", "2")
rc, out, err = run("summary", "--json")
s = {(g["source"], g["model"]): g for g in json.loads(out)}
check("summary counts only reviews (plan_review, audit, manual review): implement and custom dispatches are not reviews",
      sum(g["reviews"] for g in s.values() if g["source"] == "antigravity") == 10, s)       # 4 + 2 (T0102) + 4 (no time, ../x, WAL open, WAL closed) audits and plan reviews
check("summary adds the counts of a group (the only gemini-3.1-pro-low review: 3 findings, 1 nit, 0 real)",
      s[("antigravity", "gemini-3.1-pro-low")]["reviews"] == 1 and s[("antigravity", "gemini-3.1-pro-low")]["findings"] == 3
      and s[("antigravity", "gemini-3.1-pro-low")]["nit"] == 1 and s[("antigravity", "gemini-3.1-pro-low")]["real"] == 0, s.get(("antigravity", "gemini-3.1-pro-low")))
check("summary: a line with an unknown model is grouped under its tier and says so", ("antigravity", "(tier pro)") in s and ("antigravity", "(tier flash)") in s, sorted(s))
check("summary: one real and one wrong finding is a precision of 0.5, nits do not count", s[("antigravity", "(tier pro)")]["precision"] == 0.5, s[("antigravity", "(tier pro)")])
check("summary: precision is none when nothing was judged", s[("antigravity", "gemini-3.8-flash-tiered")]["precision"] is None, s)
rc, out, err = run("summary")
check("summary table prints and counts what is still without an outcome and what is not counted", rc == 0 and "without an outcome" in out and "not counted" in out, out)

# ── damaged log: kept, never erased ──────────────────────────────────────────────────────────────────────────────────────────
with open(LOG, "a", encoding="utf-8") as f:
    f.write('{"hand": "edited", }\nnull\n[1, 2]\n')
rc, out, err = run("note", "--conversation", "c-audit", "--real", "1")
after = raw_lines()
check("a line a person broke (trailing comma), a null and a list survive the next write unchanged",
      rc == 0 and all(x in after for x in ('{"hand": "edited", }', "null", "[1, 2]")), (rc, err, after[-4:]))
with open(LOG, "ab") as f:
    f.write(b'{"source": "claude", "note": "caf\xe9 not utf-8"}\n')
rc3, out3, err3 = run("note", "--conversation", "c-audit", "--real", "1")
with open(LOG, "rb") as f:
    data = f.read()
check("a line with a byte that is not UTF-8 neither crashes a command nor changes when the file is rewritten", rc3 == 0 and b"caf\xe9 not utf-8" in data, (rc3, err3))
rc, out, err = run("summary")
check("a null or list line does not crash any command", rc == 0 and "unreadable line(s) kept" in out, (rc, err, out))

# ── concurrency: collect and note together lose nothing ───────────────────────────────────────────────────────────────────────
N = 24
procs = []
for i in range(N):
    procs.append(subprocess.Popen([sys.executable, "-I", SCRIPT, "note", "--project", PROJECT, "--source", "claude", "--task", "T0200", "--kind", "review",
                                   "--model", "claude-par", "--note", "parallel %d" % i, "--real", "1"], env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE))
    if i % 3 == 0:
        procs.append(subprocess.Popen([sys.executable, "-I", SCRIPT, "collect", "--project", PROJECT], env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE))
codes = [(p.wait(), p.stderr.read().decode()[:150]) for p in procs]
par = [x for x in rows() if x.get("model") == "claude-par"]
check("%d notes written next to %d collects at the same time: none lost, none crashed" % (N, len(procs) - N), len(par) == N and all(c == 0 for c, _ in codes),
      ([c for c in codes if c[0]], len(par)))
check("no temp file is left behind in the log folder", not [f for f in os.listdir(os.path.dirname(LOG)) if f.startswith(".reviewer-log.")], os.listdir(os.path.dirname(LOG)))

# ── the project defaults to the git root, and a project with no task says so ───────────────────────────────────────────────────
repo = os.path.join(TMP, "gitrepo"); os.makedirs(os.path.join(repo, "sub", "deep"))
subprocess.run(["git", "init", "-q", repo], check=True)
task("T0300-git", os.path.realpath(repo), [{"kind": "audit", "conversationId": "c-git", "model": "pro", "round": 0, "at": iso(-50)}])
env2 = dict(ENV); env2.pop("REVIEW_LOG")
rc, out, err = run("collect", project=False, cwd=os.path.join(repo, "sub", "deep"), env=env2)
want = os.path.join(os.path.realpath(repo), ".agents", "local", "memory", "claude-auto", "reviewer-log.jsonl")
check("without --project the log goes under the git root, not under the folder the command was started in",
      rc == 0 and os.path.isfile(want) and not os.path.exists(os.path.join(repo, "sub", "deep", ".agents")), (out, err))
rc, out, err = run("collect", project=bare, env=env3)
check("collect says so when no task belongs to the project (a silent zero hid a wrong --project)", "no Antigravity task found" in err, err)

# ── numbers in the log: a boolean is not a count, a string is not a count ────────────────────────────────────────────────────
with open(LOG, "a", encoding="utf-8") as f:
    f.write(json.dumps({"source": "claude", "model": "claude-odd", "kind": "review", "real": True, "findings": "3", "nit": 2}) + "\n")
rc, out, err = run("summary", "--json")
odd = {(g["source"], g["model"]): g for g in json.loads(out)}[("claude", "claude-odd")]
check("summary: true is not 1 and \"3\" is not 3, only whole numbers count", odd["real"] == 0 and odd["findings"] == 0 and odd["nit"] == 2, odd)

print("review_log: %s" % ("all checks passed" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
PY
