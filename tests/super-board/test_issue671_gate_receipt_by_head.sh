#!/usr/bin/env bash
# Test hồi quy #671 AC1: review worker lấy gate_receipt theo head SHA (không đọc task_pass.json của worktree mình, không cần mã trong comment).
#  - head có biên nhận task trong store chung -> in fp, exit 0 (từ worktree KHÁC với worktree đã chạy gate)
#  - head không có biên nhận -> exit 1, không in gì
#  - sha rác -> exit 64
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/.claude/bin/super-board-gate-receipt.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-671r.XXXXXX")"
trap 'rm -r "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
G="git -C $TMP/repo"
git init -q "$TMP/repo" && mkdir -p "$TMP/repo/.agents/devkit" && cp -R "$ROOT/.agents/devkit/bin" "$TMP/repo/.agents/devkit/bin" 2>/dev/null
echo a > "$TMP/repo/a.txt"
$G add -A && $G -c user.name=t -c user.email=t@t commit -q -m one
HEAD_SHA="$($G rev-parse HEAD)"
FP="$(python3 -I -c "import sys; sys.path.insert(0, sys.argv[1]); import tree_fp; print(tree_fp.commit_fingerprint(sys.argv[2], sys.argv[3]))" "$TMP/repo/.agents/devkit/bin" "$TMP/repo" "$HEAD_SHA")"
[ -n "$FP" ] || { echo "✖ no fingerprint"; exit 1; }
COMMON="$($G rev-parse --path-format=absolute --git-common-dir)"
mkdir -p "$COMMON/postfix-gate/task_receipts"
printf '{"scope":"task","fp":"%s"}\n' "$FP" > "$COMMON/postfix-gate/task_receipts/$FP.json"
# worktree khác: không có task_pass.json riêng
$G worktree add -q --detach "$TMP/wt" "$HEAD_SHA"

out="$(cd "$TMP/wt" && bash "$SCRIPT" "$HEAD_SHA" 2>/dev/null)"; rc=$?
if [ "$rc" = 0 ] && [ "$out" = "$FP" ]; then ok "A: head with stored task receipt -> fp from another worktree"; else fail "A: rc=$rc out=$out"; fi

echo b > "$TMP/repo/b.txt"; $G add -A && $G -c user.name=t -c user.email=t@t commit -q -m two
out="$(cd "$TMP/wt" && bash "$SCRIPT" "$($G rev-parse HEAD)" 2>/dev/null)"; rc=$?
if [ "$rc" = 1 ] && [ -z "$out" ]; then ok "B: head with no receipt -> exit 1, silent"; else fail "B: rc=$rc out=$out"; fi

# D: biên nhận scoped do BỘ GHI THẬT của gate tạo, trên cây làm việc lệch commit (như .claude/settings.json do worktree setup sửa)
echo dirty >> "$TMP/repo/a.txt"
HEAD2="$($G rev-parse HEAD)"
python3 -I - "$TMP/repo" "$ROOT/.agents/devkit/bin/post-fix-gate.py" <<'PY' >/dev/null 2>&1
import importlib.util, sys
repo, gate = sys.argv[1:3]
sys.path.insert(0, gate.rsplit("/", 1)[0])
spec = importlib.util.spec_from_file_location("pfg", gate)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
import tree_fp
fp = tree_fp.tree_fingerprint(repo)
m.write_full_pass_receipt(repo, 0, tests=[], tested_fp=fp, scoped={"why": "t"})
PY
out="$(cd "$TMP/wt" && bash "$SCRIPT" "$HEAD2" 2>/dev/null)"; rc=$?
if [ "$rc" = 0 ] && [ -n "$out" ]; then ok "D: real scoped receipt (tree-keyed) found by head"; else fail "D: rc=$rc out=$out"; fi

(cd "$TMP/wt" && bash "$SCRIPT" "not-a-sha" >/dev/null 2>&1); rc=$?
if [ "$rc" = 64 ]; then ok "C: bad sha -> exit 64"; else fail "C: rc=$rc"; fi

[ "$FAILS" = 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
