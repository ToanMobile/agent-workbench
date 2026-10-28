#!/usr/bin/env python3
"""#560: liệt kê PR mở có issue Closes/Fixes/Resolves đã ĐÓNG (PR mồ côi), chỉ đọc.

PR nháp 22–24/10 (#204…#246) còn mở dù issue đã đóng: pre-flight vẫn đếm chúng là đụng file.
Luật: super-board-orphan-prs.py in số PR, issue, ngày cập nhật, lý do; PR có issue còn mở thì bỏ;
test dưới kiểm: lister/reader chỉ nhận lời gọi đọc, và mã nguồn script không chứa chuỗi lệnh ghi.
"""
from __future__ import annotations

import importlib.util
import io
import sys
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / ".claude" / "bin" / "super-board-orphan-prs.py"


def load():
    spec = importlib.util.spec_from_file_location("super_board_orphan_prs_under_test", SCRIPT)
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
    prs = [
        {"number": 204, "title": "a", "body": "Closes #150", "headRefName": "issue-150-a", "updatedAt": "2026-10-22T01:00:00Z", "isDraft": True},
        {"number": 207, "title": "b", "body": "Fixes #151, resolves #152", "headRefName": "issue-151-b", "updatedAt": "2026-10-23T01:00:00Z", "isDraft": True},
        {"number": 300, "title": "c", "body": "Closes #153", "headRefName": "issue-153-c", "updatedAt": "2026-10-27T01:00:00Z", "isDraft": False},
        {"number": 301, "title": "d", "body": "Refs #150 — không đóng gì", "headRefName": "x", "updatedAt": "2026-10-27T01:00:00Z", "isDraft": True},
    ]
    states = {150: "CLOSED", 151: "CLOSED", 152: "OPEN", 153: "OPEN"}
    calls = []

    def lister(repo):
        calls.append(("list", repo))
        return prs

    def reader(repo, n):
        calls.append(("state", n))
        return states[n]

    found = m.find_orphans("o/r", lister, reader)
    nums = [f["pr"] for f in found]
    check(nums == [204, 207], "chỉ PR có issue đóng bị liệt kê", str(nums))
    check(found[0]["issues"] == [150] and found[0]["updatedAt"].startswith("2026-10-22"), "PR #204: issue + ngày cập nhật", str(found[0]))
    check(found[1]["issues"] == [151], "PR #207: chỉ issue đã đóng (#152 còn mở bị bỏ)", str(found[1]))
    check("đã đóng" in found[0]["reason"] and "#150" in found[0]["reason"], "có lý do", found[0]["reason"])
    check(all(c[0] in ("list", "state") for c in calls), "chỉ gọi đọc")

    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        rc = m.main(["--repo", "o/r"], lister=lister, reader=reader)
    text = out.getvalue()
    check(rc == 0 and "#204" in text and "#207" in text and "#300" not in text, "main in danh sách", text)
    check("dry-run" in text.lower(), "ghi rõ dry-run", text)

    # Mã nguồn mặc định không chứa lệnh ghi nào.
    src = SCRIPT.read_text(encoding="utf-8")
    forbidden = ["pr " + "close", "--" + "delete", "pus" + "h", "issue " + "edit", "issue " + "comment", "issue " + "close"]
    for bad in forbidden:
        check(bad not in src, f"mã nguồn không chứa lệnh ghi: {bad}")

    def broken(repo, n):
        raise OSError("gh down")

    with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
        rc = m.main(["--repo", "o/r"], lister=lister, reader=broken)
    check(rc == 79, "không đọc được trạng thái → exit 79, không đoán", str(rc))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
