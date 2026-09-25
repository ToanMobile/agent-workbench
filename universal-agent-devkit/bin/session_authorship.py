"""Who wrote a file: this Claude Code session, or someone else?

One rule shared by bin/post-fix-gate.py (split_tests_by_author: an existing test edited by
this session blocks, by another session only warns) and hooks/testsourceset_gate.sh (which
modules THIS session touched). Sources: the session's Edit/Write/MultiEdit/NotebookEdit calls
(its sub-agents' too), its write-shaped Bash commands, and the Bash windows of every session in
.claude/audit-gate/bash_write_ledger.tsv. Every caller fails closed: no transcript, an
unreadable one, or a tool the rule cannot see through (read_only_tool) means "cannot tell".
"""
import fnmatch
import glob
import json
import os
import re
import time
from pathlib import Path

EDIT_TOOLS = ("Edit", "MultiEdit", "Write", "NotebookEdit")

# rm / git rm count as writes: a deleted file has no mtime, naming it is the only trace.
# touch / ln too: `touch -t 2020… <file>` after a write moves the mtime out of every window.
# Archive/sync tools (tar, rsync, unzip, cpio, 7z, git archive) restore files with old mtimes.
WRITE_VERB_RE = re.compile(r"\bsed\s+(-[A-Za-z]*i|--in-place)|\bperl\s+-[A-Za-z]*i|\btee\b|"
                           r"\b(cp|mv|rm|install|patch|dd|truncate|touch|ln|tar|rsync|unzip|cpio|7z)\b|"
                           r"\bgit\s+(apply|am|archive|checkout|restore|rm|mv)\b")
REDIRECT_TARGET_RE = re.compile(r">>?\s*[\"']?([^\s\"'<>|;&()]+)")
PATH_TOKEN_RE = re.compile(r"[^\s\"'<>|;&()=]+")

# Tools that cannot write a project file (taken from the tool names in real Claude Code
# transcripts, 2026-09-25). Any other tool — a write-capable MCP tool, an external agent
# dispatch, Monitor/Workflow running commands outside the Bash ledger — can write where the
# rule cannot see it: its session's writes are then unknown (fail closed).
# Sub-agents (Task/Agent/SendMessage) are read through their own transcripts.
READ_ONLY_TOOLS = frozenset((
    "Read", "Grep", "Glob", "LS", "WebFetch", "WebSearch", "TodoWrite", "TodoRead", "Task", "Agent",
    "SendMessage", "ListAgents", "TaskOutput", "BashOutput", "TaskStop", "KillShell", "TaskCreate",
    "TaskUpdate", "TaskList", "TaskGet", "ToolSearch", "Skill", "AskUserQuestion", "ExitPlanMode",
    "EnterPlanMode", "ScheduleWakeup", "ReadNotifications", "SendUserFile", "SendFeedback", "LSP",
    "advisor", "SubagentHandback",
    # antigravity-pm reads. pm_report writes one report .md into the task's state directory
    # (src/report.js writeFileAtomic(paths.report)), never a project source or test file.
    "mcp__antigravity-pm__pm_status", "mcp__antigravity-pm__pm_diff",
    "mcp__antigravity-pm__pm_report", "mcp__antigravity-pm__pm_doctor",
    # pm_ack records an acknowledged warning in the PM's task.json (state), no project file.
    "mcp__antigravity-pm__pm_ack",
    # replicant (Android device) reads: the UI tree. ui-action drives the device: not listed.
    "mcp__replicant-mcp__ui-query"))
# Tools that write exactly the one file their input names: that path counts as written by the
# session (like Write). Without an absolute path the tool is opaque. ui-capture reads the screen
# and, with localPath, saves it there.
PATH_WRITE_TOOLS = {"mcp__replicant-mcp__ui-capture": "localPath"}
# An MCP tool (mcp__<server>__<tool>) counts as read-only when its own name clearly reads:
# get_/read-/… (snake, kebab) or getJiraIssue/searchJiraIssuesUsingJql (camelCase) — and none
# of its words writes (getOrCreateFile, searchAndReplace stay write-capable).
MCP_READ_RE = re.compile(r"^(?:(?i:get|read|list|search|query|fetch)[_-]|(?:get|read|list|search|query|fetch)[A-Z])")
_MCP_WRITE_WORDS = frozenset((
    "create", "update", "edit", "write", "delete", "remove", "replace", "set", "put", "post", "patch",
    "add", "insert", "move", "rename", "upsert", "apply", "commit", "push", "merge", "transition",
    "upload", "save", "send", "modify", "append", "drop", "clear", "reset", "run", "exec", "execute"))
_WORD_RE = re.compile(r"[A-Z]?[a-z]+|[A-Z]+(?![a-z])|\d+")


def read_only_tool(name) -> bool:
    if not isinstance(name, str):
        return False
    if name in READ_ONLY_TOOLS:
        return True
    if name.startswith("mcp__"):
        tool = name.rsplit("__", 1)[-1]
        return (bool(MCP_READ_RE.match(tool))
                and not any(w.lower() in _MCP_WRITE_WORDS for w in _WORD_RE.findall(tool)))
    return False


def _ts(value):
    """Epoch seconds of a transcript ISO timestamp, or None."""
    from datetime import datetime  # noqa: PLC0415
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def session_trace(transcript: str):
    """(files written by Edit/Write tools, Bash commands, first timestamp, Bash call count,
    opaque) of a session, from its transcript and its sub-agents' — or None when there is nothing
    to judge by (no transcript, unreadable, not one tool call). opaque: it called a tool that may
    write where neither the transcript nor the Bash ledger shows it (not read_only_tool)."""
    if not transcript or not os.path.isfile(transcript):
        return None
    edited, bash, started, tool_uses, opaque = set(), [], None, 0, False
    subs = sorted(Path(os.path.splitext(transcript)[0], "subagents").glob("*.jsonl"))
    for i, path in enumerate([Path(transcript)] + subs):
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            if i == 0:
                return None
            continue
        for line in lines:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if not isinstance(rec, dict):
                continue
            if i == 0 and started is None:
                started = _ts(rec.get("timestamp"))
            content = (rec.get("message") or {}).get("content") if isinstance(rec.get("message"), dict) else None
            for blk in content if isinstance(content, list) else []:
                if not isinstance(blk, dict) or blk.get("type") != "tool_use":
                    continue
                tool_uses += 1
                inp = blk.get("input") if isinstance(blk.get("input"), dict) else {}
                if blk.get("name") in EDIT_TOOLS:
                    fp = inp.get("file_path") or inp.get("notebook_path")
                    if isinstance(fp, str) and fp:
                        edited.add(os.path.realpath(fp))
                elif blk.get("name") == "Bash":
                    if isinstance(inp.get("command"), str):
                        bash.append(inp["command"])
                elif blk.get("name") in PATH_WRITE_TOOLS:
                    fp = inp.get(PATH_WRITE_TOOLS[blk["name"]])
                    if isinstance(fp, str) and os.path.isabs(fp):
                        edited.add(os.path.realpath(fp))
                    elif fp is not None:
                        opaque = True
                elif not read_only_tool(blk.get("name")):
                    opaque = True
    return (edited, bash, started, len(bash), opaque) if tool_uses else None


def shell_named(commands) -> set:
    """Path tokens a Bash command may write: `>`/`>>` targets always, every token of a
    write-shaped command (WRITE_VERB_RE); a leading ./ is dropped."""
    named = set()
    for cmd in commands:
        toks = set(REDIRECT_TARGET_RE.findall(cmd))
        if WRITE_VERB_RE.search(cmd):
            toks |= set(PATH_TOKEN_RE.findall(cmd))
        named |= {t[2:] if t.startswith("./") else t for t in toks}
    return named


def names_path(named, root, rel) -> bool:
    """True when a token of shell_named() may name repo-relative path rel: the path itself, a
    suffix of it, a glob matching it (src/test/*.kt), or a directory holding it (src/, ., an
    absolute one)."""
    full = os.path.realpath(os.path.join(root, rel))
    for t in named:
        if t == rel or rel.endswith("/" + t) or fnmatch.fnmatchcase(rel, t) or fnmatch.fnmatchcase(full, t):
            return True
        target = os.path.realpath(os.path.join(root, t or "."))
        if full == target or full.startswith(target.rstrip(os.sep) + os.sep):
            return True
    return False


def bash_windows(project) -> list:
    """(start, end, session) of every Bash command in bash_write_ledger.tsv; a start with no
    end (a backgrounded command) stays open until now."""
    windows, opens = [], {}
    try:
        with open(Path(project) / ".claude" / "audit-gate" / "bash_write_ledger.tsv", encoding="utf-8") as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if len(parts) != 4:
                    continue
                sid, kind, stamp, tuid = parts
                try:
                    stamp = float(stamp)
                except ValueError:
                    continue
                if kind == "start":
                    opens[(sid, tuid)] = stamp
                elif kind == "end" and (sid, tuid) in opens:
                    windows.append((opens.pop((sid, tuid)), stamp, sid))
    except OSError:
        return []
    return windows + [(st, time.time(), sid) for (sid, _), st in opens.items()]


# Bounds of the scan of other sessions' transcripts (it runs inside a Stop hook).
SCAN_TAIL_BYTES = 8 << 20    # only the last 8 MB of a transcript: the recent edits are at its end
SCAN_MAX_FILES = 64          # the most recently modified ones
SCAN_DEADLINE_S = 2.0
NO_RESULT_SLACK_S = 5.0      # a tool_use with no tool_result (yet): its write lands within seconds


def other_session_edits(transcript, session, targets, since) -> dict:
    """{realpath: [(start, end, session), …]} — the Edit/Write/MultiEdit/NotebookEdit calls of
    OTHER Claude Code sessions (and their sub-agents) on the realpaths in targets, read from the
    transcripts next to this one (~/.claude/projects/<slug>/<id>.jsonl, <id>/subagents/*.jsonl).
    A window runs from its tool_use to its tool_result (±1 s); a failed call (is_error) has none.
    Only transcripts modified at or after `since`, only their last SCAN_TAIL_BYTES. Records of
    this session (a fork's copy) are skipped. Any error or the deadline gives {}: no evidence, so
    the caller keeps blocking."""
    try:
        return _other_session_edits(transcript, session, set(targets), since)
    except Exception:  # noqa: BLE001 - fail closed: evidence of "other" must be certain
        return {}


def _tail_lines(path):
    with open(path, "rb") as fh:
        size = fh.seek(0, os.SEEK_END)
        start = max(0, size - SCAN_TAIL_BYTES)
        fh.seek(start)
        data = fh.read(SCAN_TAIL_BYTES)
    if start:
        data = data.split(b"\n", 1)[1] if b"\n" in data else b""
    return data.decode("utf-8", "replace").splitlines()


def _other_session_edits(transcript, session, targets, since):
    if not targets or not transcript or since is None:
        return {}
    deadline = time.monotonic() + SCAN_DEADLINE_S
    here = os.path.realpath(transcript)
    own_subs = os.path.splitext(here)[0] + os.sep
    folder = os.path.dirname(here)
    cands = []
    for t in glob.glob(os.path.join(folder, "*.jsonl")) + glob.glob(os.path.join(folder, "*", "subagents", "*.jsonl")):
        rt = os.path.realpath(t)
        if rt == here or rt.startswith(own_subs):
            continue
        try:
            mt = os.path.getmtime(rt)
        except OSError:
            continue   # vanished since the glob: it holds no evidence
        if mt >= since:
            cands.append((mt, rt))
    cands.sort(reverse=True)
    needles = {json.dumps(os.path.basename(p))[1:-1] for p in targets}
    found = {}
    for _, t in cands[:SCAN_MAX_FILES]:
        if time.monotonic() > deadline:
            return {}
        lines = _tail_lines(t)
        uses = {}   # tool_use id -> (start, realpath, session)
        for line in lines:
            if '"tool_use"' not in line or not any(n in line for n in needles):
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if not isinstance(rec, dict):
                continue
            sid, ts, msg = rec.get("sessionId"), _ts(rec.get("timestamp")), rec.get("message")
            if sid == session or ts is None or not isinstance(msg, dict) or not isinstance(msg.get("content"), list):
                continue
            for blk in msg["content"]:
                if not isinstance(blk, dict) or blk.get("type") != "tool_use" or blk.get("name") not in EDIT_TOOLS:
                    continue
                inp = blk.get("input") if isinstance(blk.get("input"), dict) else {}
                fp = inp.get("file_path") or inp.get("notebook_path")
                if isinstance(fp, str) and os.path.isabs(fp) and os.path.realpath(fp) in targets \
                        and isinstance(blk.get("id"), str):
                    uses[blk["id"]] = (ts, os.path.realpath(fp), sid if isinstance(sid, str) and sid else "transcript:" + t)
        if not uses:
            continue
        ends = {}   # tool_use id -> end, or None for a call that failed
        for line in lines:
            if '"tool_result"' not in line or not any(u in line for u in uses):
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            msg = rec.get("message") if isinstance(rec, dict) else None
            if not isinstance(msg, dict) or not isinstance(msg.get("content"), list):
                continue
            ts = _ts(rec.get("timestamp"))
            for blk in msg["content"]:
                if isinstance(blk, dict) and blk.get("type") == "tool_result" and blk.get("tool_use_id") in uses:
                    failed = blk.get("is_error") or rec.get("toolDenialKind") or ts is None
                    ends[blk["tool_use_id"]] = None if failed else ts
        for tid, (st, rp, sid) in uses.items():
            end = ends[tid] if tid in ends else st + NO_RESULT_SLACK_S
            if end is not None:
                found.setdefault(rp, []).append((st - 1, end + 1, sid))
    return found


def window_owner(mt, windows):
    """Session of the narrowest window holding mtime mt; "" on an exact tie across sessions;
    None when no window holds it."""
    best = None   # (width, session)
    for st, en, sid in windows:
        if not st <= mt <= en:
            continue
        if best is None or en - st < best[0]:
            best = (en - st, sid)
        elif en - st == best[0] and sid != best[1]:
            best = (best[0], "")
    return None if best is None else best[1]
