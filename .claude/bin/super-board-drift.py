#!/usr/bin/env python3
"""super-board-drift.py — phát hiện bản sao super-board ở repo app lệch khỏi bản nguồn (#368). Chỉ đọc, stdlib.

    super-board-drift.py --source <repo nguồn> --target <repo app> [--target ...]

So sha256 từng file super-board của nguồn (.claude/bin/super-*, .claude/workflows/super-board-wave.js,
.claude/skills/super-board*/, super-build, super-qa, super-review, super-collect) với cùng đường dẫn ở mỗi target.
In một dòng JSON: {"source": ..., "targets": {<repo>: {"missing": [...], "changed": [...]}}, "drifted": bool}.
Thoát 0 khi mọi target khớp, 1 khi có lệch (missing = nguồn có, bản sao thiếu; changed = nội dung khác), 64 khi dùng sai.
Target trùng chính nguồn thì bỏ qua. File chỉ có ở target (bản địa phương) không tính là lệch.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys

SKILLS = ("super-board", "super-build", "super-qa", "super-review", "super-collect")


def git_listed(root):
    """File git theo dõi dưới .claude của nguồn; None khi root không phải repo git (khi đó quét thư mục)."""
    try:
        r = subprocess.run(["git", "-C", root, "ls-files", "-z", "--", ".claude"], capture_output=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    return [p for p in r.stdout.decode("utf-8", "replace").split("\0") if p]


def walked(root):
    """Đường lùi khi nguồn không phải repo git: bỏ __pycache__, file ẩn và *.pyc (rác sinh ra, không phải bản nguồn)."""
    out = []
    for dirpath, dirs, names in os.walk(os.path.join(root, ".claude")):
        dirs[:] = [d for d in dirs if d != "__pycache__" and not d.startswith(".")]
        out += [os.path.relpath(os.path.join(dirpath, n), root) for n in names
                if not n.startswith(".") and not n.endswith(".pyc")]
    return out


def is_super_board_file(rel):
    parts = rel.split("/")
    if parts[:2] == [".claude", "bin"]:
        return len(parts) == 3 and parts[2].startswith("super-")
    if rel == ".claude/workflows/super-board-wave.js":
        return True
    return parts[:2] == [".claude", "skills"] and len(parts) > 3 and parts[2] in SKILLS


def tracked_files(root):
    """Đường dẫn tương đối (so với root) của mọi file super-board trong nguồn: theo `git ls-files` (file chưa theo dõi như
    __pycache__/*.pyc, .DS_Store không tính), nguồn không phải repo git thì quét thư mục."""
    listed = git_listed(root)
    if listed is None:
        listed = walked(root)
    return sorted(r for r in listed if is_super_board_file(r) and os.path.isfile(os.path.join(root, r)))


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def compare(source, target):
    missing, changed = [], []
    for rel in tracked_files(source):
        dst = os.path.join(target, rel)
        if not os.path.isfile(dst):
            missing.append(rel)
        elif digest(dst) != digest(os.path.join(source, rel)):
            changed.append(rel)
    return {"missing": missing, "changed": changed}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True)
    ap.add_argument("--target", action="append", default=[])
    args = ap.parse_args()
    if not os.path.isdir(os.path.join(args.source, ".claude")) or not args.target:
        print("super-board-drift: cần --source <repo có .claude> và ít nhất một --target", file=sys.stderr)
        return 64
    src = os.path.realpath(args.source)
    result = {}
    for t in args.target:
        if os.path.realpath(t) != src:
            result[t] = compare(src, t)
    drifted = any(v["missing"] or v["changed"] for v in result.values())
    print(json.dumps({"source": args.source, "targets": result, "drifted": drifted}, ensure_ascii=False))
    return 1 if drifted else 0


if __name__ == "__main__":
    sys.exit(main())
