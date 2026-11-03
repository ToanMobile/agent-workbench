#!/usr/bin/env python3
"""agent-kit approve-tests <task-id> — ghi mục duyệt chéo test sửa từ biên bản audit antigravity-pm (đợt 2 lane A, mục 2).

Thay 5 bước tay (đọc auditedHead, băm từng test, ghi JSON). Không thay kiểm: post-fix-gate kiểm lại mọi mục bằng CÙNG luật
(push_gate.audited_head / audit_reviewer, post-fix-gate.audit_covers).
- reviewer và auditedHead chỉ lấy từ biên bản PM ngoài repo (verdicts.audit), không bao giờ từ dòng lệnh; reviewer qua
  push_gate.audit_reviewer(legacy=False): grok chỉ khi lượt audit gần nhất PM tự chạy là grok, biên bản cũ (reviewer "pm") chỉ là
  antigravity khi dispatches có lượt audit antigravity, không thì từ chối.
- author = push_gate.session_agent() (DEVKIT_AGENT_ID, không thì grok / claude theo env của phiên; rỗng → từ chối); reviewer trùng
  author hoặc thuộc tập danh tính phiên push_gate.session_agents() → từ chối (đợt 2 F2, vòng kiểm lại H4).
- test sửa = file test có ở merge-base(trunk, HEAD) và khác ở cây làm việc (đã commit + bẩn); chỉ ghi file audit_covers nhận.
- ghi/thay mục {path, sha256, reviewer, author, task_id, reason} trong .claude/audit-gate/approved_tests.json của checkout hiện tại
  (get_project_dir của gate); thư mục đó trỏ ra ngoài checkout (symlink) → từ chối. Ghi nguyên tử.
Exit: 0 đã ghi ≥1 mục · 1 không có test nào để ghi · 2 từ chối · 3 lỗi ngoài dự kiến (ngoại lệ, đợt 2 F6: không lẫn với 1).
"""
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

DEVKIT = Path(__file__).resolve().parents[2]


def _gate():
    spec = importlib.util.spec_from_file_location("post_fix_gate_approve", DEVKIT / "bin" / "post-fix-gate.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def refuse(msg):
    print(f"approve-tests: từ chối — {msg}", file=sys.stderr)
    return 2


def main(argv):
    if len(argv) != 1 or argv[0].startswith("-"):
        print("usage: agent-kit approve-tests <task-id>   (reviewer, auditedHead: từ biên bản antigravity-pm; author: danh tính phiên)",
              file=sys.stderr)
        return 2
    task_id = argv[0].strip()
    gate = _gate()
    pg = gate._push_gate()
    author = pg.session_agent()
    if not author:
        return refuse("không xác định được danh tính phiên (DEVKIT_AGENT_ID rỗng, không có env phiên Grok / Claude Code): "
                      "không biết phiên nào là author")
    project = Path(os.path.realpath(gate.get_project_dir()))
    top, prefix = str(gate.get_repo_root()), gate.get_project_prefix()
    head = pg.audited_head(top, task_id)
    if not head:
        return refuse(f"task {task_id} không có biên bản audit pass của antigravity-pm kèm auditedHead cho repo này")
    reviewer = pg.audit_reviewer(top, task_id, legacy=False)
    if not reviewer:
        return refuse(f"task {task_id}: biên bản PM không xác định được reviewer (verdicts.audit.reviewer khớp lượt audit gần nhất "
                      "trong dispatches)")
    agents = pg.session_agents()   # vòng kiểm lại H4: reviewer thuộc TẬP danh tính phiên (DEVKIT_AGENT_ID=codex trong phiên Grok vẫn là grok)
    if reviewer == author or reviewer in agents:
        return refuse(f"reviewer {reviewer} trùng author {author} / danh tính phiên {', '.join(sorted(agents))} (tự duyệt)")
    chain = gate._approval_chain(top, project)
    if not chain:
        return refuse("không xác định được nhánh đích / merge-base (lỗi git)")
    base = chain[1]
    diff = subprocess.run(["git", "-C", str(project), "diff", "--name-only", "--relative", base, "--"],
                          capture_output=True, text=True, timeout=60)
    if diff.returncode != 0:
        return refuse(f"git diff {base[:10]} lỗi: {diff.stderr.strip()[:200]}")
    entries, skipped = [], []
    for f in diff.stdout.splitlines():
        if not f or not gate.is_test_path(f) or not (project / f).is_file():
            continue
        existed = subprocess.run(["git", "-C", top, "cat-file", "-e", f"{base}:{prefix}{f}"], capture_output=True, timeout=30)
        if existed.returncode != 0:
            continue                                   # test mới: không cần duyệt
        ok, why = gate.audit_covers(top, prefix, project, f, head)
        if not ok:
            skipped.append((f, why))
            continue
        sha = hashlib.sha256((project / f).read_bytes()).hexdigest()
        entries.append({"path": f, "sha256": sha, "reviewer": reviewer, "author": author, "task_id": task_id,
                        "reason": f"audit {reviewer} pass, task {task_id}, auditedHead {head[:12]} (agent-kit approve-tests)"})
    for f, why in skipped:
        print(f"approve-tests: bỏ qua {f} — {why}", file=sys.stderr)
    if not entries:
        print("approve-tests: không có test sửa nào khớp cây đã audit; không ghi gì", file=sys.stderr)
        return 1
    ledger_dir = project / ".claude" / "audit-gate"
    ledger_dir.mkdir(parents=True, exist_ok=True)
    real_dir = os.path.realpath(ledger_dir)
    if not real_dir.startswith(str(project) + os.sep):
        return refuse(f"{ledger_dir} trỏ ra ngoài checkout hiện tại ({real_dir})")
    ledger = Path(real_dir) / "approved_tests.json"
    if ledger.is_symlink():
        return refuse(f"{ledger} là symlink")
    data = {"approvals": []}
    if ledger.exists():
        try:
            data = json.loads(ledger.read_text(encoding="utf-8"))
        except (OSError, ValueError, RecursionError) as e:
            return refuse(f"{ledger} không đọc được ({type(e).__name__}); không ghi đè")
        if not isinstance(data, dict) or not isinstance(data.get("approvals"), list):
            return refuse(f"{ledger} không phải dạng {{\"approvals\": [...]}}; không ghi đè")
    new_paths = {e["path"] for e in entries}
    data["approvals"] = [e for e in data["approvals"] if not (isinstance(e, dict) and e.get("path") in new_paths)] + entries
    fd, tmp = tempfile.mkstemp(dir=real_dir, prefix="approved_tests.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=1)
        os.replace(tmp, ledger)
    except OSError as e:
        try:
            os.remove(tmp)
        except OSError:
            pass
        return refuse(f"ghi {ledger} lỗi ({e})")
    label = "grok (thay Antigravity)" if reviewer == "grok" else reviewer
    for e in entries:
        print(f"approve-tests: duyệt chéo {label}, task {task_id}: {e['path']} sha256={e['sha256'][:12]}")
    print(f"approve-tests: đã ghi {len(entries)} mục vào {ledger}; chạy lại gate để nó kiểm lại")
    return 0


def run(argv):
    """main với lỗi ngoài dự kiến thành exit 3 kèm thông báo (đợt 2 F6): traceback trần ra exit 1 = "không có test để ghi"."""
    try:
        return main(argv)
    except Exception as e:  # noqa: BLE001 - mọi lỗi: báo rõ, exit 3, không ghi gì thêm
        print(f"approve-tests: lỗi ({type(e).__name__}: {e}); không ghi gì thêm", file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))
