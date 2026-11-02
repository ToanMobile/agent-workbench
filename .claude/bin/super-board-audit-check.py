#!/usr/bin/env python3
"""Đối chiếu task_id tự khai (`approved-by:` / `cross-review-approved:`) với biên bản audit của antigravity-pm (#605, audit T0066 vòng 2).

Marker duyệt chéo chỉ là lời khai trong comment (mọi lane dùng chung token OWNER), nên chỉ tính khi antigravity-pm có verdict audit
`pass` cho đúng task đó với `auditedHead` == head đang được duyệt (push_gate.audited_head: biên bản ngoài repo, sha phải là commit
có trong repo). Không tìm thấy push_gate, task_id sai dạng, không có biên bản, head lệch, lỗi git → không duyệt (fail closed).

pm home lạ (ANTIGRAVITY_PM_STATE_HOME, HOME=/tmp/x) không phải fixture test → không duyệt (push_gate.pm_home_overridden /
pm_home_test_fixture, audit T0066 vòng 3). `--pr N`: head chưa có object trong repo thì fetch refs/pull/N/head trước (lỗi → không duyệt).

CLI: super-board-audit-check.py <task_id> <sha40> [--top DIR] [--pr N]   exit 0 = khớp, 1 = không khớp / không kiểm được.
"""
from __future__ import annotations

import argparse
import importlib.util
import re
import subprocess
import sys
from pathlib import Path

TASK_ID = re.compile(r"T\d{4,}-[a-z0-9-]{1,48}\Z")   # antigravity-pm TASK_ID_RE (src/tasks.js), như push_gate.APPROVED_VALUE
SHA = re.compile(r"[0-9a-f]{40}\Z")
_PUSH_GATE = []


def push_gate():
    """push_gate.py của kit, tìm theo vị trí THẬT của script này (không theo biến môi trường: một biến như thế là lối lách)."""
    if not _PUSH_GATE:
        root = Path(__file__).resolve().parents[2]
        mod = None
        for cand in (root / "universal-agent-devkit/bin/push_gate.py", root / ".agents/devkit/bin/push_gate.py"):
            if cand.is_file():
                spec = importlib.util.spec_from_file_location("sb_push_gate", cand)
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
                break
        _PUSH_GATE.append(mod if mod is not None and callable(getattr(mod, "audited_head", None)) else None)
    return _PUSH_GATE[0]


def repo_top(cwd=None):
    try:
        run = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=cwd, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    return run.stdout.strip() if run.returncode == 0 and run.stdout.strip() else None


def audited(task_id, top=None):
    """auditedHead (sha40) của verdict audit pass của `task_id` trong repo `top` (mặc định: repo của cwd), hoặc None."""
    if not isinstance(task_id, str) or not TASK_ID.fullmatch(task_id):
        return None
    top = top or repo_top()
    gate = push_gate()
    if not top or gate is None:
        return None
    # audit T0066 vòng 3: biên bản ở pm home lạ thì agent nào cũng tự dựng được; push_gate thiếu hàm kiểm (bản cũ) → không duyệt.
    overridden, fixture = getattr(gate, "pm_home_overridden", None), getattr(gate, "pm_home_test_fixture", None)
    if not callable(overridden) or not callable(fixture) or (overridden() and not fixture()):
        print(f"audit-check: antigravity-pm state home is not ~/.antigravity-pm; the audit record of {task_id} does not count",
              file=sys.stderr)
        return None
    try:
        head = gate.audited_head(top, task_id)
    except Exception as error:   # noqa: BLE001 - biên bản hỏng không bao giờ thành duyệt; ghi lý do ra stderr
        print(f"audit-check: cannot read the audit record of {task_id}: {error.__class__.__name__}", file=sys.stderr)
        return None
    return head if isinstance(head, str) and SHA.fullmatch(head) else None


def ensure_commit(top, sha, pr):
    """True khi `sha` là commit có trong repo `top`; thiếu object thì fetch refs/pull/<pr>/head từ origin một lần (audit T0066 vòng 3:
    head PR chưa fetch về checkout của board làm biên bản thật bị bác). Lỗi git / không có pr → False (caller từ chối như cũ)."""
    top = top or repo_top()
    if not top or not isinstance(sha, str) or not SHA.fullmatch(sha):
        return False

    def present():
        try:
            return subprocess.run(["git", "-C", top, "cat-file", "-e", sha + "^{commit}"], capture_output=True,
                                  timeout=15).returncode == 0
        except (OSError, subprocess.SubprocessError):
            return False

    if present():
        return True
    if type(pr) is not int or pr <= 0:
        return False
    try:
        run = subprocess.run(["git", "-C", top, "fetch", "--quiet", "origin", f"refs/pull/{pr}/head"], capture_output=True,
                             text=True, timeout=60)
    except (OSError, subprocess.SubprocessError) as error:
        print(f"audit-check: fetch of PR #{pr} head failed: {error.__class__.__name__}", file=sys.stderr)
        return False
    if run.returncode != 0:
        print(f"audit-check: fetch of PR #{pr} head failed: {run.stderr.strip()[:200]}", file=sys.stderr)
    return present()


def matches(task_id, sha, top=None):
    return isinstance(sha, str) and bool(SHA.fullmatch(sha)) and audited(task_id, top) == sha


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("task_id")
    ap.add_argument("sha")
    ap.add_argument("--top", help="repo chứa biên bản (mặc định: git toplevel của cwd)")
    ap.add_argument("--pr", type=int, help="số PR: head chưa có trong repo thì fetch refs/pull/<pr>/head trước khi đối chiếu")
    args = ap.parse_args()
    if args.pr is not None:
        ensure_commit(args.top, args.sha, args.pr)
    if matches(args.task_id, args.sha, args.top):
        return 0
    print(f"audit-check: task {args.task_id!r} has no antigravity-pm audit pass with auditedHead {args.sha[:12]}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
