#!/usr/bin/env python3
"""fold_agent_file.py <agent file> <AGENTS.md> — move one agent's instruction file into AGENTS.md.

AGENTS.md is the only instruction file of a DevKit project: Claude Code reads it when
there is no CLAUDE.md, and Gemini CLI reads it through `context.fileName`. The project's
own text in CLAUDE.md / GEMINI.md / Agent.md (everything outside the DevKit block) is
kept verbatim and placed in AGENTS.md above the DevKit block, under a one-line marker
naming where it came from. Text already present in AGENTS.md is not added twice.
The caller backs the original up (<name>_old.md) and removes it.

Prints "moved N lines" or "nothing to move"; exit 1 only on an I/O error.
"""
import datetime
import os
import re
import sys
import tempfile

START, END = "<!-- universal-agent-devkit:start -->", "<!-- universal-agent-devkit:end -->"


def strip_block(text):
    return re.sub(re.escape(START) + r".*?" + re.escape(END) + r"\n?", "", text, flags=re.S)


def norm(text):
    return re.sub(r"\s+", " ", text).strip()


def main(src, agents):
    try:
        own = strip_block(open(src, encoding="utf-8").read()).strip("\n")
        target = open(agents, encoding="utf-8").read() if os.path.exists(agents) else ""
    except (OSError, UnicodeDecodeError) as e:
        print(f"cannot read: {e}", file=sys.stderr)
        return 1
    if not norm(own) or norm(own) in norm(strip_block(target)):
        print("nothing to move")
        return 0
    stamp = datetime.date.today().isoformat()
    piece = f"<!-- moved from {os.path.basename(src)} on {stamp} (AGENTS.md is the only instruction file) -->\n{own}\n\n"
    at = target.find(START)
    if at < 0:
        new = (target.rstrip("\n") + "\n\n" if target.strip() else "") + piece
    else:
        new = target[:at] + piece + target[at:]
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(agents)), prefix=".fold.")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(new)
    os.chmod(tmp, os.stat(agents).st_mode & 0o7777 if os.path.exists(agents) else 0o644)
    os.replace(tmp, agents)
    print(f"moved {own.count(chr(10)) + 1} lines")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
