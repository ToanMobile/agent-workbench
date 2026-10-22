#!/usr/bin/env python3
"""#253: dòng `blocked-by:` chỉ được ghi issue còn MỞ thật.

Builder #200 (22/10) ghi `blocked-by:` có #160 đã merge; sweep thả thẻ về Ready, builder build lại, vòng lặp (6 lượt).
Luật: super-board-blocked-by.py line --repo R 160,161 in ra dòng máy đọc chỉ với số còn mở, lý do bỏ số đã đóng
ra stderr (để builder đưa vào comment); không còn số nào mở thì `blocked-by: -`; không đọc được trạng thái thì exit 79
(không đoán, không ghi).
"""
from __future__ import annotations

import importlib.util
import io
import sys
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / ".claude" / "bin" / "super-board-blocked-by.py"


def load():
    spec = importlib.util.spec_from_file_location("super_board_blocked_by_under_test", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    fails = 0

    def check(cond, label, detail=""):
        nonlocal fails
        if cond:
            print("✔", label)
        else:
            print("✖", label, detail)
            fails += 1

    m = load()
    states = {160: "CLOSED", 161: "OPEN", 162: "OPEN"}

    def run(argv, reader):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            rc = m.main(argv, reader=reader)
        return rc, out.getvalue(), err.getvalue()

    rc, out, err = run(["line", "--repo", "a/b", "160,161"], lambda repo, n: states[n])
    check(rc == 0 and out.strip() == "blocked-by: 161", "closed #160 dropped, open #161 kept", f"rc={rc} out={out!r}")
    check("#160" in err and ("closed" in err.lower() or "đã đóng" in err), "stderr gives the reason for dropping #160", err)

    rc, out, err = run(["line", "--repo", "a/b", "161,162"], lambda repo, n: states[n])
    check(rc == 0 and out.strip() == "blocked-by: 161, 162", "all open: both kept, sorted", f"out={out!r}")

    rc, out, err = run(["line", "--repo", "a/b", "160"], lambda repo, n: states[n])
    check(rc == 0 and out.strip() == "blocked-by: -", "only closed blockers: `blocked-by: -`, nothing invented", f"out={out!r}")

    def broken(repo, n):
        raise OSError("gh unreachable")

    rc, out, err = run(["line", "--repo", "a/b", "161"], broken)
    check(rc == 79 and out == "", "unreadable state: exit 79, no line written", f"rc={rc} out={out!r}")

    rc, out, err = run(["line", "--repo", "a/b", "abc"], lambda repo, n: "OPEN")
    check(rc == 64 and out == "", "bad issue list: exit 64", f"rc={rc}")

    # the real read_state: stub `gh` on PATH; a PR answers MERGED, a typo answers "Could not resolve", an outage exits 1
    import os, stat, tempfile
    with tempfile.TemporaryDirectory() as d:
        gh = Path(d) / "gh"
        gh.write_text('''#!/bin/sh
case "$3" in
  208) echo "MERGED https://github.com/a/b/pull/208" ;;
  246) echo "OPEN https://github.com/a/b/pull/246" ;;
  999) echo "GraphQL: Could not resolve to an issue or pull request with the number of 999." >&2; exit 1 ;;
  500) echo "HTTP 502" >&2; exit 1 ;;
  *) echo "OPEN https://github.com/a/b/issues/$3" ;;
esac
''')
        gh.chmod(gh.stat().st_mode | stat.S_IEXEC)
        old = os.environ["PATH"]
        os.environ["PATH"] = d + os.pathsep + old
        try:
            rc, out, err = run(["line", "--repo", "a/b", "208,7"], m.read_state)
            check(rc == 0 and out.strip() == "blocked-by: 7", "a merged PR number counts as closed", f"rc={rc} out={out!r} err={err!r}")
            rc, out, err = run(["line", "--repo", "a/b", "246,7"], m.read_state)
            check(rc == 64 and out == "", "an OPEN pull request number is refused (deps.sh would read it as closed)", f"rc={rc} out={out!r}")
            rc, out, err = run(["line", "--repo", "a/b", "999"], m.read_state)
            check(rc == 64 and out == "", "a number that is not in the repo: exit 64, not a halt", f"rc={rc}")
            rc, out, err = run(["line", "--repo", "a/b", "500"], m.read_state)
            check(rc == 79 and out == "", "a gh outage: exit 79, no line", f"rc={rc}")
        finally:
            os.environ["PATH"] = old

    print("ALL PASS" if fails == 0 else f"{fails} FAILED")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
