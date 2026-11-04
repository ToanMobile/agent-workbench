#!/usr/bin/env python3
"""Đối chiếu task_id tự khai (`approved-by:` / `cross-review-approved:`) với biên bản audit của antigravity-pm (#605, audit T0066 vòng 2).

Marker duyệt chéo chỉ là lời khai trong comment (mọi lane dùng chung token OWNER), nên chỉ tính khi antigravity-pm có verdict audit
`pass` cho đúng task đó với `auditedHead` == head đang được duyệt (push_gate.audited_head: biên bản ngoài repo, sha phải là commit
có trong repo). Không tìm thấy push_gate, task_id sai dạng, không có biên bản, head lệch, lỗi git → không duyệt (fail closed).

pm home lạ (ANTIGRAVITY_PM_STATE_HOME, HOME=/tmp/x) không phải fixture test → không duyệt (push_gate.pm_home_overridden /
pm_home_test_fixture, audit T0066 vòng 3). `--pr N`: head chưa có object trong repo thì fetch refs/pull/N/head trước (lỗi → không duyệt).

CLI: super-board-audit-check.py <task_id> <sha40> [--top DIR] [--pr N]   exit 0 = khớp, 1 = không khớp / không kiểm được.
CLI: super-board-audit-check.py --chain-audit <sha40> --base <ref> [--top DIR]   (04/11, merge gate / train --has-edited-tests)
     exit 0 = PR sửa/xoá file đã có mà gate có thể coi là test (edited_existing) VÀ có biên bản audit pass của antigravity-pm với
     auditedHead thuộc <base>..<sha40> (duyệt test sửa tra thẳng biên bản, post-fix-gate _pm_audit_cross_review), HOẶC không kiểm được
     (giữ đường bi quan: khoá, không autosync); exit 1 = không có (PR chỉ có audit lớn mà không sửa test thì không bi quan); mã khác
     (lỗi nạp, sai tham số) = bi quan.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
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


# Script mà post-fix-gate.suite_runner_paths đọc tiếp để tìm script tầng sau (_RUNNER_FOLLOW_EXT, cộng script không đuôi).
FOLLOW_EXT = (".sh", ".bash", ".zsh", "")
TOKEN = re.compile(r"[\w./-]+")


def _tokens(text):
    """(token, basename của token) của một văn bản lệnh: "./bin/x" → "bin/x"."""
    toks = {t[2:] if t.startswith("./") else t for t in TOKEN.findall(text)}
    return toks, {os.path.basename(t) for t in toks}


def edited_existing(top, sha, base, gate):
    """Siêu tập các file đã có ở merge-base(base, sha) mà PR sửa/xoá và gate có thể coi là test đã có bị sửa: đường dẫn test
    (post-fix-gate.is_test_path, nạp từ kit cạnh push_gate), hoặc file được NHẮC TÊN (nguyên token, theo đường dẫn hay tên file) trong
    ma trận hồi quy hay trong script mà ma trận gọi, đi tiếp hai tầng như post-fix-gate.suite_runner_paths (script suite như bin/agent-kit,
    script .py mà script .sh của suite gọi; Grok review 04/11). File không ai nhắc thì gate không bao giờ coi là script suite. Script
    đọc ở `base`. Lỗi git/nạp/đọc ma trận → raise (người gọi coi là có)."""
    def git(*args):
        run = subprocess.run(["git", "-C", top, *args], capture_output=True, text=True, timeout=60)
        if run.returncode != 0:
            raise RuntimeError(f"git {args[0]}: exit {run.returncode}")
        return run.stdout
    parts = git("diff", "--name-status", "--no-renames", "-z", f"{base}...{sha}").split("\0")
    paths = [parts[i + 1] for i in range(0, len(parts) - 1, 2) if parts[i][:1] in ("M", "D", "T")]
    if not paths:
        return []
    spec = importlib.util.spec_from_file_location("sb_post_fix_gate", Path(gate.__file__).with_name("post-fix-gate.py"))
    pfg = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pfg)
    # Ma trận đọc ở `base` như gate (Grok review 04/11), không ở cây làm việc. Không có ở base = gate không có script suite để theo.
    have = subprocess.run(["git", "-C", top, "cat-file", "-e", f"{base}:{gate.MATRIX}"], capture_output=True, timeout=60)
    matrix = git("cat-file", "-p", f"{base}:{gate.MATRIX}") if have.returncode == 0 else ""
    toks, names = _tokens(matrix)
    files = [f for f in git("ls-tree", "-r", "--name-only", "-z", base).split("\0") if f]
    followed = set()
    for _depth in range(2):                         # script ma trận nhắc, rồi script mà chúng nhắc
        new = [f for f in files if f not in followed and Path(f).suffix in FOLLOW_EXT and (f in toks or os.path.basename(f) in names)]
        if not new:
            break
        for f in new:
            followed.add(f)
            t2, n2 = _tokens(git("cat-file", "-p", f"{base}:{f}"))
            toks |= t2
            names |= n2
    return [p for p in paths if pfg.is_test_path(p) or p in toks or os.path.basename(p) in names]


def chain_audit(sha, base, top=None):
    """True khi PR (head sha) có thể đang dựa vào duyệt test sửa tra thẳng từ biên bản PM: PR sửa file test đã có (edited_existing) và
    một audit pass của repo có auditedHead trong `git rev-list sha --not base` (tổ tiên-hoặc-chính head PR, không thuộc base). Lỗi /
    không kiểm được → True (fail về phía bi quan)."""
    top = top or repo_top()
    gate = push_gate()
    if not top or gate is None or not isinstance(sha, str) or not SHA.fullmatch(sha) or not base:
        return True
    try:
        if not edited_existing(top, sha, base, gate):
            return False
        heads = gate.audited_heads(top)
        run = subprocess.run(["git", "-C", top, "rev-list", sha, "--not", base], capture_output=True, text=True, timeout=60)
    except Exception as error:   # noqa: BLE001 - biên bản / git hỏng: giữ đường bi quan
        print(f"audit-check: cannot read the audit records: {error.__class__.__name__}", file=sys.stderr)
        return True
    if run.returncode != 0:
        return True
    pr_commits = set(run.stdout.split())
    return any(h in pr_commits for _tid, h in heads)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--chain-audit":
        cp = argparse.ArgumentParser(prog="super-board-audit-check.py --chain-audit")
        cp.add_argument("sha")
        cp.add_argument("--base", required=True)
        cp.add_argument("--top")
        cargs = cp.parse_args(sys.argv[2:])
        try:
            return 0 if chain_audit(cargs.sha, cargs.base, cargs.top) else 1
        except Exception as error:   # noqa: BLE001 - lỗi nạp push_gate / repo: bi quan, không bao giờ là "không có"
            print(f"audit-check: --chain-audit failed: {error.__class__.__name__}", file=sys.stderr)
            return 3
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
