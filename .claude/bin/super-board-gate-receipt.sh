#!/usr/bin/env bash
# #671 AC1: in mã biên nhận task (fp) của gate scoped cho một head SHA, đọc từ store chung của git common dir,
# nên review worker ở worktree khác lấy được mà không cần mã trong comment builder/QA.
# Dùng: super-board-gate-receipt.sh <sha40>   → stdout: fp, exit 0 · exit 1: head chưa có biên nhận (chạy gate scoped trên head) · 64: sai tham số.
# fp = tree_fp.commit_fingerprint(head) (cùng khoá write_task_receipt ghi), nên commit chỉ thêm docs/super-board/runs không đổi nó.
set -u
SHA="${1:-}"
case "$SHA" in *[!0-9a-f]* | "") echo "usage: $0 <sha40>" >&2; exit 64 ;; esac
[ "${#SHA}" = 40 ] || { echo "usage: $0 <sha40>" >&2; exit 64; }
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 64; }
FP="$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import tree_fp; print(tree_fp.commit_fingerprint(sys.argv[2], sys.argv[3], timeout=60))' \
  "$ROOT/.agents/devkit/bin" "$ROOT" "$SHA" 2>/dev/null)" || exit 1
[ -n "$FP" ] || exit 1
COMMON="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)" || exit 1
[ -f "$COMMON/postfix-gate/task_receipts/$FP.json" ] || exit 1
printf '%s\n' "$FP"
