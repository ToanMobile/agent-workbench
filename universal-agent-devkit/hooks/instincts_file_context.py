#!/usr/bin/env python3
"""PreToolUse(Read|Edit) hook: show the instincts whose `- **glob:**` line matches the file being opened (#555).

An entry opts in with one line, e.g. `- **glob:** `src/api/**`, `*.sql``. A pattern with no `/` matches the
basename anywhere; `**` crosses directories, `*` and `?` do not. Each entry is injected once per session
(.claude/audit-gate/instinct_file_seen/<session>) and logged to surfaced.jsonl like a prompt-matched one, so
`instincts.py archive` counts it as shown. Entries without a glob keep the prompt path (enrich_context.py).

Never blocks: any error is logged (stderr + .claude/audit-gate/instincts_file_context.err) and the exit is 0.
"""
import json
import os
import re
import sys
import time

GLOB_LINE = re.compile(r"^- \*\*glob:\*\*[ \t]*(.+)$", re.MULTILINE)
CHUNK_SPLIT = re.compile(r"(?m)^(?=### \[INSTINCT-|## )")
HEADING = re.compile(r"^### \[(INSTINCT-[A-Za-z0-9_-]+)\]")
SAFE_SESSION = re.compile(r"[^A-Za-z0-9._-]")


def glob_regex(pattern):
    """`**` any depth, `*` / `?` within one segment; a pattern with no `/` matches at any depth."""
    pattern = pattern.strip().lstrip("/")
    out, i = [], 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    body = "".join(out)
    return re.compile(("(?:.*/)?" if "/" not in pattern else "") + body + r"\Z")


def entries_for(rel, text):
    """[(id, line, chunk)] of the entries whose glob matches the project-relative path."""
    found = []
    for chunk in CHUNK_SPLIT.split(text):
        head = HEADING.match(chunk)
        gl = GLOB_LINE.search(chunk) if head else None
        if not gl:
            continue
        pats = [p.strip().strip("`").strip() for p in gl.group(1).split(",")]
        if any(p and glob_regex(p).match(rel) for p in pats):
            line = text.count("\n", 0, text.index(chunk)) + 1
            body = re.sub(r"\n---\s*\Z", "", chunk.rstrip()).rstrip()
            found.append((head.group(1), line, body))
    return found


def run(payload):
    inp = payload.get("tool_input") or payload.get("toolInput") or {}
    path = inp.get("file_path") or inp.get("target_file") or ""
    root = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd()
    if not isinstance(path, str) or not path:
        return
    root = os.path.realpath(root)
    full = os.path.realpath(path if os.path.isabs(path) else os.path.join(root, path))
    if not full.startswith(root + os.sep):
        return
    rel = full[len(root) + 1:]
    hits = []
    for name in ("instincts.md", os.path.join("active-profile", "instincts.md")):
        src = os.path.join(root, ".agents", name)
        if os.path.isfile(src):
            with open(src, encoding="utf-8") as fh:
                text = fh.read()
            hits += [(i, ln, c, os.path.join(".agents", name)) for i, ln, c in entries_for(rel, text)]
    if not hits:
        return
    log_dir = os.path.join(root, ".claude", "audit-gate")
    session = SAFE_SESSION.sub("_", str(payload.get("session_id") or "nosession"))
    seen_dir = os.path.join(log_dir, "instinct_file_seen")
    os.makedirs(seen_dir, exist_ok=True)
    seen_file = os.path.join(seen_dir, session)
    seen = set()
    if os.path.isfile(seen_file):
        with open(seen_file, encoding="utf-8") as fh:
            seen = set(fh.read().split())
    fresh = [h for h in hits if h[0] not in seen]
    if not fresh:
        return
    with open(seen_file, "a", encoding="utf-8") as fh:
        fh.write("".join(h[0] + "\n" for h in fresh))
    refs = [{"id": i, "file": f, "line": ln} for i, ln, _, f in fresh]
    with open(os.path.join(log_dir, "surfaced.jsonl"), "a", encoding="utf-8") as fh:
        fh.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "session": str(payload.get("session_id") or ""),
                             "file": rel, "instinct_ids": [r["id"] for r in refs], "instinct_refs": refs},
                            ensure_ascii=False) + "\n")
    ctx = f"[instincts] bài học gắn với file {rel}:\n\n" + "\n\n".join(h[2] for h in fresh)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": ctx}}, ensure_ascii=False))


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
        if isinstance(payload, dict):
            run(payload)
    except Exception as exc:   # never block a Read/Edit: log it with context and exit 0
        msg = f"instincts_file_context: {type(exc).__name__}: {exc}"
        print(msg, file=sys.stderr)
        try:
            d = os.path.join(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd(), ".claude", "audit-gate")
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "instincts_file_context.err"), "a", encoding="utf-8") as fh:
                fh.write(time.strftime("%Y-%m-%dT%H:%M:%S ") + msg + "\n")
        except OSError as log_exc:   # the stderr line above already carries the original error
            print(f"instincts_file_context: error log not written: {log_exc}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
