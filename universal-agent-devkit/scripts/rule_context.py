#!/usr/bin/env python3
"""rule_context.py — the project-rule sections that match a prompt (UserPromptSubmit).

Reads the hook payload ({"prompt": …}) on stdin and .agents/context/rules-index.md of
$CLAUDE_PROJECT_DIR (one line per section of .agents/local/rules/, with its `sed -n`
range). Prints at most MAX_HITS sections whose title shares at least MIN_HITS distinct
words with the prompt (accents folded, so "man hinh" matches "màn hình"; a word of 4+
letters also matches as a prefix: "crash" → "Crashlytics"), with the
command that opens each. Silent for slash commands, short prompts and no match.
Exit 0 always. Escape hatch: RULE_CONTEXT=0.
"""
import json
import os
import re
import sys
import unicodedata

MAX_HITS = 3
MIN_HITS = 2
STOP = set("""the and for with that this from into when then than have has are was were not you your can
will should would could what which where how why all any use using make made need does done also only
va la cua cho cac mot nhung duoc khong trong khi thi neu de co voi nay do tu bi den nhu hay phai lam
roi da dang se sau truoc ra vao len xuong gi nao toi ban minh anh em no""".split())


def fold(text):
    text = unicodedata.normalize("NFD", text.lower()).replace("đ", "d")
    return "".join(c for c in text if unicodedata.category(c) != "Mn")


def words(text):
    return {w for w in re.findall(r"[a-z0-9_]{3,}", fold(text)) if w not in STOP}


def main():
    if os.environ.get("RULE_CONTEXT") == "0":
        return 0
    try:
        prompt = json.loads(sys.stdin.read() or "{}").get("prompt") or ""
    except ValueError:
        return 0
    if len(prompt.strip()) < 8 or prompt.lstrip().startswith("/"):
        return 0
    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    try:
        lines = open(os.path.join(root, ".agents", "context", "rules-index.md"), encoding="utf-8").read().splitlines()
    except OSError:
        return 0
    want = words(prompt)
    if not want:
        return 0
    scored = []
    for line in lines:
        m = re.match(r"\s*- (.+?) — (`sed -n '\d+,\d+p' [^`]+`)\s*$", line)
        if not m:
            continue
        title = words(m.group(1))
        hits = {t for t in want if t in title or (len(t) >= 4 and any(u.startswith(t) for u in title))}
        if len(hits) >= MIN_HITS or any(len(t) >= 8 for t in hits):   # one long term is specific enough
            scored.append((len(hits), -len(m.group(1)), m.group(1), m.group(2)))
    if not scored:
        return 0
    scored.sort(reverse=True)
    print("[DevKit] Luật dự án khớp yêu cầu — mở đúng mục trước khi sửa vùng này:")
    for _, _, title, cmd in scored[:MAX_HITS]:
        print(f"  - {title[:140]} — {cmd}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
