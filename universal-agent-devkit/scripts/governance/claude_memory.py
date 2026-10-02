#!/usr/bin/env python3
"""claude_memory.py <project> [--check] — Claude Code's auto-memory lives in the project.

Claude Code keeps its auto-memory per user in ~/.claude/projects/<slug>/memory/, out of
the repo and invisible to other agents. `autoMemoryDirectory` (read from
.claude/settings.local.json — personal, never committed) points it at
.agents/local/memory/claude-auto/ instead, next to the rest of the project's memory:

  * sets autoMemoryDirectory (absolute path; a custom value of the user's is kept);
  * moves the files of the old per-user folder in (a same-named file with other content
    is kept as <name>.from-user-memory.md) and renames that folder memory.moved-to-project;
  * MEMORY.md — the index Claude loads at every session start — gets one line for each
    note it does not list yet.

--check: exit 1 when autoMemoryDirectory does not point into the project.
"""
import json
import os
import re
import shutil
import sys

REL = os.path.join(".agents", "local", "memory", "claude-auto")
HEADER = """# Memory index (Claude Code auto-memory — kept in the repo by Universal Agent DevKit)

One line per note in this folder; open a note before relying on it and check its facts
against the current code. Traps from past bugs are in `.agents/instincts.md`.

"""


def slug(project):
    return re.sub(r"[^A-Za-z0-9]", "-", project)


def note_line(path):
    name = os.path.basename(path)
    desc = ""
    try:
        head = open(path, encoding="utf-8", errors="replace").read(1500)
        m = re.search(r"^description:\s*(.+)$", head, re.M)
        if m:
            desc = m.group(1).strip().strip("\"'")
        else:
            m = re.search(r"^#\s+(.+)$", head, re.M)
            desc = m.group(1).strip() if m else ""
    except OSError:
        pass
    desc = desc[:140] + ("…" if len(desc) > 140 else "")
    return f"- [{name[:-3]}]({name})" + (f" — {desc}" if desc else "")


def settings_dir(project):
    try:
        return json.load(open(os.path.join(project, ".claude", "settings.local.json"), encoding="utf-8")).get("autoMemoryDirectory")
    except (OSError, ValueError, AttributeError):
        return None


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("-")]
    project = os.path.realpath(args[0] if args else os.getcwd())
    target = os.path.join(project, REL)
    current = settings_dir(project)
    if "--check" in argv:
        return 0 if current and os.path.realpath(current).startswith(project + os.sep) else 1
    if current and os.path.realpath(current) != os.path.realpath(target):
        print(f"  - autoMemoryDirectory: {current} (yours) — kept")
        return 0
    # 1. settings.local.json (the folder itself appears with the first note: Claude Code
    #    creates it when it saves one, the move below when there are notes to move)
    local = os.path.join(project, ".claude", "settings.local.json")
    if current is None:
        try:
            data = json.load(open(local, encoding="utf-8"))
        except (OSError, ValueError):
            data = {}
        data["autoMemoryDirectory"] = target
        os.makedirs(os.path.dirname(local), exist_ok=True)
        tmp = local + ".devkit-tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        os.replace(tmp, local)
        print(f"  - Claude auto-memory → {REL}/ (.claude/settings.local.json autoMemoryDirectory)")
    # 2. the old per-user folder
    old = os.path.join(os.path.expanduser("~"), ".claude", "projects", slug(project), "memory")
    moved = 0
    if os.path.isdir(old) and not os.path.islink(old):
        os.makedirs(target, exist_ok=True)
        for name in sorted(os.listdir(old)):
            src = os.path.join(old, name)
            if not os.path.isfile(src):
                continue
            dst = os.path.join(target, name)
            if name == "MEMORY.md":
                continue                # rebuilt below from the notes themselves
            if os.path.exists(dst):
                if open(src, "rb").read() == open(dst, "rb").read():
                    continue
                dst = os.path.join(target, name[:-3] + ".from-user-memory.md") if name.endswith(".md") else dst + ".from-user-memory"
            shutil.copy2(src, dst)
            moved += 1
        gone = old + ".moved-to-project"
        n = 1
        while os.path.exists(gone):
            n += 1
            gone = f"{old}.moved-to-project.{n}"
        os.rename(old, gone)
        print(f"  - Claude auto-memory: {moved} note(s) moved in from {old} (old folder kept as {os.path.basename(gone)})")
    # 3. MEMORY.md lists every note
    if not os.path.isdir(target):
        return 0
    index = os.path.join(target, "MEMORY.md")
    text = open(index, encoding="utf-8").read() if os.path.isfile(index) else HEADER
    notes = sorted(n for n in os.listdir(target) if n.endswith(".md") and n not in ("MEMORY.md", "README.md"))
    missing = [n for n in notes if f"({n})" not in text]
    if missing or (notes and not os.path.isfile(index)):
        text = text.rstrip("\n") + "\n" + "".join(note_line(os.path.join(target, n)) + "\n" for n in missing)
        with open(index + ".tmp", "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(index + ".tmp", index)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
