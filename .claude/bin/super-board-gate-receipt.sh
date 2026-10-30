#!/usr/bin/env bash
# #671 AC1: in mã biên nhận (fp) của gate cho một head SHA, đọc từ store chung của git common dir,
# nên review worker ở worktree khác lấy được mà không cần mã trong comment builder/QA.
# Dùng: super-board-gate-receipt.sh <sha40>   → stdout: fp, exit 0 · exit 1: head chưa có biên nhận (chạy gate scoped trên head) · 64: sai tham số.
# Nguồn 1: scoped_receipts/*.json và tree_receipts/*.json (lượt gate thật: --scoped, hoặc --full khi nó tự leo; exit 0, trường "head" = HEAD lúc chạy; khoá theo cây làm việc nên tìm theo head).
# Nguồn 2: task_receipts/<commit_fingerprint(head)>.json (lượt không --scoped trên cây sạch).
set -u
SHA="${1:-}"
case "$SHA" in *[!0-9a-f]* | "") echo "usage: $0 <sha40>" >&2; exit 64 ;; esac
[ "${#SHA}" = 40 ] || { echo "usage: $0 <sha40>" >&2; exit 64; }
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 64; }
COMMON="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)" || exit 1
STORE="$COMMON/postfix-gate"
FP="$(python3 -I -c '
import glob, json, os, subprocess, sys
store, sha, root = sys.argv[1:4]
# Cây bẩn không phủ commit sạch (L10 của push_gate): file dirty chỉ qua khi trùng blob ở head, hoặc là file cài đặt worktree.
SETUP = {".claude/settings.json", ".claude/settings.local.json"}
def clean(d):
    dirty = d.get("dirty")
    if not isinstance(dirty, dict):
        return False
    for p, v in dirty.items():
        if p in SETUP:
            continue
        r = subprocess.run(["git", "-C", root, "rev-parse", "--verify", "-q", sha + ":" + p], capture_output=True, text=True)
        if r.returncode != 0 or r.stdout.strip() != v:
            return False
    return True
for f in sorted(glob.glob(os.path.join(store, "scoped_receipts", "*.json")) + glob.glob(os.path.join(store, "tree_receipts", "*.json"))):
    try:
        d = json.load(open(f))
    except (OSError, ValueError):
        continue
    if isinstance(d, dict) and d.get("exit") == 0 and d.get("head") == sha and d.get("fingerprint") and clean(d):
        print(d["fingerprint"])
        break
' "$STORE" "$SHA" "$ROOT" 2>/dev/null)"
if [ -n "$FP" ]; then printf '%s\n' "$FP"; exit 0; fi
FP="$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import tree_fp; print(tree_fp.commit_fingerprint(sys.argv[2], sys.argv[3], timeout=60))' \
  "$ROOT/.agents/devkit/bin" "$ROOT" "$SHA" 2>/dev/null)" || exit 1
[ -n "$FP" ] || exit 1
[ -f "$STORE/task_receipts/$FP.json" ] || exit 1
printf '%s\n' "$FP"
