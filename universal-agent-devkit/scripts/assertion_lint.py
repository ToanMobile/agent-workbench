#!/usr/bin/env python3
"""A @Test / def test_ with no distinguishing assertion is vacuous.

A literal assertTrue(true), assert False, or assertEquals(1, 1) does not count.
One real assertion in the same method is enough. Regex over a brace body, not a
full parser: a test whose assert sits in a nested lambda still counts.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

_MARKER = re.compile(
    r"@(?:Test|ParameterizedTest|RepeatedTest|TestFactory)\b"
    r"|\[(?:UnityTest|Test|TestCase|TestCaseSource)\b"
    r"|^(?:[ \t]*)def[ \t]+(test_\w+)\s*\(",
    re.M,
)
_SKIP = re.compile(r"@(?:Ignore|Disabled)\b|\[Ignore\b|\[Explicit\b")
_ASSERT = re.compile(
    r"\bassert(?:True|False|Equals|NotEquals|Null|NotNull|That|Throws|Same|NotSame|ArrayEquals)\s*\("
    r"|\bAssert\.(?:AreEqual|AreNotEqual|IsTrue|IsFalse|IsNull|IsNotNull|That|Throws|Greater|Less|AreSame)\s*\("
    r"|\bassertThat\s*\("
    r"|\bexpect\s*\("
    r"|\bshould(?:Be|Not|Have|Throw)\b"
    r"|\bXCTAssert\w*\s*\("
    r"|\brequire(?:NotNull|\s*\()"
    r"|\bcheck(?:NotNull)?\s*\("
    r"|\bpytest\.raises\b"
    r"|\bself\.assert\w+\s*\("
    r"|\bassert\s+(?!True\b|False\b)"
)
_VACUOUS = re.compile(
    r"assertTrue\s*\(\s*true\s*\)"
    r"|assertFalse\s*\(\s*false\s*\)"
    r"|Assert\.IsTrue\s*\(\s*true\s*\)"
    r"|Assert\.IsFalse\s*\(\s*false\s*\)"
    r"|assert\s+True\b"
    r"|assert\s+False\b"
    r"|assert\s+1\s*==\s*1\b"
    r"|assert(?:Equals|Equal)\s*\(\s*(?P<lit>[0-9]+|true|false|\"[^\"\n]*\"|'[^'\n]*')\s*,\s*(?P=lit)\s*\)"
    r"|Assert\.AreEqual\s*\(\s*(?P<lit2>[0-9]+|true|false|\"[^\"\n]*\")\s*,\s*(?P=lit2)\s*\)",
    re.IGNORECASE,
)


def _body(text: str, start: int, limit: int | None = None) -> str:
    """Brace block of the method that starts at `start`, never crossing `limit`."""
    end = len(text) if limit is None else limit
    brace = text.find("{", start, end)
    if brace == -1:
        return text[start:end]
    depth = 0
    for i in range(brace, len(text)):
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[brace:i + 1]
    return text[brace:end]


def _python_body(text: str, start: int) -> str:
    line_start = text.rfind("\n", 0, start) + 1
    indent = len(text[line_start:start]) - len(text[line_start:start].lstrip(" "))
    lines = text[start:].splitlines(keepends=True)
    out = [lines[0]] if lines else []
    for line in lines[1:]:
        if line.strip() and (len(line) - len(line.lstrip(" "))) <= indent and not line.lstrip().startswith("#"):
            break
        out.append(line)
    return "".join(out)


def _distinguishing(body: str) -> bool:
    vacuous_spans = [(m.start(), m.end()) for m in _VACUOUS.finditer(body)]

    def inside_vacuous(span) -> bool:
        return any(a <= span[0] and span[1] <= b for a, b in vacuous_spans)

    return any(not inside_vacuous(m.span()) for m in _ASSERT.finditer(body))


def findings(text: str) -> list:
    """[(line, name)] methods that never assert on a value."""
    out = []
    for m in _MARKER.finditer(text):
        window_start = max(0, m.start() - 120)
        prelude = text[window_start:m.end()]
        if _SKIP.search(prelude):
            continue
        name = m.group(1) or m.group(0)[:40]
        if m.group(1):
            body = _python_body(text, m.start())
        else:
            nxt = _MARKER.search(text, m.end())
            body = _body(text, m.end(), nxt.start() if nxt else None)
        if not _distinguishing(body):
            line = text.count("\n", 0, m.start()) + 1
            out.append((line, name.strip()))
    return out


def main(argv: list) -> int:
    if len(argv) < 2:
        print("usage: assertion_lint.py <test-file>...", file=sys.stderr)
        return 2
    bad = 0
    for raw in argv[1:]:
        text = Path(raw).read_text(encoding="utf-8", errors="replace")
        for line, name in findings(text):
            bad += 1
            print(f"{raw}:{line}: test không có assertion phân biệt dữ liệu ({name})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
