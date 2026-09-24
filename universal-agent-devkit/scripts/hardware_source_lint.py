#!/usr/bin/env python3
"""Blocking patterns for hardware-safety calls written in source, not only in a shell.

Matches the command text, so ProcessBuilder("echo") and a socket to any other port
are left alone. The gate applies these to lines the change introduced.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Each pattern is one line (no DOTALL): a dangerous call and its argument together.
PATTERNS = [
    (re.compile(r"""Runtime\.getRuntime\(\)\.exec\s*\(\s*(?:new\s+String\s*\[\s*\]\s*\{|arrayOf\s*\(|listOf\s*\(|)["'][^"']*\b(?:mount|su|reboot)\b"""),
     ("Lệnh hệ thống nguy hiểm qua Runtime.exec (mount/su/reboot)",
      "Dangerous Runtime.exec (mount/su/reboot)")),
    (re.compile(r"""ProcessBuilder\s*\(\s*(?:listOf|arrayOf|mutableListOf|arrayListOf)?\s*\(?\s*["'](?:su|reboot|mount)["']"""),
     ("ProcessBuilder gọi su/reboot/mount", "ProcessBuilder invokes su/reboot/mount")),
    (re.compile(r"""(?:new\s+Socket|InetSocketAddress|ServerSocket)\s*\([^)\n]{0,120}\b5555\b"""),
     ("Socket thô tới cổng 5555 (adb daemon)", "Raw socket to port 5555 (adb daemon)")),
    (re.compile(r"""subprocess\.(?:run|Popen|call|check_call|check_output)\s*\([^)\n]{0,180}\b(?:su|reboot|mount)\b"""),
     ("subprocess gọi su/reboot/mount", "subprocess invokes su/reboot/mount")),
    (re.compile(r"""socket\.(?:create_connection|connect)\s*\([^)\n]{0,80}\b5555\b"""),
     ("socket Python tới cổng 5555", "Python socket to port 5555")),
    (re.compile(r"""CarPropertyManager.{0,180}setAccessible\s*\(\s*true\s*\)|setAccessible\s*\(\s*true\s*\).{0,180}CarPropertyManager"""),
     ("Reflection né CarPropertyManager", "Reflection bypasses CarPropertyManager")),
]


def findings(text: str) -> list:
    """[(pattern_index, match)] for every dangerous call in text."""
    out = []
    for i, (pat, _label) in enumerate(PATTERNS):
        for m in pat.finditer(text):
            out.append((i, m))
    return out


def main(argv: list) -> int:
    if len(argv) < 2:
        print("usage: hardware_source_lint.py <file>...", file=sys.stderr)
        return 2
    bad = 0
    for raw in argv[1:]:
        path = Path(raw)
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as e:
            print(f"{raw}: {e}", file=sys.stderr)
            return 2
        for i, m in findings(text):
            bad += 1
            line = text.count("\n", 0, m.start()) + 1
            print(f"{raw}:{line}: {PATTERNS[i][1][0]}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
