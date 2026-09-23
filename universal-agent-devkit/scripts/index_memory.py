#!/usr/bin/env python3
"""
index_memory.py — 2-Tier Memory Indexing Generator (Geely EX2 Architecture)
Parses massive knowledge/bug files, generates a lightweight index (< 20KB),
and outputs exact line ranges with `sed -n 'a,bp'` on-demand slicing commands.
Prevents Context Window Bloat and reasoning degradation.
"""

import sys
import os
import re
import subprocess
import tempfile
from pathlib import Path

INDEX_BUDGET = 20 * 1024  # bytes — the index is loaded whole at session start


def project_path(p: Path) -> str:
    """The path of p as typed from the project root, so the index's `sed -n` commands
    work where the agent runs them: `.agents/instincts.md`, not `instincts.md`.
    The root is the folder holding `.agents/`, else the git top level, else the cwd."""
    ap = Path(os.path.abspath(p))
    if ".agents" in ap.parts[:-1]:
        i = len(ap.parts) - 1 - ap.parts[:-1][::-1].index(".agents") - 1
        return str(Path(*ap.parts[i:]))
    try:
        res = subprocess.run(["git", "-C", str(ap.parent), "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, timeout=5)
        root = res.stdout.strip() if res.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        root = ""
    for base in (root, os.getcwd()):
        if base:
            rel = os.path.relpath(os.path.realpath(ap), os.path.realpath(base))
            if not rel.startswith(".."):
                return rel
    return str(ap)


def shorten(title: str, limit: int) -> str:
    """title cut at a word boundary to at most limit characters."""
    if len(title) <= limit:
        return title
    cut = title[:limit - 1].rsplit(" ", 1)[0].rstrip(" ,;:—-/(")
    return (cut or title[:limit - 1]) + "…"


def generate_memory_index(file_path: str):
    p = Path(file_path)
    if not p.exists():
        print(f"❌ File not found: {file_path}")
        return 1

    with open(p, "r", encoding="utf-8", errors="replace") as f:
        text = f.read()
    # Headings inside HTML comments (the [INSTINCT-XXX] template) or code fences are not
    # entries; blank them out line for line so the line numbers stay right.
    text = re.sub(r"<!--.*?-->", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.DOTALL)
    text = re.sub(r"^(```|~~~).*?^\1[^\n]*$", lambda m: "\n" * m.group(0).count("\n"), text,
                  flags=re.DOTALL | re.MULTILINE)
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()

    total_lines = len(lines)
    file_size_kb = p.stat().st_size / 1024

    sections = []
    header_pattern = re.compile(r"^(#{1,3})\s+(.*)")

    current_title = "Giới thiệu"
    current_start = 1
    current_level = 1

    for idx, line in enumerate(lines, start=1):
        m = header_pattern.match(line.strip())
        if m:
            level = len(m.group(1))
            title = m.group(2).strip()
            if idx > current_start:
                sections.append((current_title, current_start, idx - 1, current_level))
            current_title = title
            current_start = idx
            current_level = level

    if current_start <= total_lines:
        sections.append((current_title, current_start, total_lines, current_level))

    out_path = p.parent / f"{p.stem}-index.md"
    src = project_path(p)

    def render(limit):
        out_lines = [
            f"# 📑 Mục Lục Bộ Nhớ 2 Tầng: {src}",
            f"> **Tệp gốc:** `{src}` ({total_lines} dòng, {file_size_kb:.1f} KB) · {len(sections)} mục",
            "> **Quy tắc đọc:** KHÔNG nạp toàn bộ file gốc. Tìm mục cần thiết bên dưới rồi chạy đúng "
            "lệnh `sed -n` của mục đó từ thư mục gốc dự án.",
            "",
        ]
        # One line per section: the range and the command in one, the title shortened.
        for title, s_line, e_line, lvl in sections:
            out_lines.append(f"- {shorten(title, limit)} — `sed -n '{s_line},{e_line}p' {src}`")
        out_lines.append("")
        return "\n".join(out_lines) + "\n"

    # Shorter titles until the whole index fits the budget; every section stays listed.
    for limit in (120, 100, 90, 80, 70, 60, 50, 40, 30):
        content = render(limit)
        if len(content.encode("utf-8")) <= INDEX_BUDGET:
            break
    else:
        print(f"warning: {len(sections)} mục — mục lục vượt {INDEX_BUDGET // 1024} KB dù đã rút gọn tiêu đề",
              file=sys.stderr)

    # Atomic: a temp file next to the index, moved into place (keeps the old file's mode).
    fd, tmp = tempfile.mkstemp(prefix=f".{out_path.name}.", dir=str(out_path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.chmod(tmp, (out_path.stat().st_mode & 0o7777) if out_path.exists() else 0o644)
        os.replace(tmp, out_path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise

    out_size_kb = out_path.stat().st_size / 1024
    print(f"✔ Đã tạo mục lục bộ nhớ 2 tầng tại: {out_path} ({out_size_kb:.1f} KB, {len(sections)} mục)")
    return 0

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: index_memory.py <path_to_markdown_file>")
        sys.exit(1)
    sys.exit(generate_memory_index(sys.argv[1]))
