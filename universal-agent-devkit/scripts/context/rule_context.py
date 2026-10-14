#!/usr/bin/env python3
"""rule_context.py — the project-rule sections that match a prompt (UserPromptSubmit).

Also names the matching `## title` sections of .agents/context/profile-reference.md (the profile rules that
context_sync.py keeps out of the startup context; see profile_hits). Each of the two files is optional.

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
PROFILE_HITS = 2
MIN_HITS = 2
REFERENCE = "profile-reference.md"
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
    want = words(prompt)
    if not want:
        return 0
    # Each source is optional: a project with no rules-index.md still gets the profile sections, and the reverse.
    scored = project_hits(read_lines(root, "rules-index.md"), want)
    if scored:
        scored.sort(reverse=True)
        print("[DevKit] Luật dự án khớp yêu cầu — mở đúng mục trước khi sửa vùng này:")
        for _, _, title, cmd in scored[:MAX_HITS]:
            print(f"  - {title[:140]} — {cmd}")
    scored = profile_hits(read_lines(root, REFERENCE), want)
    if scored:
        scored.sort(reverse=True)
        print("[DevKit] Luật profile (nạp theo yêu cầu) khớp yêu cầu — mở đúng mục trước khi sửa vùng này:")
        for _, _, title, cmd in scored[:PROFILE_HITS]:
            print(f"  - {title[:140]} — {cmd}")
    return 0


def read_lines(root, name):
    try:
        with open(os.path.join(root, ".agents", "context", name), encoding="utf-8") as f:
            return f.read().splitlines()
    except OSError:
        return []


def hit_words(want, pool):
    return {t for t in want if t in pool or (len(t) >= 4 and any(u.startswith(t) for u in pool))}


def profile_hits(lines, want):
    """Sections `## title` of profile-reference.md (context_sync.py) that match the prompt: two title words, one
    long title word, or one exact title word plus two more words of the section body. [(score, -len, title, sed cmd)]."""
    heads = [i for i, l in enumerate(lines) if l.startswith("## ")]
    scored = []
    for n, i in enumerate(heads):
        end = heads[n + 1] if n + 1 < len(heads) else len(lines)
        while end > i + 1 and not lines[end - 1].strip():
            end -= 1
        title = lines[i][3:].strip()
        head = words(title)
        h = hit_words(want, head)
        b = hit_words(want - h, words(" ".join(lines[i + 1:end]))) if h else set()
        # The body path needs an EXACT title word: a 4-letter prefix ("crash" -> Crashlytics) plus common body words is noise.
        if len(h) >= MIN_HITS or any(len(t) >= 8 for t in h) or (h & head and len(b) >= MIN_HITS):
            scored.append((2 * len(h) + len(b), -len(title), title,
                           f"`sed -n '{i + 1},{end}p' .agents/context/{REFERENCE}`"))
    return scored


def project_hits(lines, want):
    scored, current = [], None
    for line in lines:
        h = re.match(r"## (?:.+? — )?`([^`]+)`\s*$", line)
        if h:
            current = h.group(1)
            continue
        # `- title La-b` / `- title La` under the `## \`path\`` heading (compact, 13/10), `- title — L a–b` (O5, an index
        # not re-synced yet), or the older `- title — \`sed -n …\``.
        m = re.match(r"\s*- (.+?) — L(\d+)[–-](\d+)\s*$", line) or re.match(r"\s*- (.+?) L(\d+)(?:-(\d+))?\s*$", line)
        if m and current:
            cmd = f"`sed -n '{m.group(2)},{m.group(3) or m.group(2)}p' {current}`"
        else:
            m = re.match(r"\s*- (.+?) — (`sed -n '\d+,\d+p' [^`]+`)\s*$", line)
            if not m:
                continue
            cmd = m.group(2)
        hits = hit_words(want, words(m.group(1)))
        if len(hits) >= MIN_HITS or any(len(t) >= 8 for t in hits):   # one long term is specific enough
            scored.append((len(hits), -len(m.group(1)), m.group(1), cmd))
    return scored


if __name__ == "__main__":
    sys.exit(main())
