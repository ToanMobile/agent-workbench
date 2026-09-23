#!/usr/bin/env python3
"""
instincts.py — add a lesson to the project's failure memory (.agents/instincts.md).

Usage (via `agent-kit learn`):
  instincts.py add "<trap title>" [--cause TEXT] [--rule TEXT] [--symptom TEXT]
                   [--check CMD] [--file PATH] [--force] [--dry-run] [-l en|vi]

  - the entry gets the next free id `[INSTINCT-NNN]` (highest 3-digit id + 1; the
    named families like INSTINCT-V01 / INSTINCT-BE-01 are left alone)
  - a title already recorded (case / whitespace / escaping ignored) is refused with
    exit 1 and the existing id, unless --force
  - user text is escaped to one Markdown line, so it cannot add headings or links
  - target: --file, else <project>/.agents/instincts.md where project =
    $CLAUDE_PROJECT_DIR → git toplevel → cwd; a missing file is created from
    templates/instincts.template.md (what the installer does)

post-fix-gate.py --record-lesson writes through append_lesson() below, so both paths
produce the same ids and format.

Exit codes: 0 added (or --dry-run), 1 duplicate title, 2 usage / file error.
100% Standard Library.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

DEVKIT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(DEVKIT_ROOT / "scripts"))
from devkit_i18n import resolve_lang, set_lang, tr  # noqa: E402

try:
    import fcntl
except ImportError:  # Windows: no advisory lock, appends are still whole-entry writes
    fcntl = None

NUMBERED_ID = re.compile(r"^### \[INSTINCT-(\d{3,})\]", re.MULTILINE)
HEADING = re.compile(r"^### \[(INSTINCT-[A-Za-z0-9_-]+)\][ \t]*(.*)$", re.MULTILINE)


def md_escape(text) -> str:
    """One line, Markdown control characters escaped — user text must not add headings,
    list items or links to instincts.md / the report."""
    text = " ".join(str(text or "").split())
    return re.sub(r"([\\`*_\[\]#<>|!])", r"\\\1", text)


def _norm_title(title: str) -> str:
    return " ".join(title.replace("\\", "").split()).casefold()


def next_id(text: str) -> str:
    numbers = [int(n) for n in NUMBERED_ID.findall(text)]
    return f"INSTINCT-{max(numbers, default=0) + 1:03d}"


def find_duplicate(text: str, title: str):
    """Id of an entry whose heading title equals `title`, else None."""
    want = _norm_title(md_escape(title))
    for inst_id, existing in HEADING.findall(text):
        if _norm_title(existing) == want:
            return inst_id
    return None


def format_entry(inst_id, title, cause=None, rule=None, symptom=None, check=None, today=None) -> str:
    none = tr("Chưa ghi", "Not recorded")
    lines = [
        f"### [{inst_id}] {md_escape(title)}",
        f"- **{tr('Ngày phát hiện', 'Found on')}:** {today or time.strftime('%Y-%m-%d')}",
        f"- **{tr('Hiện tượng lỗi', 'Symptom')}:** {md_escape(symptom or title)}",
        f"- **{tr('Nguyên nhân', 'Cause')}:** {md_escape(cause) if cause else none}",
        f"- **{tr('Quy tắc phòng ngừa & Cách fix', 'Prevention & fix')}:** {md_escape(rule) if rule else none}",
    ]
    if check:
        lines.append(f"- **{tr('Lệnh kiểm tra', 'Check')}:** {md_escape(check)}")
    return "\n".join(lines) + "\n"


def append_lesson(path: Path, title, cause=None, rule=None, symptom=None, check=None,
                  force=False, dry_run=False):
    """Returns (status, inst_id, entry): status is "added", "dry-run" or "duplicate"
    (inst_id is then the existing entry). Raises OSError / ValueError."""
    if not md_escape(title):
        raise ValueError(tr("tiêu đề bài học rỗng", "the lesson title is empty"))
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a+", encoding="utf-8") as f:
        if fcntl is not None:
            fcntl.flock(f, fcntl.LOCK_EX)  # id read + append are one step for concurrent writers
        f.seek(0)
        text = f.read()
        dup = find_duplicate(text, title)
        if dup and not force:
            return "duplicate", dup, None
        inst_id = next_id(text)
        entry = format_entry(inst_id, title, cause, rule, symptom, check)
        if dry_run:
            return "dry-run", inst_id, entry
        lead = "" if not text or text.endswith("\n") else "\n"
        f.write(f"{lead}\n---\n\n{entry}")
    return "added", inst_id, entry


def project_dir() -> Path:
    env = os.environ.get("CLAUDE_PROJECT_DIR")
    if env and Path(env).is_dir():
        return Path(env).resolve()
    res = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if res.returncode == 0 and res.stdout.strip():
        return Path(res.stdout.strip()).resolve()
    return Path.cwd().resolve()


def resolve_target(file_arg, project: Path) -> Path:
    """The file to write. Refuses a link into the DevKit from another project: the
    lesson would land in the shared DevKit memory instead of this project's."""
    target = Path(file_arg) if file_arg else project / ".agents" / "instincts.md"
    if target.is_symlink() and project != DEVKIT_ROOT and DEVKIT_ROOT in target.resolve().parents:
        raise ValueError(tr(f"{target} là link vào DevKit — bài học sẽ ghi vào DevKit dùng chung, không ghi. Thay link bằng file thật.",
                            f"{target} links into the DevKit — the lesson would go to the shared DevKit, refused. Replace the link with a real file."))
    return target


def cmd_add(args) -> int:
    project = project_dir()
    try:
        target = resolve_target(args.file, project)
    except ValueError as e:
        print(f"✖ {e}", file=sys.stderr)
        return 2
    created = False
    if not target.exists() and not args.dry_run:
        template = DEVKIT_ROOT / "templates" / "instincts.template.md"
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            if template.is_file():
                shutil.copyfile(template, target)
                created = True
        except OSError as e:
            print(f"✖ {tr('Không tạo được', 'Cannot create')} {target}: {e}", file=sys.stderr)
            return 2
    try:
        status, inst_id, entry = append_lesson(
            target, args.title, cause=args.cause, rule=args.rule, symptom=args.symptom,
            check=args.check, force=args.force, dry_run=args.dry_run)
    except (OSError, ValueError) as e:
        print(f"✖ {e}", file=sys.stderr)
        return 2
    if status == "duplicate":
        print(f"✖ {tr('Bài học này đã có', 'This lesson already exists')}: [{inst_id}] "
              f"{tr('trong', 'in')} {target} {tr('(--force để vẫn thêm)', '(--force to add anyway)')}", file=sys.stderr)
        return 1
    if created:
        print(f"• {tr('Đã tạo', 'Created')} {target} {tr('từ template', 'from the template')}")
    if status == "dry-run":
        print(f"{tr('(dry-run) Sẽ thêm vào', '(dry-run) Would add to')} {target}:\n\n{entry}")
    else:
        print(f"✔ {tr('Đã ghi', 'Recorded')} [{inst_id}] {tr('vào', 'in')} {target}")
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="agent-kit learn",
                                     description="Record a lesson / code trap in .agents/instincts.md")
    sub = parser.add_subparsers(dest="cmd", required=True)
    add = sub.add_parser("add", help="add a lesson")
    add.add_argument("title", help="trap / lesson title")
    add.add_argument("--cause", help="root cause")
    add.add_argument("--rule", "--prevention", dest="rule", help="prevention rule / how to fix")
    add.add_argument("--symptom", help="observed symptom (default: the title)")
    add.add_argument("--check", help="command that detects the trap")
    add.add_argument("--file", help="instincts file (default: <project>/.agents/instincts.md)")
    add.add_argument("--force", action="store_true", help="add even if the title is already recorded")
    add.add_argument("--dry-run", action="store_true", help="print the entry, write nothing")
    add.add_argument("-l", "--lang", choices=["en", "vi"], help="output language")
    args = parser.parse_args(argv)
    set_lang(resolve_lang(args.lang, project_dir()))
    return cmd_add(args)


if __name__ == "__main__":
    sys.exit(main())
