#!/usr/bin/env bash
# Regression test: skills/devkit-audit/scripts/review_log.py, the log of who reviewed what with which model and how the review turned out
# (user 2026-10-11: "ghi log để lấy số liệu"). Fake PM_HOME, CONV_DIR and log under a temp dir: nothing of the real Antigravity data is touched.
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"   # no inherited GIT_*: tests/lib/clean_git_env.sh
set -u
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${RL_SCRIPT:-$DEVKIT_DIR/skills/devkit-audit/scripts/review_log.py}"
python3 -I - "$SCRIPT" <<'PY'
import json, os, subprocess, sys, tempfile

SCRIPT = sys.argv[1]
TMP = tempfile.mkdtemp()
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


def run(*args):
    r = subprocess.run([sys.executable, "-I", SCRIPT, *args, "--project", PROJECT], capture_output=True, text=True, env=ENV)
    return r.returncode, r.stdout, r.stderr


def rows():
    try:
        return [json.loads(l) for l in open(LOG, encoding="utf-8") if l.strip()]
    except OSError:
        return []


def task(task_id, project, dispatches, results=None):
    d = os.path.join(PM, "projects", "x-1", "tasks", task_id); os.makedirs(d)
    json.dump({"id": task_id, "project": project, "dispatches": dispatches}, open(os.path.join(d, "task.json"), "w"))
    for name, body in (results or {}).items():
        rd = os.path.join(project, ".antigravity-pm", "tasks", task_id); os.makedirs(rd, exist_ok=True)
        json.dump(body, open(os.path.join(rd, name), "w"))


def conv(cid, text):
    open(os.path.join(CONV, cid + ".db"), "wb").write(text)


# a conversation file names several ids; the most frequent one is the model that ran
conv("c-plan", b"x gemini-3.1-pro-low y gemini-3.1-pro-low z gemini-3.1-pro-low q gemini-3.8-flash-tiered")
conv("c-audit", b"gemini-3.8-flash-tiered " * 5 + b"gemini-3.1-pro-low")
task("T0100-demo-task", PROJECT,
     [{"kind": "plan_review", "conversationId": "c-old", "model": "pro", "round": 0, "at": "2026-10-10T10:00:00.000Z"},
      {"kind": "plan_review", "conversationId": "c-plan", "model": "pro", "round": 1, "at": "2026-10-10T11:00:00.000Z"},
      {"kind": "audit", "conversationId": "c-audit", "model": "flash", "round": 1, "at": "2026-10-10T12:00:00.000Z"},
      {"kind": "audit", "conversationId": "c-nofile", "model": "flash", "round": 2, "at": "2026-10-10T13:00:00.000Z"}],
     {"plan-review.json": {"verdict": "co_van_de", "findings": [{"severity": "major"}, {"severity": "minor"}, {"severity": "minor"}]},
      "audit-agent.json": {"verdict": "pass", "findings": []}})
task("T0101-other-project", OTHER, [{"kind": "audit", "conversationId": "c-other", "model": "pro", "round": 0, "at": "2026-10-10T09:00:00.000Z"}])

# ── collect ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
rc, out, err = run("collect")
r = rows()
by = {x["conversation"]: x for x in r}
check("collect: one line per dispatch of THIS project (4), none of the other project", rc == 0 and len(r) == 4 and "c-other" not in by, (rc, len(r), err))
check("collect: the model is the most frequent gemini id of the conversation file", by["c-plan"]["model"] == "gemini-3.1-pro-low" and by["c-audit"]["model"] == "gemini-3.8-flash-tiered")
check("collect: the tier that was asked is kept next to the model that ran", by["c-plan"]["tier"] == "pro" and by["c-audit"]["tier"] == "flash")
check("collect: verdict and finding count come from the result file of the LAST dispatch of a kind",
      by["c-plan"]["verdict"] == "co_van_de" and by["c-plan"]["findings"] == 3 and by["c-nofile"]["verdict"] == "pass" and by["c-nofile"]["findings"] == 0)
check("collect: an earlier dispatch of the same kind has no result to read (its file was overwritten)", by["c-old"]["verdict"] is None and by["c-old"]["findings"] is None)
check("collect: a conversation file that is gone gives model null, not a crash", by["c-nofile"]["model"] is None and by["c-old"]["model"] is None)
check("collect: the short task id and the round are stored", by["c-plan"]["task"] == "T0100" and by["c-plan"]["round"] == 1)

rc, out, err = run("collect")
check("collect is idempotent: a second run adds nothing", rc == 0 and len(rows()) == 4 and "0 new" in out, out)

# ── note ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────
rc, out, err = run("note", "--conversation", "c-plan", "--real", "0", "--nit", "3", "--false-positive", "0", "--note", "pseudo-code of the plan only")
by = {x["conversation"]: x for x in rows()}
check("note --conversation merges the outcome into the collected line (no new line)", rc == 0 and len(rows()) == 4 and by["c-plan"]["nit"] == 3 and by["c-plan"]["real"] == 0, (rc, err))
check("note keeps what collect knew", by["c-plan"]["model"] == "gemini-3.1-pro-low" and by["c-plan"]["findings"] == 3)
rc, out, err = run("note", "--conversation", "c-audit", "--missed", "1", "--stray-files", "1")
by = {x["conversation"]: x for x in rows()}
check("note: a second field set on another line, zero is a value", by["c-audit"]["missed"] == 1 and by["c-audit"]["stray_files"] == 1 and by["c-plan"]["real"] == 0)
rc, out, err = run("note", "--source", "claude", "--task", "T0100", "--kind", "review", "--model", "claude-fresh-context", "--findings", "2", "--real", "2", "--false-positive", "0")
check("note without a known conversation appends a manual line (a Claude reviewer)", rc == 0 and len(rows()) == 5 and rows()[-1]["source"] == "claude" and rows()[-1]["real"] == 2)
rc, out, err = run("collect")
check("collect after a manual line still adds nothing", len(rows()) == 5)

# ── summary ───────────────────────────────────────────────────────────────────────────────────────────────────────────────
run("note", "--conversation", "c-old", "--real", "1", "--false-positive", "1", "--nit", "2")
rc, out, err = run("summary", "--json")
s = {(g["source"], g["model"]): g for g in json.loads(out)}
check("summary: one real and one wrong finding is a precision of 0.5", s[("antigravity", "pro")]["precision"] == 0.5, s[("antigravity", "pro")])
pro = s[("antigravity", "gemini-3.1-pro-low")]; flash = s[("antigravity", "gemini-3.8-flash-tiered")]; cl = s[("claude", "claude-fresh-context")]
check("summary groups by source and model; a line whose model is unknown falls back to its tier (flash / pro)",
      set(s) == {("antigravity", "gemini-3.1-pro-low"), ("antigravity", "gemini-3.8-flash-tiered"), ("antigravity", "pro"), ("antigravity", "flash"), ("claude", "claude-fresh-context")}, sorted(s))
check("summary adds the counts of a group", pro["reviews"] == 1 and pro["findings"] == 3 and pro["nit"] == 3 and flash["missed"] == 1 and flash["stray_files"] == 1, (pro, flash))
check("summary: precision = real / (real + false positive), none when nothing was judged", cl["precision"] == 1.0 and flash["precision"] is None, (cl, flash))
rc, out, err = run("summary")
check("summary table prints and counts the lines without an outcome", rc == 0 and "without an outcome" in out and "gemini-3.1-pro-low" in out, out)

# ── damaged log ──────────────────────────────────────────────────────────────────────────────────────────────────────────
with open(LOG, "a", encoding="utf-8") as f:
    f.write("{ not json\n\n")
rc, out, err = run("collect")
check("a damaged line in the log is skipped, not fatal", rc == 0 and len(rows()) == 5, (rc, err))
check("the log is replaced atomically: no .tmp left behind", not os.path.exists(LOG + ".tmp"))

print("review_log: %s" % ("all checks passed" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
PY
