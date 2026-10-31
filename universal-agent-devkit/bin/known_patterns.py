#!/usr/bin/env python3
"""known_patterns.py — the bug-pattern registry, read from the project's existing failure memory (.agents/instincts.md).

There is no second registry: every `### [INSTINCT-…]` entry of .agents/instincts.md (written by `instincts.py add` /
`agent-kit learn`, post-fix-gate --record-lesson) is a known bug pattern. Two optional lines make one machine-checkable:

  - **glob:** `src/api/**`, `*.sql`          (already read by hooks/instincts_file_context.py)
  - **detect:** `except\\s*:\\s*pass`          (one or more backticked Python regexes, matched against ADDED diff lines)
  - **detect-glob:** `*.py`, `*.sh`          (files the detect regexes apply to; default: the entry's glob, else every file)

Subcommands
  context [--files F ...] [--max N]   compact Markdown of the patterns, for the reviewers' prompts (all 3 get the same text)
  scan --base REF [--out FILE]        added lines of `git diff REF` (+ untracked files) that match a `detect` regex in a file
                                      the entry's globs cover → a reviewer envelope "registry" (P0, category recurring-bug)
  semgrep --out FILE                  one semgrep rule (pattern-regex, paths.include = globs) per entry with a detect regex
  list                                JSON of the parsed entries

Library: entries(repo) / match_finding(entries, finding) (bin/review-merge.py flags a match as a P0 recurring bug).
Exit: 0 ok (scan: no hit), 1 scan hit, 2 usage / io error. Standard library only.
"""
import argparse
import json
import os
import re
import subprocess
import sys

HEAD_RX = re.compile(r"^### \[(INSTINCT-[A-Za-z0-9_-]+)\][ \t]*(.*)$", re.MULTILINE)
CHUNK_SPLIT = re.compile(r"(?m)^(?=### \[INSTINCT-|## )")
FIELD_RX = re.compile(r"^- \*\*([^*:]+):?\*\*:?[ \t]*(.*)$", re.MULTILINE)
TICKS = re.compile(r"`([^`]+)`")
ID_IN_TEXT = re.compile(r"\bINSTINCT-[A-Za-z0-9_-]+\b")
CAUSE_KEYS = ("nguyên nhân", "nguyên nhân gốc rễ", "cause")
RULE_KEYS = ("quy tắc phòng ngừa & cách fix", "quy tắc bắt buộc", "prevention & fix", "rule")


def registry_path(repo):
    for rel in (".agents/instincts.md", "universal-agent-devkit/.agents/instincts.md"):
        p = os.path.join(repo, rel)
        if os.path.isfile(p):
            return p
    return os.path.join(repo, ".agents/instincts.md")


def glob_regex(pattern):
    """Same rule as hooks/instincts_file_context.py: `**` any depth, `*`/`?` one segment, no `/` = basename anywhere."""
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


def parse(text):
    out = []
    for chunk in CHUNK_SPLIT.split(text or ""):
        m = HEAD_RX.match(chunk)
        if not m:
            continue
        fields = {}
        for fm in FIELD_RX.finditer(chunk):
            fields.setdefault(fm.group(1).strip().lower(), fm.group(2).strip())
        globs = TICKS.findall(fields.get("glob", "")) or [g.strip() for g in fields.get("glob", "").split(",") if g.strip()]
        detect = TICKS.findall(fields.get("detect", ""))
        dglobs = TICKS.findall(fields.get("detect-glob", "")) or globs
        compiled = []
        for rx in detect:
            try:
                compiled.append(re.compile(rx))
            except re.error as e:
                print(f"known_patterns: {m.group(1)}: bad detect regex {rx!r}: {e}", file=sys.stderr)
        cause = next((fields[k] for k in CAUSE_KEYS if k in fields), "")
        rule = next((fields[k] for k in RULE_KEYS if k in fields), "")
        out.append({"id": m.group(1), "title": m.group(2).strip(), "cause": cause, "rule": rule,
                    "globs": dglobs, "detect": detect, "_rx": compiled, "_grx": [glob_regex(g) for g in dglobs]})
    return out


def entries(repo):
    try:
        with open(registry_path(repo), encoding="utf-8") as fh:
            return parse(fh.read())
    except OSError:
        return []


def covers(entry, path):
    return not entry["_grx"] or any(g.match(path) for g in entry["_grx"])


def match_finding(ents, finding):
    """(entry id, how) when a review finding is a known pattern: it names the id, or its snippet hits a detect regex in a
    covered file. None otherwise."""
    text = " ".join(str(finding.get(k) or "") for k in ("known_pattern", "problem", "category"))
    named = set(ID_IN_TEXT.findall(text))
    for e in ents:
        if e["id"] in named:
            return e["id"], "named"
    snip = str(finding.get("snippet") or "")
    path = str(finding.get("file") or "")
    if snip and path:
        for e in ents:
            if e["_rx"] and covers(e, path) and any(rx.search(snip) for rx in e["_rx"]):
                return e["id"], "detect"
    return None


def _clip(s, n):
    s = " ".join(str(s or "").split())
    return s if len(s) <= n else s[: n - 1] + "…"


def context(ents, files=None, max_n=60):
    files = files or []
    picked = [e for e in ents if not files or not e["_grx"] or any(covers(e, f) for f in files)]
    lines = ["## Known bug patterns of this repo (.agents/instincts.md) — a change that repeats one is a P0 recurring bug",
             "Tag such a finding with \"known_pattern\": \"<INSTINCT-id>\"."]
    for e in picked[:max_n]:
        lines.append(f"- {e['id']}: {_clip(e['title'], 140)} — rule: {_clip(e['rule'], 220)}"
                     + (f" — detect: {', '.join(e['detect'])}" if e["detect"] else ""))
    if len(picked) > max_n:
        lines.append(f"- … +{len(picked) - max_n} more in .agents/instincts.md")
    return "\n".join(lines) + "\n"


def _git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, timeout=60)


def added_lines(repo, base):
    """[(path, line_no, text)] of lines the change adds: `git diff -U0 base` (committed since base + uncommitted) and whole
    untracked files."""
    out = []
    r = _git(repo, "diff", "-U0", "--no-color", "--no-ext-diff", base, "--")
    if r.returncode != 0:
        raise RuntimeError(f"git diff {base} failed: {r.stderr.strip()[:300]}")
    path, ln = None, 0
    for line in r.stdout.splitlines():
        if line.startswith("+++ "):
            path = None if line[4:] == "/dev/null" else line[4:][2:] if line[4:].startswith("b/") else line[4:]
        elif line.startswith("@@"):
            m = re.search(r"\+(\d+)", line)
            ln = int(m.group(1)) if m else 0
        elif line.startswith("+") and path is not None:
            out.append((path, ln, line[1:]))
            ln += 1
    u = _git(repo, "ls-files", "--others", "--exclude-standard", "-z")
    for p in [x for x in u.stdout.split("\0") if x]:
        fp = os.path.join(repo, p)
        if os.path.islink(fp) or not os.path.isfile(fp) or os.path.getsize(fp) > 2_000_000:
            continue
        try:
            with open(fp, encoding="utf-8") as fh:
                for i, t in enumerate(fh, 1):
                    out.append((p, i, t.rstrip("\n")))
        except (OSError, UnicodeDecodeError):
            continue
    return out


def scan(repo, base, ents=None):
    ents = entries(repo) if ents is None else ents
    active = [e for e in ents if e["_rx"]]
    hits = []
    if active:
        for path, ln, text in added_lines(repo, base):
            for e in active:
                if covers(e, path) and any(rx.search(text) for rx in e["_rx"]):
                    hits.append({"severity": "P0", "category": "recurring-bug", "file": path, "line": ln, "end_line": ln,
                                 "snippet": text.strip()[:300], "known_pattern": e["id"], "deterministic": True,
                                 "problem": f"repeats known bug {e['id']}: {_clip(e['title'], 160)}",
                                 "why": _clip(e["cause"], 300), "fix": _clip(e["rule"], 300)})
    return {"reviewer": "registry", "status": "ok", "verdict": "fail" if hits else "pass", "findings": hits,
            "reason": f"{len(hits)} added line(s) match a known bug pattern" if hits else "",
            "patterns_checked": len(active), "usage": {"tokens": 0, "usd": 0.0}}


def semgrep_yaml(ents):
    rules = []
    for e in ents:
        for k, rx in enumerate(e["detect"]):
            rid = re.sub(r"[^a-z0-9-]", "-", e["id"].lower()) + (f"-{k + 1}" if len(e["detect"]) > 1 else "")
            r = [f"  - id: {rid}", f"    message: {json.dumps('Recurring bug ' + e['id'] + ': ' + _clip(e['title'], 160) + ' — ' + _clip(e['rule'], 200), ensure_ascii=False)}",
                 "    severity: ERROR", "    languages: [generic]", f"    pattern-regex: {json.dumps(rx, ensure_ascii=False)}"]
            if e["globs"]:
                r += ["    paths:", "      include:"] + [f"        - {json.dumps(g if '/' in g else '**/' + g)}" for g in e["globs"]]
            rules.append("\n".join(r))
    return "# generated by universal-agent-devkit/bin/known_patterns.py semgrep from .agents/instincts.md — do not edit\nrules:\n" \
        + ("\n".join(rules) if rules else "  []") + "\n"


def _public(e):
    return {k: v for k, v in e.items() if not k.startswith("_")}


def main(argv=None):
    ap = argparse.ArgumentParser(prog="known_patterns.py")
    ap.add_argument("--repo", default=None)
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("context"); c.add_argument("--files", nargs="*", default=[]); c.add_argument("--max", type=int, default=60)
    s = sub.add_parser("scan"); s.add_argument("--base", required=True); s.add_argument("--out")
    g = sub.add_parser("semgrep"); g.add_argument("--out", required=True)
    sub.add_parser("list")
    a = ap.parse_args(argv)
    repo = a.repo or subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or os.getcwd()
    ents = entries(repo)
    try:
        if a.cmd == "context":
            sys.stdout.write(context(ents, a.files, a.max))
            return 0
        if a.cmd == "list":
            print(json.dumps([_public(e) for e in ents], ensure_ascii=False, indent=1))
            return 0
        if a.cmd == "semgrep":
            with open(a.out, "w", encoding="utf-8") as fh:
                fh.write(semgrep_yaml(ents))
            print(f"{a.out}: {sum(len(e['detect']) for e in ents)} rule(s)")
            return 0
        env = scan(repo, a.base, ents)
        text = json.dumps(env, ensure_ascii=False, indent=1)
        if a.out:
            with open(a.out, "w", encoding="utf-8") as fh:
                fh.write(text + "\n")
        else:
            print(text)
        return 1 if env["findings"] else 0
    except (OSError, RuntimeError, subprocess.SubprocessError) as e:
        print(f"known_patterns: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
