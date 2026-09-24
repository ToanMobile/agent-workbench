#!/usr/bin/env python3
"""
memory_stats.py — does the failure memory reach the model on REAL prompts?

  memory_stats.py <project> [<project> …] [--json] [--top N]      (agent-kit memory-stats)

For each project, from its Claude Code transcripts (~/.claude/projects/<slug>/*.jsonl):
  1. Replay: every prompt the user typed (no slash command, no <wrapped> peer/system
     message, no sidechain, no tool result; repeats counted once) through the CURRENT prompt
     hook logic — scripts/enrich_context.py (traps) and scripts/rule_context.py (project-rule
     sections) — read-only: nothing is written, no REPORTED row, no inbox. Reports the % of
     prompts that get a trap, a rule, either; the traps shown most; the project's traps
     (.agents/instincts.md) never shown.
  2. Surfaced → read: what the hook REALLY printed in those sessions (UserPromptSubmit
     hook_success attachments naming `[INSTINCT-…] … sed -n 'a,bp' <file>`), and how often
     the model then opened that range in the same session (Read of the file overlapping
     a..b or without an offset, or a Bash `sed -n 'a,b…` on it).
Standard library only. Prompt texts are never printed — only counts and trap ids.
"""

from __future__ import annotations

import collections
import contextlib
import glob
import io
import json
import os
import re
import sys
from pathlib import Path

DEVKIT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(DEVKIT / "scripts"))
sys.dont_write_bytecode = True

SHOWN_RE = re.compile(r"\[(INSTINCT-[A-Za-z0-9_-]+)\][^\n]*?sed -n '(\d+),(\d+)p' ([^`\s]+)")
HEAD_RE = re.compile(r"^### \[(INSTINCT-[A-Za-z0-9_-]+)\]", re.M)


def slug(project: Path) -> str:
    return re.sub(r"[^A-Za-z0-9]", "-", str(project))


def transcripts(project: Path, given: str | None = None) -> list:
    """Claude names the folder after the path the session started in — resolved or not
    (/var → /private/var on macOS): try both."""
    home = Path(os.environ.get("HOME", "~")).expanduser()
    out = []
    for cand in dict.fromkeys([str(project), given or str(project), os.path.abspath(given or str(project))]):
        out += glob.glob(str(home / ".claude" / "projects" / slug(Path(cand)) / "*.jsonl"))
    return sorted(set(out))


def records(path: str):
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                yield json.loads(line)
            except ValueError:
                continue


def typed_prompt(rec: dict) -> str | None:
    if rec.get("type") != "user" or rec.get("isSidechain") or rec.get("isMeta"):
        return None
    content = (rec.get("message") or {}).get("content")
    if isinstance(content, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
            return None
        content = "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    if not isinstance(content, str):
        return None
    text = content.strip()
    if len(text) < 8 or text.startswith(("/", "<", "Caveat:", "[Request interrupted")):
        return None
    return text


def replay(project: Path, prompts: list) -> tuple:
    import enrich_context as ec
    import rule_context as rcx
    traps, rules = [], []
    # Read-only by construction AND by switch: nothing a replayed prompt does may reach the
    # user's checklist, inbox state or recall log, even if the hook logic changes later.
    guards = {"BUG_CAPTURE": "0", "SURFACED_LOG": "0", "INBOX_WATCH": "0"}
    saved = {k: os.environ.get(k) for k in guards}
    os.environ.update(guards)
    old_env = os.environ.get("CLAUDE_PROJECT_DIR")
    os.environ["CLAUDE_PROJECT_DIR"] = str(project)
    try:
        for p in prompts:
            dossier = ec.enrich_prompt(p, str(DEVKIT), str(project))
            ids = []
            for r in ec.shown_refs(dossier):
                m = ec.INSTINCT_ID_RE.search(r["title"])
                ids.append(m.group(1) if m else r["title"][:60])
            traps.append(ids)
            out, stdin = io.StringIO(), sys.stdin
            try:
                sys.stdin = io.StringIO(json.dumps({"prompt": p}))
                with contextlib.redirect_stdout(out):
                    rcx.main()
            except Exception:  # noqa: BLE001 — a rule-matcher failure is "no rule", not a crash
                pass
            finally:
                sys.stdin = stdin
            rules.append([l.strip()[2:] for l in out.getvalue().splitlines() if l.strip().startswith("- ")])
    finally:
        if old_env is None:
            os.environ.pop("CLAUDE_PROJECT_DIR", None)
        else:
            os.environ["CLAUDE_PROJECT_DIR"] = old_env
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    return traps, rules


def read_after(recs: list, start: int, path: str, a: int, b: int) -> bool:
    base = os.path.basename(path)
    for rec in recs[start:]:
        content = (rec.get("message") or {}).get("content")
        if rec.get("type") != "assistant" or not isinstance(content, list):
            continue
        for blk in content:
            if not isinstance(blk, dict) or blk.get("type") != "tool_use":
                continue
            inp = blk.get("input") or {}
            if blk.get("name") == "Read" and str(inp.get("file_path", "")).endswith(path.lstrip("./")) \
                    or (blk.get("name") == "Read" and os.path.basename(str(inp.get("file_path", ""))) == base
                        and path.startswith(".agents/")):
                off = inp.get("offset")
                if off is None:
                    return True
                lim = inp.get("limit") or 2000
                if int(off) <= b and int(off) + int(lim) >= a:
                    return True
            if blk.get("name") == "Bash":
                cmd = str(inp.get("command", ""))
                if re.search(rf"sed -n ['\"]?{a},", cmd) and base in cmd:
                    return True
    return False


def stats(project: Path, top: int = 10, given: str | None = None) -> dict:
    files = transcripts(project, given)
    prompts, seen = [], set()
    surfaced, read = 0, 0
    per_id_shown, per_id_read = collections.Counter(), collections.Counter()
    for f in files:
        recs = list(records(f))
        for i, rec in enumerate(recs):
            p = typed_prompt(rec)
            if p and p not in seen:
                seen.add(p)
                prompts.append(p)
            att = rec.get("attachment") if rec.get("type") == "attachment" else None
            if isinstance(att, dict) and att.get("hookEvent") == "UserPromptSubmit" \
                    and isinstance(att.get("content"), str):
                for m in SHOWN_RE.finditer(att["content"]):
                    iid, a, b, path = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)
                    surfaced += 1
                    per_id_shown[iid] += 1
                    if read_after(recs, i + 1, path, a, b):
                        read += 1
                        per_id_read[iid] += 1
    traps, rules = replay(project, prompts)
    with_trap = sum(1 for t in traps if t)
    with_rule = sum(1 for r in rules if r)
    either = sum(1 for t, r in zip(traps, rules) if t or r)
    shown = collections.Counter(i for t in traps for i in t)
    try:
        text = (project / ".agents" / "instincts.md").read_text(encoding="utf-8", errors="replace")
        text = re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)     # the commented-out template
        own = [i for i in HEAD_RE.findall(text) if "XXX" not in i]
    except OSError:
        own = []
    n = len(prompts) or 1
    return {
        "project": str(project), "transcripts": len(files), "prompts": len(prompts),
        "with_trap": with_trap, "with_rule": with_rule, "with_either": either,
        "pct_trap": round(100 * with_trap / n, 1), "pct_rule": round(100 * with_rule / n, 1),
        "pct_trap_or_rule": round(100 * either / n, 1),
        "top_surfaced": shown.most_common(top),
        "own_instincts": len(own),
        "never_surfaced": [i for i in own if i not in shown],
        "surfaced_events": surfaced, "read_events": read,
        "read_rate": round(100 * read / surfaced, 1) if surfaced else None,
        "top_read": per_id_read.most_common(top),
    }


def text_report(s: dict) -> str:
    rr = f"{s['read_rate']}%" if s["read_rate"] is not None else "—"
    lines = [f"## {Path(s['project']).name} — {s['transcripts']} transcript, {s['prompts']} prompt thật",
             f"  Phát lại qua hook hiện tại: bẫy {s['pct_trap']}% · luật dự án {s['pct_rule']}% · "
             f"ít nhất một {s['pct_trap_or_rule']}%",
             f"  Hook thật đã in {s['surfaced_events']} bẫy → model mở đọc {s['read_events']} ({rr})",
             f"  Bẫy hiện nhiều nhất: " + (", ".join(f"{i}×{c}" for i, c in s["top_surfaced"]) or "—"),
             f"  Bẫy của dự án chưa từng hiện ({len(s['never_surfaced'])}/{s['own_instincts']}): "
             + (", ".join(s["never_surfaced"][:15]) + (" …" if len(s["never_surfaced"]) > 15 else "") or "—")]
    return "\n".join(lines)


def main(argv=None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    as_json = "--json" in args
    top = 10
    if "--top" in args:
        top = int(args[args.index("--top") + 1])
        del args[args.index("--top"):args.index("--top") + 2]
    given = [a for a in args if not a.startswith("--")] or [os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()]
    results = [stats(Path(g).expanduser().resolve(), top, os.path.expanduser(g)) for g in given]
    if as_json:
        print(json.dumps(results[0] if len(results) == 1 else results, ensure_ascii=False, indent=2))
    else:
        print("\n\n".join(text_report(s) for s in results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
