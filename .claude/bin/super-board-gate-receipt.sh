#!/usr/bin/env bash
# #671 AC1: in mã biên nhận (fp) của gate cho một head SHA, đọc từ store chung của git common dir,
# nên review worker ở worktree khác lấy được mà không cần mã trong comment builder/QA.
# Dùng: super-board-gate-receipt.sh <sha40>   → stdout: fp, exit 0 · exit 1: head chưa có biên nhận (chạy gate scoped trên head)
#   · exit 2: lỗi kỹ thuật (không nạp được tree_fp, git lỗi hoặc quá hạn; chi tiết ở stderr) · 64: sai tham số.
# Nguồn 1: scoped_receipts/*.json và tree_receipts/*.json (lượt gate thật: --scoped (#741: không tự leo), hoặc --full tường minh; exit 0, trường "head" = HEAD lúc chạy; khoá theo cây làm việc nên tìm theo head).
# Nguồn 2: task_receipts/<commit_fingerprint(head)>.json (lượt không --scoped trên cây sạch).
set -u
SHA="${1:-}"
case "$SHA" in *[!0-9a-f]* | "") echo "usage: $0 <sha40>" >&2; exit 64 ;; esac
[ "${#SHA}" = 40 ] || { echo "usage: $0 <sha40>" >&2; exit 64; }
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 64; }
COMMON="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)" || { echo "gate-receipt: không tìm được git common dir" >&2; exit 2; }
STORE="$COMMON/postfix-gate"
FP="$(python3 -I - "$STORE" "$SHA" "$ROOT" <<'PYEOF'
import glob, json, os, subprocess, sys
store, sha, root = sys.argv[1:4]
sys.path.insert(0, os.path.join(root, ".agents", "devkit", "bin"))
try:
    import tree_fp
except ImportError as e:
    print("gate-receipt: không nạp được tree_fp: %s" % e, file=sys.stderr)
    sys.exit(2)
# Cây bẩn không phủ commit sạch (L10 của push_gate): file dirty chỉ qua khi trùng blob ở head, là file cài đặt worktree
# hoặc nằm trong tree_fp.EXCLUDE (không tính vào fingerprint).
SETUP = {".claude/settings.json", ".claude/settings.local.json"}
def excluded(p):
    return p in SETUP or any(p == e or p.startswith(e + "/") for e in tree_fp.EXCLUDE)
def clean(d):
    dirty = d.get("dirty")
    if not isinstance(dirty, dict):
        return False
    for p, v in dirty.items():
        if excluded(p):
            continue
        r = subprocess.run(["git", "-C", root, "rev-parse", "--verify", "-q", sha + ":" + p], capture_output=True, text=True, timeout=30)
        if r.returncode != 0 or r.stdout.strip() != v:
            return False
    return True
try:
    for f in sorted(glob.glob(os.path.join(store, "scoped_receipts", "*.json")) + glob.glob(os.path.join(store, "tree_receipts", "*.json"))):
        try:
            with open(f, encoding="utf-8") as fh:
                d = json.load(fh)
        except (OSError, ValueError):
            continue
        if not isinstance(d, dict) or d.get("carried_from"):
            continue   # bản chép `worktree finish` đưa sang main: không cho mượn (như đầu đọc của post-fix-gate.py)
        ex = d.get("exit")
        if ex == 0 and not isinstance(ex, bool) and d.get("head") == sha and d.get("fingerprint") and clean(d):
            print(d["fingerprint"])
            break
except (subprocess.TimeoutExpired, OSError) as e:
    print("gate-receipt: lỗi khi đọc biên nhận: %s" % e, file=sys.stderr)
    sys.exit(2)
PYEOF
)" || exit 2
if [ -n "$FP" ]; then printf '%s\n' "$FP"; exit 0; fi
FP="$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import tree_fp; print(tree_fp.commit_fingerprint(sys.argv[2], sys.argv[3], timeout=60))' \
  "$ROOT/.agents/devkit/bin" "$ROOT" "$SHA")" || { echo "gate-receipt: không tính được fingerprint của $SHA" >&2; exit 2; }
[ -n "$FP" ] || { echo "gate-receipt: không tính được fingerprint của $SHA (git lỗi)" >&2; exit 2; }
[ -f "$STORE/task_receipts/$FP.json" ] || exit 1
printf '%s\n' "$FP"
