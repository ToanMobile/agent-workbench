#!/usr/bin/env python3
"""super-board-root-cause-hash.py — deterministic root-cause hash for the rebuild-cap gate (#982).

Spec: .claude/skills/super-board/references/run.md → "Root-cause hash".

  hash --lane <build|qa|review>   stdin = failure text → 12 hex chars
         sha256(lane | error class | first 3 unique normalized file:line frames)
  last                            stdin = `gh issue view --json comments` JSON → the newest
                                  `root-cause-hash: <12 hex>` value in the comments ("" if none)

Exit 0 always for well-formed input; bad JSON on `last` prints "" (no hash known, caller keeps the
plain loop:rebuild-N count).
"""
import hashlib
import json
import re
import sys

# First match wins (order = the run.md list).
CLASSES = [
    ("test_assertion", r"AssertionError|assert(ion)? (failed|error)|expected .* (got|but)|✖ "),
    ("test_runtime", r"Traceback \(most recent|Exception|panic:|segfault|Segmentation fault"),
    ("build_fail", r"build failed|compilation (error|failed)|SyntaxError|cannot find symbol|BUILD FAILED"),
    ("lint_fail", r"\blint\b|ktlint|eslint|shellcheck|flake8|ruff"),
    ("merge_conflict", r"CONFLICT|conflicting|merge conflict|gate-exit-(2|5|14)"),
    ("network", r"timed? ?out|connection (refused|reset)|ECONN|rc=128|publickey"),
    ("auth", r"\b40[13]\b|unauthori[sz]ed|permission denied|token"),
    ("quota", r"\b429\b|rate limit|quota"),
]
FRAME = re.compile(r"(?<![\w/.-])((?:/[\w.@+-]+)*/?(?:[\w.@+-]+/)*[\w.@+-]+\.[A-Za-z0-9]{1,5}):(\d+)")
ABS_PREFIX = re.compile(r"^(?:/[^/\s]+)+?/(?=(?:\.claude|\.agents|tests?|src|lib|bin|scripts|universal-agent-devkit)/)")
HASH_LINE = re.compile(r"^root-cause-hash:\s*([0-9a-f]{12})\s*$", re.M)


def error_class(text: str) -> str:
    for name, pat in CLASSES:
        if re.search(pat, text, re.I if name in ("network", "auth", "quota", "lint_fail") else 0):
            return name
    return "other"


def frames(text: str) -> list[str]:
    seen: list[str] = []
    for m in FRAME.finditer(text):
        f = f"{ABS_PREFIX.sub('', m.group(1)).lstrip('./')}:{m.group(2)}"
        if f not in seen:
            seen.append(f)
    return sorted(seen[:3])


def make_hash(lane: str, text: str) -> str:
    raw = "|".join([lane, error_class(text), *frames(text)])
    return hashlib.sha256(raw.encode()).hexdigest()[:12]


def last_hash(payload: str) -> str:
    try:
        comments = json.loads(payload).get("comments") or []
    except (ValueError, AttributeError):
        return ""
    for c in reversed(comments):
        found = HASH_LINE.findall((c or {}).get("body") or "")
        if found:
            return found[-1]
    return ""


def main(argv: list[str]) -> int:
    if len(argv) >= 2 and argv[1] == "hash":
        lane = argv[argv.index("--lane") + 1] if "--lane" in argv else "review"
        print(make_hash(lane, sys.stdin.read()))
        return 0
    if len(argv) >= 2 and argv[1] == "last":
        print(last_hash(sys.stdin.read()))
        return 0
    print(f"usage: {argv[0]} hash --lane <lane> | last", file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv))
