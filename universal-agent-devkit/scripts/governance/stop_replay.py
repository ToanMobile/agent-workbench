#!/usr/bin/env python3
"""Replay the Stop hooks' BLOCKS on real Claude Code transcripts: which blocks were right, which were wrong?

    python3 stop_replay.py [--days 7] [--root DIR ...] [--hook NAME ...] [--examples N] [--json] [--min-stops 100] [--no-replay]
                           [--hooks DIR]

Reads, never writes, the transcripts of ~/.claude/projects, ~/.claude-finos*/projects and ~/.claude-max/projects (every
`<root>/<project>/*.jsonl` modified in the last --days days; --root may repeat and replaces the defaults). A transcript is
streamed (they reach 100 MB); a Stop is kept by its own timestamp; the same Stop recorded in two transcripts (a resumed
session) counts once.

A Stop is a `system` / `stop_hook_summary` record. A BLOCK is an entry of its `hookErrors`, `[bash ".../<hook>.sh"]: <message>`
(exit 2: the message is the hook's stderr). An entry that is no block (a hook script that is missing, "non-blocking status
code") is counted apart. For every block of proof_gate, test_evidence_gate and review_gate this rebuilds what the hook saw from
the transcript alone (the last assistant message, the turn after the last human prompt, its tool calls, the whole session's
edits and reviews) and gives it one of four verdicts:

  correct       the reason is settled by the transcript: the agent did not have what the hook asked for
  WRONG         the agent had what the hook asked for, or the hook misread the reply, AND the hook code in this checkout
                still blocks it (replayed for real: the hook is run on the reconstructed reply in a throw-away git repo)
  fixed-since   the block was WRONG or stale, and the hook code in this checkout no longer blocks it
  unknown       the reason needs state a transcript does not hold (the gate receipt, an image file, test XML on disk, the git
                diff of that moment). Never counted as wrong. What the tool cannot settle is said, not guessed.

The table is per hook and repo: Stops, blocked Stops, blocks per Stop, the four verdicts, and masked examples of every WRONG
class. The 0.10 target of docs/workflow-improvements.md (blocks per Stop, repos with >= --min-stops Stops) is printed per
repo for the three classified hooks and for every hook, as blocked Stops per Stop and block entries per Stop.

Prompt and reply texts are never printed raw: an example is a short head of the reply with tokens, emails, other people's home
folders and long ids masked. Standard library only, Python 3.9. A report, not a gate: exit 0.
"""
import argparse
import ast
import collections
import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.dirname(os.path.dirname(HERE))
HOOKS_DIR = os.path.join(KIT, "hooks")

DEFAULT_ROOTS = ("~/.claude/projects", "~/.claude-finos/projects", "~/.claude-finos_team/projects", "~/.claude-max/projects")
GATES = ("proof_gate", "test_evidence_gate", "review_gate")      # classified; every other hook is only counted
BLOCK_RE = re.compile(r"^\[(.*?)\]: (.*)\Z", re.S)
HOOK_RE = re.compile(r"/([\w.-]+)\.sh")
NOT_A_BLOCK = re.compile(r"^(?:Failed with non-blocking status code|Hook script appears to be missing|Hook (?:cancelled|timed out))", re.I)
MAX_TURN_EVENTS = 800       # tool calls kept per turn: the LAST ones (a push or an edit late in a long turn is what the hooks read)
MAX_RESULT_CHARS = 400
MAX_CMD_CHARS = 600         # a command head is all the classifiers read
MAX_TURN_TEXTS = 60         # assistant messages kept per turn, the last ones (the report of a push turn may stand in an earlier one)
MAX_TEXT_CHARS = 8000
# a background task: "running in background with ID: X", "moved to the background (ID: X)", an Agent's "agentId: X"; its end:
# <task-notification><task-id>X</task-id>… or a queue line <agent-message from="X">
BG_ID_RE = re.compile(r"(?:\bID:\s*|\bagentId:\s*)([A-Za-z0-9]{6,})")
TASK_DONE_RE = re.compile(r"<task-id>([A-Za-z0-9]{6,})</task-id>|<agent-message from=\"([A-Za-z0-9]{6,})\"")
EDIT_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit")
CODE_EXT = re.compile(r"\.(?:kt|java|cs|py|js|ts|tsx|swift|go|rs|sh)$")
TEST_RUN = re.compile(r"(?:\btests?/|test_|\.test\.|pytest|npm\s+(?:run\s+)?test|cargo\s+test|go\s+test|gradlew|unity|run_impacted"
                      r"|post-fix-gate|--run-tests|swift\s+test)", re.I)
REVIEWERS = {"principal-code-reviewer", "code-reviewer", "silent-failure-hunter", "pr-test-analyzer", "type-design-analyzer",
             "test-architect-seti", "android-principal-architect", "exampleapp-code-reviewer"}
REVIEW_SKILLS = {"code-review", "review-pr", "review-changes", "open-code-review", "multi-lens-audit"}


# ── masking ───────────────────────────────────────────────────────────────────────────────────────────────────────────
_MASKS = (
    (re.compile(r"\b(?:sk|pk|rk|ghp|gho|ghs|ghu|github_pat|glpat|xox[abprs]|AKIA|AIza|ya29|eyJ)[A-Za-z0-9_\-.]{8,}"), "<token>"),
    # `Bearer abc…`, `Authorization: Basic …`, `--password x`, `mật khẩu là x`, and a NAME that holds a key word before or after it (DB_PASSWORD=x,
    # PGPASSWORD=x, OPENAI_API_KEY=x, SECRET_KEY=x, {"password": "x"}): over-masking a word like `tokens=3` costs nothing here
    (re.compile(r"(?i)\b(?:bearer|basic)\s+[A-Za-z0-9._~+/=-]{6,}"
                r"|--?(?:password|passwd|pwd|token|secret)(?:=|\s+)\S+"
                r"|mật\s+khẩu(?:\s+là)?\s*[:=]?\s*\S+"
                r"|[\w-]*(?:token|api[_-]?key|secret|pass|password|passwd|pwd|private[_-]?key|access[_-]?key|cookie|credential)[\w-]*"
                r"[\"']?\s*[:=]\s*[\"']?[^\s\"',;]+"
                r"|(?<![\w-])-p\S{4,}|(?<![\w-])-u\s+\S+:\S+"),
     "<secret>"),
    (re.compile(r"[A-Za-z]:\\Users\\[^\\\s]+"), "~"),
    (re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+"), "<email>"),
    (re.compile(r"(?:/Users|/home)/[^/\s\"']+"), "~"),
    (re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"), "<uuid>"),
    (re.compile(r"\b[0-9a-fA-F]{24,}\b"), "<hex>"),
    (re.compile(r"\b[A-Za-z0-9+/_-]{32,}={0,2}"), "<blob>"),
)


def mask(text, limit=160):
    """A one-line, short, secret-free head of a text."""
    s = re.sub(r"\s+", " ", text if isinstance(text, str) else "").strip()
    for rx, rep in _MASKS:
        s = rx.sub(rep, s)
    return s if len(s) <= limit else s[:limit - 1] + "…"


# ── transcripts ───────────────────────────────────────────────────────────────────────────────────────────────────────
def transcript_files(roots, days, now=None):
    """Main-session transcripts (<root>/<project>/<id>.jsonl, no subagent files) modified in the last `days` days."""
    cut = (now or time.time()) - days * 86400
    seen, out = set(), []
    for root in roots:
        for path in glob.glob(os.path.join(os.path.expanduser(root), "*", "*.jsonl")):
            real = os.path.realpath(path)
            try:
                if real in seen or os.path.getmtime(real) < cut:
                    continue
            except OSError:
                continue
            seen.add(real)
            out.append(real)
    return sorted(out)


def repo_label(project_dir):
    """The repo a Stop belongs to, from the folder Claude Code names after the path the session STARTED in (`-Volumes-Data-Toan-
    Game-Goods-Triple-Shelf-Match-3D`, a worktree `<repo>--claude-worktrees-<name>`): not the cwd, which moves into sub-folders."""
    s = project_dir.split("--claude-worktrees-")[0].split("--claude-")[0]
    s = re.sub(r"^-(?:Volumes|Users|home)-[^-]+-(?:Toan-|Desktop-|Documents-)?", "", s) if s.startswith("-") else s
    s = re.sub(r"^Game-", "", s)
    half = len(s) // 2
    if len(s) % 2 == 1 and s[:half] == s[half + 1:] and s[half] == "-":   # OfficeReader-OfficeReader: the git root is the inner folder
        s = s[:half]
    return s or project_dir


def _epoch(ts):
    try:
        return datetime.datetime.fromisoformat(str(ts).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def _text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(x.get("text", "") for x in content if isinstance(x, dict) and x.get("type") == "text"
                         and isinstance(x.get("text"), str))
    return ""


def _result_text(body):
    if isinstance(body, list):
        body = " ".join(x.get("text", "") for x in body if isinstance(x, dict))
    return str(body or "")


def _done_ids(text):
    return {a or b for a, b in TASK_DONE_RE.findall(text)}


def load_harness():
    """hooks/devkit_harness.py (the one definition of a prompt and a status line), or None when it will not load."""
    try:
        sys.path.insert(0, HOOKS_DIR)
        sys.dont_write_bytecode = True
        import devkit_harness
        return devkit_harness
    except Exception:
        return None
    finally:
        if sys.path and sys.path[0] == HOOKS_DIR:
            del sys.path[0]


def _human_prompt(e, harness):
    if harness is not None:
        return harness.is_user_prompt(e)
    if e.get("type") != "user" or e.get("isMeta") or not isinstance(e.get("message"), dict):
        return False
    c = e["message"].get("content")
    return isinstance(c, str) or (isinstance(c, list) and any(isinstance(x, dict) and x.get("type") == "text" for x in c))


def stops_of(path, harness=None, seen_uuids=None, since=0.0):
    """Yield one dict per Stop of a transcript, streaming (a Stop is yielded when the NEXT Stop or prompt shows what followed it):
       {uuid, project_dir, path, blocks: [{hook, message}], errors: how many hookErrors were no block}
       and, for a Stop that blocked, what the hook saw: reply, turn_off / reply_end (byte range of the turn in the file),
       events (the tool calls of the turn: name, command / path, result head), texts (its assistant messages), sess (the
       whole session's edits, reviewers and skills), bg_open (background tasks of the turn nobody reported done);
       and what followed: next_blocks (hook names that blocked the next Stop of the turn; None: a prompt came first)."""
    project_dir = os.path.basename(os.path.dirname(path))
    turn_off = None
    reply, reply_end = "", None
    events, texts, by_id = collections.deque(maxlen=MAX_TURN_EVENTS), collections.deque(maxlen=MAX_TURN_TEXTS), {}
    sess = {"edits": [], "agents": [], "skills": []}
    bg_open = {}
    pending = None
    try:
        fh = open(path, "rb")
    except OSError:
        return
    off = 0
    with fh:
        for n, raw in enumerate(fh):
            line_off, off = off, off + len(raw)
            if b'"type"' not in raw:
                continue
            try:
                e = json.loads(raw.decode("utf-8", "replace"))
            except ValueError:
                continue
            if not isinstance(e, dict):
                continue
            typ = e.get("type")
            if typ == "system":
                if e.get("subtype") != "stop_hook_summary":
                    continue
                t = _epoch(e.get("timestamp"))
                uid = e.get("uuid")
                if t is not None and t < since:
                    continue
                if seen_uuids is not None and uid:
                    if uid in seen_uuids:
                        continue
                    seen_uuids.add(uid)
                blocks, errors = [], 0
                for err in e.get("hookErrors") or []:
                    m = BLOCK_RE.match(str(err))
                    h = HOOK_RE.search(m.group(1)) if m else None
                    body = m.group(2) if m else str(err)
                    if h and not NOT_A_BLOCK.match(body):
                        blocks.append({"hook": h.group(1), "message": body})
                    else:
                        errors += 1
                if pending is not None:
                    pending["next_blocks"] = [b["hook"] for b in blocks]
                    yield pending
                    pending = None
                st = {"uuid": uid, "project_dir": project_dir, "path": path, "blocks": blocks, "errors": errors}
                if not blocks:
                    yield st
                    continue
                st.update(reply=reply, turn_off=turn_off, reply_end=reply_end, events=list(events), texts=list(texts),
                          sess={k: list(v) for k, v in sess.items()}, bg_open=dict(bg_open), next_blocks=None)
                pending = st
                continue
            if typ == "queue-operation" and bg_open:
                for done in _done_ids(str(e.get("content", ""))):
                    bg_open.pop(done, None)
                continue
            if e.get("isSidechain"):
                continue
            msg = e.get("message")
            if not isinstance(msg, dict):
                continue
            content = msg.get("content")
            if typ == "user":
                if bg_open and isinstance(content, (str, list)):
                    for done in _done_ids(content if isinstance(content, str) else _text_of(content)):
                        bg_open.pop(done, None)
                if _human_prompt(e, harness):
                    if pending is not None:
                        yield pending
                        pending = None
                    turn_off = line_off
                    reply, reply_end = "", None
                    events.clear()
                    texts.clear()
                    by_id = {}
                    bg_open.clear()
                    continue
                if isinstance(content, list):
                    for c in content:
                        if isinstance(c, dict) and c.get("type") == "tool_result" and c.get("tool_use_id") in by_id:
                            ev = by_id[c["tool_use_id"]]
                            ev["result"] = _result_text(c.get("content"))[:MAX_RESULT_CHARS]
                            ev["rn"] = n                   # where the result stands: a push counts as settled there (proof_gate)
                            if ev.get("bg") or "background" in ev["result"]:
                                for tid in BG_ID_RE.findall(ev["result"]):
                                    bg_open[tid] = ev["name"] + ":" + (ev.get("sub") or ev["cmd"][:100])
            elif typ == "assistant" and isinstance(content, list):
                for c in content:
                    if not isinstance(c, dict):
                        continue
                    if c.get("type") == "text" and isinstance(c.get("text"), str):
                        reply, reply_end = c["text"], off
                        texts.append({"n": n, "text": c["text"][:MAX_TEXT_CHARS]})
                    elif c.get("type") == "tool_use":
                        args = c.get("input") if isinstance(c.get("input"), dict) else {}
                        cmd = str(args.get("command", ""))
                        ev = {"name": str(c.get("name", "")),
                              "bg": bool(args.get("run_in_background")), "sub": str(args.get("subagent_type", "")),
                              "cmd": cmd[:MAX_CMD_CHARS],
                              # read on the WHOLE command: the push of a long script stands past any cut
                              "push": harness is not None and "push" in harness.git_writes(cmd),
                              "path": str(args.get("file_path") or args.get("notebook_path") or args.get("TargetFile") or "")}
                        events.append(ev)
                        name = ev["name"]
                        if name in EDIT_TOOLS:
                            sess["edits"].append({"n": n, "path": ev["path"]})
                        elif name in ("Agent", "Task"):
                            sess["agents"].append({"n": n, "type": ev["sub"]})
                        elif name == "Skill":
                            sess["skills"].append({"n": n, "skill": str(args.get("skill", ""))})
                        ev["n"] = n
                        if c.get("id"):
                            by_id[c["id"]] = ev
    if pending is not None:
        yield pending


def collect(roots, days, harness=None, hooks=None, now=None):
    """(Stops per repo, block entries, non-block hook errors per repo). A block entry is a dict with its repo and its Stop."""
    since = (now or time.time()) - days * 86400
    stops, errors = collections.Counter(), collections.Counter()
    blocks, seen = [], set()
    for path in transcript_files(roots, days, now):
        for st in stops_of(path, harness, seen, since):
            repo = repo_label(st["project_dir"])
            stops[repo] += 1
            errors[repo] += st["errors"]
            for b in st["blocks"]:
                if hooks and b["hook"] not in hooks:
                    continue
                blocks.append(dict(b, repo=repo, stop=st))
    return stops, blocks, errors


# ── the hook's own regexes (never a copy that can drift) ─────────────────────────────────────────────────────────────
_REGEX_CACHE = {}
_HEREDOC_PY = re.compile(r"<<'PY'[^\n]*\n(.*?)\nPY\n", re.S)


def _flags(node):
    """`re.I`, `re.I | re.S` ... of a parsed re.compile call, 0 for anything else."""
    if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name) and node.value.id == "re":
        return getattr(re, node.attr, 0)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.BitOr):
        return _flags(node.left) | _flags(node.right)
    return 0


def hook_regex(hook, name):
    """The compiled `NAME = re.compile("…", re.I)` of the python heredoc of hooks/<hook>.sh, read as a syntax tree (nothing is run),
    or None when the source no longer has that shape."""
    key = (hook, name)
    if key not in _REGEX_CACHE:
        rx = None
        try:
            with open(os.path.join(HOOKS_DIR, hook + ".sh"), encoding="utf-8") as fh:
                m = _HEREDOC_PY.search(fh.read())
            for node in ast.parse(m.group(1)).body if m else ():
                if (isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == name for t in node.targets)
                        and isinstance(node.value, ast.Call) and node.value.args and isinstance(node.value.args[0], ast.Constant)
                        and isinstance(node.value.args[0].value, str)):
                    flags = _flags(node.value.args[1]) if len(node.value.args) > 1 else 0
                    rx = re.compile(node.value.args[0].value, flags)
        except (OSError, SyntaxError, ValueError, re.error):
            rx = None
        _REGEX_CACHE[key] = rx
    return _REGEX_CACHE[key]


# ── a real run of the current hook in a throw-away git repo ──────────────────────────────────────────────────────────
SANDBOX_ENV = ("PATH", "HOME", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR", "USER", "LOGNAME", "TERM")   # nothing else: PROOF_GATE=0,
# TEST_EVIDENCE_GATE=0 and the other kill switches and knobs of the caller's shell must not reach the hook (OCR review 14/10)


class Sandbox:
    """A temp git repo and a temp transcript: the hook is run exactly as Claude Code runs it (payload on stdin, exit 2 = block),
    but on a project that is not one of the user's, so what it writes (<repo>/.claude/audit-gate) stays here."""

    def __init__(self):
        self.root = tempfile.mkdtemp(prefix="stop-replay-")
        self.n = 0
        try:
            self.repo = os.path.join(self.root, "repo")
            os.makedirs(self.repo)
            self.env = {k: os.environ[k] for k in SANDBOX_ENV if k in os.environ}
            for args in (["init", "-q", "."], ["config", "user.email", "r@r"], ["config", "user.name", "r"]):
                subprocess.run(["git", "-C", self.repo] + args, env=self.env, capture_output=True, timeout=30, check=True)
            with open(os.path.join(self.repo, "a.txt"), "w") as fh:
                fh.write("x\n")
            subprocess.run(["git", "-C", self.repo, "add", "-A"], env=self.env, capture_output=True, timeout=30, check=True)
            subprocess.run(["git", "-C", self.repo, "commit", "-qm", "init"], env=self.env, capture_output=True, timeout=30, check=True)
        except (OSError, subprocess.SubprocessError):
            self.close()
            raise

    def close(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def run(self, hook, reply, turn_slice=None):
        """(exit code, stderr) of hooks/<hook>.sh for this reply; turn_slice = the raw transcript bytes of the turn, else only a
        prompt. None when the hook did not return, crashed (a traceback) or exited with a code that is neither pass (0) nor block (2):
        such a run says nothing about whether the hook would block."""
        self.n += 1
        tp = os.path.join(self.root, "t%d.jsonl" % self.n)
        prompt = json.dumps({"type": "user", "timestamp": "2000-01-01T00:00:00.000Z",
                             "message": {"role": "user", "content": "replay"}}) + "\n"
        with open(tp, "wb") as fh:
            fh.write(turn_slice if turn_slice else prompt.encode())
        payload = json.dumps({"session_id": "replay-%d" % self.n, "hook_event_name": "Stop", "transcript_path": tp,
                              "cwd": self.repo, "last_assistant_message": reply, "stop_hook_active": False})
        env = dict(self.env, CLAUDE_PROJECT_DIR=self.repo, PROOF_GATE_MAX_BLOCKS="1000")
        try:
            r = subprocess.run(["bash", os.path.join(HOOKS_DIR, hook + ".sh")], input=payload.encode(), env=env,
                               capture_output=True, timeout=60, cwd=self.repo)
        except (subprocess.TimeoutExpired, OSError):
            return None
        finally:
            try:
                os.remove(tp)               # a turn slice reaches 64 MiB: not kept until close()
            except OSError:
                pass
        err = r.stderr.decode("utf-8", "replace")
        return None if r.returncode not in (0, 2) or "Traceback" in err else (r.returncode, err)


def turn_bytes(stop):
    """The transcript bytes of the turn up to the reply (the prompt, the tool calls, the reply): what proof_gate reads."""
    a, b = stop.get("turn_off"), stop.get("reply_end")
    if a is None or b is None or b <= a or b - a > 64 << 20:
        return None
    try:
        with open(stop["path"], "rb") as fh:
            fh.seek(a)
            return fh.read(b - a)
    except OSError:
        return None


# ── oracles: what the transcript alone settles ──────────────────────────────────────────────────────────────────────
_NUMBERED = re.compile(r"(?m)^[ \t]*(?:[-*>][ \t]*)?(?:\*\*|__)?[ \t]*([1-4])[ \t]*[.)][ \t]*(?:\*\*|__)?[ \t]*(.{0,70})")
# each idea is a CONCEPT with its qualifier ("Hành vi cũ / mới" is no old-bug / new-bug item)
_ITEM_WORDS = (r"\b(?:đã|what)\s+(?:was\s+)?(?:fix\w*|sửa|làm|thay\s+đổi|done|changed)\b",
               r"\b(?:bug|lỗi|test|regress\w*)\b.{0,20}\b(?:cũ|old)\b|\breopen\w*",
               r"\b(?:nguy\s+cơ|rủi\s+ro|risk|bug|lỗi)\b.{0,20}\b(?:mới|new)\b|\bcollateral\b",
               r"\b(?:an\s+toàn|safety)\b")


def structured_report(reply):
    """True when the reply has the four items of the acceptance report as a numbered list 1..4, each with a LABEL (the text before a
    colon) that carries the idea of the item (what was fixed, old bugs, new bugs, code safety): the report, whatever its words.
    Independent of the hook's own regexes; an entry without a colon is no label."""
    entries = [(int(n), rest.split(":", 1)[0].split("：", 1)[0]) for n, rest in _NUMBERED.findall(reply or "")
               if ":" in rest or "：" in rest]
    for i, (num, rest) in enumerate(entries):
        if num != 1:
            continue
        run, want = [rest], 2                 # a 1 may start another list first: try every 1, then the first 2, 3, 4 after it
        for n2, r2 in entries[i + 1:]:
            if n2 == want:
                run.append(r2)
                want += 1
        if len(run) == 4 and all(re.search(_ITEM_WORDS[k], run[k], re.I) for k in range(4)):
            return True
    return False


def _head(msg):
    return (msg.splitlines() or [""])[0]


def _missing_items(stderr):
    m = re.search(r"Báo cáo 4 mục \(thiếu ([\d,]+)\)", stderr or "")
    return sorted(m.group(1).split(",")) if m else []


def _combine(parts):
    """One verdict from the verdicts of a block's reasons: a reason settled as right keeps the block right whatever the others
    say; else any reason the transcript cannot settle leaves it unknown; else every reason was wrong."""
    kinds = [p[0] for p in parts]
    for want in ("correct", "unknown"):
        if want in kinds:
            return next(p for p in parts if p[0] == want)
    if all(k == "fixed-since" for k in kinds):
        return parts[0]
    return next(p for p in parts if p[0] == "wrong")


# What the oracle takes for "a mention": copies of the hook's QUOTED_SPAN and OUTCOME_MENTION_WORD, on purpose (the before/after
# comparison needs an oracle that does not move with the fix); tests/gates/test_stop_replay.sh fails when they drift apart.
_QUOTE_SPAN = re.compile(r"\"[^\"\n]*\"|“[^”\n]*”|`[^`\n]*`")
_SENTENCE_END = re.compile(r"\n|[!?](?=\s|$)|\.(?=\s|$)")
_NAMES_A_QUOTE = re.compile(r"\b(?:chữ|cụm(?:\s+từ)?|words?|phrases?)\s+$", re.I)
_CONNECTIVE = re.compile(r"\bother\s+words?\s+$", re.I)
_NEGATION_BEFORE = re.compile(r"\bchưa\s+phải(?:\s+là)?\s+$", re.I)


def quoted_outcome(reply, rx):
    """How a reply holds the hook's outcome phrase ('đã fix', 'đã xử lý'...) when EVERY occurrence sits inside ONE pair of quotes or
    backticks: 'framed' when a naming word (chữ, cụm, phrase...) stands right before the opening quote and the phrase starts right
    after it, or "chưa phải" stands right before the phrase: a mention, not a claim; 'bare' when nothing says so (Kết quả:
    "đã fix"), which the hook counts on purpose; None otherwise."""
    body = re.sub(r"```.*?```", " ", reply or "", flags=re.S).replace("**", "")
    found = list(rx.finditer(body)) if rx is not None else []
    spans = [(m.start(), m.end()) for m in _QUOTE_SPAN.finditer(body)]
    cuts = [0] + [c.end() for c in _SENTENCE_END.finditer(body)]

    def quote_of(m):
        return next(((a, e) for a, e in spans if a < m.start() and m.end() < e), None)

    def framed(m):
        a, e = quote_of(m)
        start = max(c for c in cuts if c <= m.start())
        named = (_NAMES_A_QUOTE.search(body[start:a]) and not _CONNECTIVE.search(body[start:a]) and m.start() == a + 1
                 and re.fullmatch(r"[\s.,;:!?…]*", body[m.end():e - 1])     # the quote holds the phrase and nothing else
                 and not re.match(r"(?:bug|lỗi|issue|crash|error)\b", m.group(0), re.I))   # (these branches of OUTCOME carry the object)
        return bool(named or _NEGATION_BEFORE.search(re.sub(r"[`\"“”]", "", body[start:m.start()])))
    if not found or any(quote_of(m) is None for m in found):
        return None
    return "framed" if all(framed(m) for m in found) else "bare"


def report_after_last_push(stop):
    """True when an assistant message written after the turn's last push carries the 4-item report (what the hook accepts for a push
    turn that does not open with XONG). A push counts where its result stands. Needs the harness (its reading of a push)."""
    last = max([e.get("rn") or e["n"] for e in stop["events"] if e.get("push")], default=None)
    return last is not None and any(t["n"] > last and structured_report(t["text"]) for t in stop["texts"])


def classify_proof(block, sb):
    st, msg = block["stop"], block["message"]
    reply = st["reply"]
    parts = []
    push = "git push" in _head(msg)
    if "Báo cáo 4 mục" in msg:
        turn = turn_bytes(st)
        replay = sb.run("proof_gate", reply, turn) if sb is not None and (turn or not push) else None   # a push turn needs the turn
        if replay is not None and not _missing_items(replay[1]):
            parts.append(("fixed-since", "report", "the current hook accepts this reply"))
        elif structured_report(reply) or (push and report_after_last_push(st)):
            parts.append(("wrong", "report-label-variant", "the four items are there under other labels"))
        else:
            parts.append(("correct", "report-missing", "no 1..4 report in the final reply"))
    if "- Cổng:" in msg:
        parts.append(("unknown", "gate-receipt", "the gate receipt is not in the transcript"))
    if "- ẢNH" in msg:
        parts.append(("unknown", "image", "the image files are not in the transcript"))
    if "BEFORE" in msg:
        parts.append(("unknown", "before-evidence", "the turn class is not in the transcript"))
    if not parts:
        parts.append(("unknown", "other", "reason not recognised"))
    return _combine(parts)


def classify_te(block, sb):
    st, msg = block["stop"], block["message"]
    reply = st["reply"]
    parts = []
    replay = sb.run("test_evidence_gate", reply) if sb is not None and ("CHECK 7" in msg or "TEST-EVIDENCE" in msg) else None
    claim_now = None if replay is None else "TEST-EVIDENCE" in replay[1]
    outcome_now = None if replay is None else "CHECK 7" in replay[1]
    if "CHECK 7" in msg:
        kind = quoted_outcome(reply, hook_regex("test_evidence_gate", "OUTCOME"))
        if outcome_now is False:
            parts.append(("fixed-since", "quoted-outcome-mention" if kind == "framed" else "outcome",
                          "the current hook no longer reads an outcome claim here"))
        elif kind == "framed":
            parts.append(("wrong", "quoted-outcome-mention", "every outcome phrase is quoted and the sentence names or negates it"))
        elif kind == "bare":
            parts.append(("unknown", "quoted-outcome-bare", "quoted with nothing saying it is a mention: the hook counts it on purpose"))
        else:
            parts.append(("unknown", "outcome-proof", "whether this session has a RED->GREEN pair is not settled by the turn"))
    if "TEST-EVIDENCE" in msg:
        evs = st["events"]
        last_edit = max([i for i, e in enumerate(evs) if e["name"] in EDIT_TOOLS and CODE_EXT.search(e["path"])], default=-1)
        ran_after = any(e["name"] == "Bash" and TEST_RUN.search(e["cmd"]) for e in evs[last_edit + 1:])
        if claim_now is False:
            parts.append(("fixed-since", "claim", "the current hook no longer reads a test-pass claim here"))
        elif not ran_after:
            parts.append(("correct", "claim-no-fresh-run", "no test run after the last code edit of the turn"))
        else:
            parts.append(("unknown", "claim-xml", "the test XML on disk is not in the transcript"))
    if "RED-CHECK" in msg or "ANTI-LOOP" in msg:
        parts.append(("unknown", "red-history", "the red/green history is session state"))
    if re.search(r"BÀI HỌC|BUG CHƯA LINK|TEST VÔ HIỆU", msg):
        parts.append(("correct", "nudge-by-design", "a once-per-session reminder hold"))
    if not parts:
        parts.append(("unknown", "other", "reason not recognised"))
    return _combine(parts)


def classify_review(block, sb):
    st, msg = block["stop"], block["message"]
    sess = st["sess"]
    last_edit = max([e["n"] for e in sess["edits"] if CODE_EXT.search(e["path"])], default=-1)
    last_review = max([a["n"] for a in sess["agents"] if a["type"] in REVIEWERS] + [s["n"] for s in sess["skills"]
                                                                                     if s["skill"] in REVIEW_SKILLS], default=-1)
    head = _head(msg)
    if "máy có" in head or "OpenCodeReview" in msg:
        return ("unknown", "ocr-required", "needs the OCR report files and the git diff of that moment")
    if last_edit >= 0 and last_review < last_edit:
        return ("correct", "no-review-after-edit", "no fresh-context review after the last code edit of the session")
    return ("unknown", "review-after-edit", "a review ran after the last edit; the hook also reads the git diff and Bash writes")


CLASSIFY = {"proof_gate": classify_proof, "test_evidence_gate": classify_te, "review_gate": classify_review}


def analyze(blocks, replay=True):
    """Give every block of a classified hook its verdict: sets block['verdict'], ['cls'], ['why']."""
    sb = None
    if replay and any(b["hook"] in ("proof_gate", "test_evidence_gate") for b in blocks):
        try:
            sb = Sandbox()
        except (OSError, subprocess.SubprocessError) as e:    # no git, no temp space: the report still comes, without fixed-since
            print("stop_replay: no sandbox (%s): the hooks are not replayed" % type(e).__name__, file=sys.stderr)
    try:
        for b in blocks:
            fn = CLASSIFY.get(b["hook"])
            if fn is None:
                b["verdict"], b["cls"], b["why"] = "n/a", "-", "hook not classified"
            else:
                b["verdict"], b["cls"], b["why"] = fn(b, sb)
    finally:
        if sb is not None:
            sb.close()
    return blocks


# ── report ───────────────────────────────────────────────────────────────────────────────────────────────────────────
def build_report(stops, blocks, errors, min_stops=100):
    rows = collections.OrderedDict()
    blocked_stops = collections.defaultdict(set)        # (scope, repo) -> ids of Stops that were blocked
    entries = collections.Counter()
    for b in blocks:
        key = (b["hook"], b["repo"])
        r = rows.setdefault(key, {"hook": b["hook"], "repo": b["repo"], "blocks": 0, "verdicts": collections.Counter(),
                                  "classes": collections.Counter(), "examples": collections.defaultdict(list), "bg": 0, "chain": 0})
        r["blocks"] += 1
        r["verdicts"][b["verdict"]] += 1
        r["classes"][(b["verdict"], b["cls"])] += 1
        r["bg"] += 1 if b["stop"]["bg_open"] else 0
        r["chain"] += 1 if b["hook"] in (b["stop"].get("next_blocks") or ()) else 0   # the next Stop of the turn was blocked by it again
        for scope in ("all", "classified") if b["hook"] in GATES else ("all",):
            blocked_stops[(scope, b["repo"])].add(b["stop"]["uuid"] or id(b["stop"]))
            entries[(scope, b["repo"])] += 1
        if b["verdict"] == "wrong":
            r["examples"][b["cls"]].append(b)
    rates = []
    for repo, n in sorted(stops.items(), key=lambda x: -x[1]):
        rates.append({"repo": repo, "stops": n, "in_scope": n >= min_stops, "errors": errors.get(repo, 0),
                      **{"%s_%s" % (scope, k): v for scope in ("all", "classified")
                         for k, v in (("blocked_stops", len(blocked_stops[(scope, repo)])), ("entries", entries[(scope, repo)]))}})
    return {"rows": list(rows.values()), "rates": rates, "stops_total": sum(stops.values())}


def format_text(rep, days, examples, min_stops=100):
    out = ["Stop replay: last %g days, %d Stops in %d repos" % (days, rep["stops_total"], len(rep["rates"])), ""]
    out.append("%-20s %-30s %6s %6s %7s %5s %6s %6s %6s" % ("hook", "repo", "blocks", "correct", "WRONG", "fixed", "unknown", "bg",
                                                            "chain"))
    for r in sorted(rep["rows"], key=lambda r: (r["hook"] not in GATES, r["hook"], -r["blocks"])):
        v = r["verdicts"]
        out.append("%-20s %-30s %6d %6d %7d %5d %6d %6d %6d" % (r["hook"], r["repo"][:30], r["blocks"], v["correct"], v["wrong"],
                                                                 v["fixed-since"], v["unknown"], r["bg"], r["chain"]))
    out += ["", "bg    = blocks that came while a background task of the turn (a reviewer, a gate, a push) had not reported done.",
            "chain = blocks after which the next Stop of the turn was blocked by the same hook again.", ""]
    out.append("Blocks per Stop (target <= 0.10 in repos with >= %d Stops; a Stop with two blocking hooks counts once in 'Stops'):"
               % min_stops)
    out.append("%-30s %6s  %-16s %-16s %-16s %-16s" % ("repo", "Stops", "3 hooks: Stops", "3 hooks: entries", "all hooks: Stops", "all: entries"))
    for x in rep["rates"]:
        s = max(x["stops"], 1)
        out.append("%-30s %6d  %5d  %5.2f     %5d  %5.2f     %5d  %5.2f     %5d  %5.2f%s" % (
            x["repo"][:30], x["stops"], x["classified_blocked_stops"], x["classified_blocked_stops"] / s, x["classified_entries"],
            x["classified_entries"] / s, x["all_blocked_stops"], x["all_blocked_stops"] / s, x["all_entries"], x["all_entries"] / s,
            "" if x["in_scope"] else "  (under the Stop floor)"))
    out += ["", "Verdict classes (hook, verdict, class: count):"]
    cls = collections.Counter()
    for r in rep["rows"]:
        for (verdict, c), n in r["classes"].items():
            cls[(r["hook"], verdict, c)] += n
    for (hook, verdict, c), n in sorted(cls.items(), key=lambda x: (x[0][0] not in GATES, x[0][0], x[0][1], -x[1])):
        if hook in GATES:
            out.append("  %-18s %-12s %-26s %4d" % (hook, verdict, c, n))
    if examples:
        out += ["", "Examples of WRONG blocks (reply head, masked):"]
        shown = collections.Counter()
        for r in rep["rows"]:
            for c, items in r["examples"].items():
                for b in items:
                    if shown[(r["hook"], c)] < examples:
                        shown[(r["hook"], c)] += 1
                        out.append("  %s / %s / %s: %s" % (r["hook"], r["repo"], c, mask(b["stop"]["reply"], 110)))
    return "\n".join(out)


def to_json(rep):
    def clean(r):
        return {"hook": r["hook"], "repo": r["repo"], "blocks": r["blocks"], "verdicts": dict(r["verdicts"]), "bg": r["bg"],
                "chain": r["chain"], "classes": {"%s:%s" % k: v for k, v in r["classes"].items()}}
    return json.dumps({"stops_total": rep["stops_total"], "rates": rep["rates"], "rows": [clean(r) for r in rep["rows"]]},
                      ensure_ascii=False, indent=1)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--days", type=float, default=7)
    ap.add_argument("--root", action="append", help="a projects folder (repeatable); replaces the defaults")
    ap.add_argument("--hook", action="append", help="only blocks of this hook (repeatable)")
    ap.add_argument("--examples", type=int, default=2, help="masked examples per WRONG class (0: none)")
    ap.add_argument("--min-stops", type=int, default=100)
    ap.add_argument("--no-replay", action="store_true", help="do not run the hooks in a sandbox (fixed-since is then never given)")
    ap.add_argument("--hooks", help="replay against the hooks/ folder of another kit checkout (a before/after comparison); default: this kit")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    global HOOKS_DIR
    if a.hooks:
        HOOKS_DIR = os.path.abspath(a.hooks)
        _REGEX_CACHE.clear()
    harness = load_harness()
    if harness is None:
        print("stop_replay: hooks/devkit_harness.py did not load: prompts are read loosely and pushes are not seen", file=sys.stderr)
    stops, blocks, errors = collect(a.root or DEFAULT_ROOTS, a.days, harness, set(a.hook) if a.hook else None)
    analyze(blocks, replay=not a.no_replay)
    rep = build_report(stops, blocks, errors, a.min_stops)
    print(to_json(rep) if a.json else format_text(rep, a.days, a.examples, a.min_stops))
    return 0


if __name__ == "__main__":
    sys.exit(main())
