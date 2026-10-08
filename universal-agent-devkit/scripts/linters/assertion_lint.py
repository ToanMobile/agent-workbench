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
    # any assertXxx( / assertXxx<T>(: kotlin.test assertIs<T>, assertFailsWith<T>, assertContains, and
    # method assertions — Compose .assertExists(), .assertIsDisplayed(), .assertTextEquals() (OfficeReader
    # 2026-09-26: a real Compose test was called vacuous and rewritten to pass the gate)
    r"|\bassert[A-Z]\w*\s*[<(]"
    r"|\bAssert\.(?:AreEqual|AreNotEqual|IsTrue|IsFalse|IsNull|IsNotNull|That|Throws|Greater|Less|AreSame)\s*\("
    r"|\bassertThat\s*\("
    r"|\bexpect\s*\("
    r"|\b(?:co)?[Vv]erify(?:All|Order|Sequence)?\s*(?:\(|\{)"
    r"|\bshould(?:Be|Not|Have|Throw)\b"
    r"|\bXCTAssert\w*\s*\("
    r"|\brequire(?:NotNull|\s*\()"
    r"|\bcheck(?:NotNull)?\s*\("
    r"|\bpytest\.raises\b"
    r"|\bself\.assert\w+\s*\("
    r"|\bassert\s+(?!True\b|False\b)"
    # Kotlin's assert(cond) (Gradle runs tests with -ea) and JUnit/kotlin.test fail(…)
    r"|\bassert\s*\(|\bfail\s*\("
)
# @Test(expected = X::class) / TestNG expectedExceptions: the thrown exception is the assertion.
_EXPECTS = re.compile(r"\s*\(\s*(?:expected|expectedExceptions)\s*=")
_VACUOUS = re.compile(
    r"assertTrue\s*\(\s*true\s*\)"
    r"|assertFalse\s*\(\s*false\s*\)"
    r"|Assert\.IsTrue\s*\(\s*true\s*\)"
    r"|Assert\.IsFalse\s*\(\s*false\s*\)"
    r"|assert\s+True\b"
    r"|assert\s+False\b"
    r"|assert\s+1\s*==\s*1\b"
    r"|\bassert\s*\(\s*(?:true|false)\s*\)"
    r"|assert(?:Equals|Equal)\s*\(\s*(?P<lit>[0-9]+|true|false|\"[^\"\n]*\"|'[^'\n]*')\s*,\s*(?P=lit)\s*\)"
    r"|Assert\.AreEqual\s*\(\s*(?P<lit2>[0-9]+|true|false|\"[^\"\n]*\")\s*,\s*(?P=lit2)\s*\)",
    re.IGNORECASE,
)

# ponytail: Python assertIsNotNone/pytest is not None không được phủ; thêm khi một dự án Python cần
_EXISTENCE = re.compile(
    r"\bassertNotNull\s*\(\s*(.*?)\s*\)(?=\s*(?:;|\n|$))"
    r"|\bAssert\.IsNotNull\s*\(\s*(.*?)\s*\)(?=\s*(?:;|\n|$))"
    r"|\bassertThat\s*\(\s*(.*?)\s*\)\s*\.\s*(?:isNotNull\s*\(\)|exists\s*\(\))",
    re.IGNORECASE
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

    for m in _EXISTENCE.finditer(body):
        args_str = (m.group(1) or m.group(2) or m.group(3))
        if args_str:
            args_str = args_str.strip()
            # Remove string literal argument at the start (e.g. assertNotNull("msg", x))
            args_str = re.sub(r'^\s*(?:"[^"]*"|\'[^\']*\')\s*,\s*', '', args_str)
            # Remove string literal argument at the end (e.g. assertNotNull(x, "msg"))
            args_str = re.sub(r'\s*,\s*(?:"[^"]*"|\'[^\']*\')\s*$', '', args_str)
            arg = args_str.strip()
            
            # literal string, number, true/false, null
            if re.match(r"^(?:true|false|null|undefined|\d+|[\"'].*[\"'])$", arg, re.IGNORECASE):
                vacuous_spans.append(m.span())
            # Singleton / capitalized bare reference
            elif re.match(r"^[A-Z]\w*$", arg):
                vacuous_spans.append(m.span())
            # var created by constructor (must be a bare word)
            elif re.match(r"^\w+$", arg):
                if re.search(r"\b" + re.escape(arg) + r"\s*=\s*(?:new\s+)?[A-Z]\w*\([^()\n]*\)\s*;?\s*$", body, re.MULTILINE):
                    if len(re.findall(r"\b" + re.escape(arg) + r"\s*=(?!=)", body)) == 1:
                        vacuous_spans.append(m.span())

    def inside_vacuous(span) -> bool:
        return any(a <= span[0] and span[1] <= b for a, b in vacuous_spans)

    return any(not inside_vacuous(m.span()) for m in _ASSERT.finditer(body))


# A same-file helper a test calls: Kotlin `fun`, Python `def`, Java/C# `void` methods.
_HELPER_DEF = re.compile(
    r"\bfun\s+(?:<[^>\n]*>\s*)?(?:[\w.]+\.)?(\w+)\s*\("
    r"|^[ \t]*def[ \t]+(\w+)\s*\("
    r"|\bvoid\s+(\w+)\s*\(",
    re.M,
)


def _asserting_helpers(text: str) -> set:
    """Names of same-file functions whose body asserts, directly or through another such
    helper (GeelyEx2 2026-09-27: five tests calling `kiem(...)` were called vacuous and
    rewritten only to please the gate). A helper whose only assertion is vacuous does not count."""
    defs = list(_HELPER_DEF.finditer(text))
    bodies = {}
    for i, m in enumerate(defs):
        name = m.group(1) or m.group(2) or m.group(3)
        if m.group(2):
            body = _python_body(text, m.start())
        else:
            limit = defs[i + 1].start() if i + 1 < len(defs) else None
            nxt = _MARKER.search(text, m.end())
            if nxt and (limit is None or nxt.start() < limit):
                limit = nxt.start()
            body = _body(text, m.end(), limit)
            if "{" not in text[m.end():limit if limit is not None else len(text)]:
                body = text[m.end():limit]          # expression body: fun f() = assertX(...)
        bodies[name] = bodies.get(name, "") + body
    helpers = {n for n, b in bodies.items() if _distinguishing(b)}
    changed = True
    while changed:
        changed = False
        for n, b in bodies.items():
            if n not in helpers and helpers and re.search(r"\b(?:%s)\s*\(" % "|".join(map(re.escape, helpers)), b):
                helpers.add(n)
                changed = True
    return helpers


def findings(text: str) -> list:
    """[(line, name)] methods that never assert on a value."""
    out = []
    helpers = _asserting_helpers(text)
    calls_helper = re.compile(r"\b(?:%s)\s*\(" % "|".join(map(re.escape, helpers))) if helpers else None
    for m in _MARKER.finditer(text):
        window_start = max(0, m.start() - 120)
        prelude = text[window_start:m.end()]
        if _SKIP.search(prelude) or (not m.group(1) and _EXPECTS.match(text, m.end())):
            continue
        name = m.group(1) or m.group(0)[:40]
        if m.group(1):
            body = _python_body(text, m.start())
        else:
            nxt = _MARKER.search(text, m.end())
            body = _body(text, m.end(), nxt.start() if nxt else None)
        if not _distinguishing(body) and not (calls_helper and calls_helper.search(body)):
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
