#!/usr/bin/env bash
# Test hồi quy #671 AC1: review worker lấy gate_receipt theo head SHA (không đọc task_pass.json của worktree mình, không cần mã trong comment).
#  - head có biên nhận task trong store chung -> in fp, exit 0 (từ worktree KHÁC với worktree đã chạy gate)
#  - head không có biên nhận -> exit 1, không in gì; biên nhận của head KHÁC, exit≠0, exit=false, bản chép (carried_from) -> exit 1
#  - cây làm việc bẩn ở file thật -> không nhận; chỉ lệch ở file cài đặt worktree -> nhận
#  - sha rác -> exit 64
# Mọi biên nhận ghi bằng bộ ghi thật write_full_pass_receipt của gate (writer.py bên dưới); ca giả mạo chỉ sửa trường của biên nhận thật.
# Tương thích bash 3.2.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/.claude/bin/super-board-gate-receipt.sh"
FAILS=0
ok() { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sb-671r.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
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

# writer.py <repo> <gate> <exit> [scoped] [untested]: ghi biên nhận bằng bộ ghi thật, in fingerprint cây đã ghi
cat > "$TMP/writer.py" <<'PYEOF'
import importlib.util, sys
repo, gate, code = sys.argv[1], sys.argv[2], int(sys.argv[3])
scoped = len(sys.argv) > 4 and sys.argv[4] == "scoped"
untested = ["X"] if len(sys.argv) > 5 else None
sys.path.insert(0, gate.rsplit("/", 1)[0])
spec = importlib.util.spec_from_file_location("pfg", gate)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
import tree_fp
fp = tree_fp.tree_fingerprint(repo)
kw = {"scoped": {"why": "t"}} if scoped else {}
m.write_full_pass_receipt(repo, code, tests=[], tested_fp=fp, untested=untested, **kw)
print(fp)
PYEOF
GATE_PY="$ROOT/.agents/devkit/bin/post-fix-gate.py"
count_receipts() { ls "$COMMON"/postfix-gate/scoped_receipts/*.json "$COMMON"/postfix-gate/tree_receipts/*.json 2>/dev/null | wc -l | tr -d ' '; }
# write_receipt <exit> [scoped] [untested]: ghi bằng bộ ghi thật; đặt WFP = fingerprint ghi; trả 0 chỉ khi writer thoát 0 VÀ file biên nhận mới xuất hiện
write_receipt() {
  local before after
  before="$(count_receipts)"
  WFP="$(python3 -I "$TMP/writer.py" "$TMP/repo" "$GATE_PY" "$@" 2>"$TMP/writer.err")" || { echo "writer rc≠0: $(tail -3 "$TMP/writer.err")"; return 1; }
  [ "$1" = 0 ] || return 0   # exit≠0 không vào store biên nhận theo cây: chỉ cần writer thoát 0
  after="$(count_receipts)"
  [ "$after" -gt "$before" ] || { echo "no new receipt file (before=$before after=$after)"; return 1; }
}
# forge <số hiệu> <head> <python-sửa-d>: bản sao biên nhận exit-0 thật (tree_receipts) với head khác và trường bị sửa; chỉ để dựng ca âm
forge() {
  python3 -I - "$COMMON/postfix-gate/tree_receipts" "$1" "$2" "$3" <<'PYEOF'
import glob, json, os, sys
d_, name, head, edit = sys.argv[1:5]
src = sorted(glob.glob(os.path.join(d_, "*.json")))[-1]
with open(src, encoding="utf-8") as fh:
    d = json.load(fh)
d["head"] = head
exec(edit)
with open(os.path.join(d_, "forged-" + name + ".json"), "w", encoding="utf-8") as fh:
    json.dump(d, fh)
PYEOF
}
run_script() { out="$(cd "$TMP/wt" && bash "$SCRIPT" "$1" 2>/dev/null)"; rc=$?; }

run_script "$HEAD_SHA"
if [ "$rc" = 0 ] && [ "$out" = "$FP" ]; then ok "A: head with stored task receipt -> fp from another worktree"; else fail "A: rc=$rc out=$out"; fi

echo b > "$TMP/repo/b.txt"; $G add -A && $G -c user.name=t -c user.email=t@t commit -q -m two
run_script "$($G rev-parse HEAD)"
if [ "$rc" = 1 ] && [ -z "$out" ]; then ok "B: head with no receipt -> exit 1, silent"; else fail "B: rc=$rc out=$out"; fi

# D: biên nhận scoped do BỘ GHI THẬT của gate tạo, trên cây làm việc lệch commit (file thật sửa chưa commit)
echo dirty >> "$TMP/repo/a.txt"
HEAD2="$($G rev-parse HEAD)"
write_receipt 0 scoped > "$TMP/wmsg"; wrc=$?; msg="$(cat "$TMP/wmsg")"
run_script "$HEAD2"
if [ "$wrc" = 0 ] && [ "$rc" = 1 ] && [ -z "$out" ]; then ok "D1: receipt of a tree dirty in a real file is not accepted for the clean commit (R1)"; else fail "D1: wrc=$wrc ($msg) rc=$rc out=$out"; fi

# D2: lệch chỉ ở file cài đặt worktree (.claude/settings.json, như worktree add sửa) -> nhận đúng fp đã ghi
$G checkout -q -- a.txt
mkdir -p "$TMP/repo/.claude"; echo '{}' > "$TMP/repo/.claude/settings.json"
$G add -f .claude/settings.json && $G -c user.name=t -c user.email=t@t commit -q -m settings
HEAD2="$($G rev-parse HEAD)"
echo '{"x":1}' > "$TMP/repo/.claude/settings.json"
write_receipt 0 scoped > "$TMP/wmsg"; wrc=$?; msg="$(cat "$TMP/wmsg")"
run_script "$HEAD2"
if [ "$wrc" = 0 ] && [ "$rc" = 0 ] && [ -n "$WFP" ] && [ "$out" = "$WFP" ]; then ok "D2: receipt dirty only in worktree-setup file is accepted, with the fp the gate wrote"; else fail "D2: wrc=$wrc ($msg) rc=$rc out=$out wfp=$WFP"; fi
$G checkout -q -- .claude/settings.json

# D3: lệch chỉ ở file nằm trong tree_fp.EXCLUDE (reports/, không tính vào fingerprint) -> nhận đúng fp đã ghi (head riêng để không trùng D2)
echo e > "$TMP/repo/e.txt"; $G add -A && $G -c user.name=t -c user.email=t@t commit -q -m exclude
HEAD2X="$($G rev-parse HEAD)"
mkdir -p "$TMP/repo/reports"; echo r > "$TMP/repo/reports/r.txt"
write_receipt 0 scoped > "$TMP/wmsg"; wrc=$?; msg="$(cat "$TMP/wmsg")"
run_script "$HEAD2X"
if [ "$wrc" = 0 ] && [ "$rc" = 0 ] && [ -n "$WFP" ] && [ "$out" = "$WFP" ]; then ok "D3: receipt dirty only in a tree_fp.EXCLUDE path is accepted, with the fp the gate wrote"; else fail "D3: wrc=$wrc ($msg) rc=$rc out=$out wfp=$WFP"; fi
rm -f "$TMP/repo/reports/r.txt"

# E: lượt gate tự leo --full ghi tree_receipts (không scoped_receipts): cũng tìm được theo head, đúng fp đã ghi
echo more >> "$TMP/repo/a.txt"
$G -c user.name=t -c user.email=t@t commit -q -am three
HEAD3="$($G rev-parse HEAD)"
write_receipt 0 > "$TMP/wmsg"; wrc=$?; msg="$(cat "$TMP/wmsg")"
run_script "$HEAD3"
if [ "$wrc" = 0 ] && [ "$rc" = 0 ] && [ -n "$WFP" ] && [ "$out" = "$WFP" ]; then ok "E: real full receipt (tree_receipts) found by head, with the fp the gate wrote"; else fail "E: wrc=$wrc ($msg) rc=$rc out=$out wfp=$WFP"; fi

# F: biên nhận của head KHÁC: commit thêm HEAD4 không chạy gate -> không mượn biên nhận của HEAD3
echo four > "$TMP/repo/d.txt"; $G add -A && $G -c user.name=t -c user.email=t@t commit -q -m four
HEAD4="$($G rev-parse HEAD)"
run_script "$HEAD4"
if [ "$rc" = 1 ] && [ -z "$out" ]; then ok "F: receipt of another head is not borrowed -> exit 1, silent"; else fail "F: rc=$rc out=$out"; fi

# G: biên nhận exit≠0 ghi bằng bộ ghi thật (exit 4 + untested) trên head sạch -> exit 1
write_receipt 4 full X > "$TMP/wmsg"; wrc=$?; msg="$(cat "$TMP/wmsg")"
run_script "$HEAD4"
if [ "$wrc" = 0 ] && [ "$rc" = 1 ] && [ -z "$out" ]; then ok "G1: real exit-4 receipt on the clean head -> exit 1"; else fail "G1: wrc=$wrc ($msg) rc=$rc out=$out"; fi

# G2-G4: bản sao biên nhận thật của HEAD3 gắn head=HEAD4 với trường bị sửa -> không nhận; bản đúng exit 0 -> nhận (đối chứng)
forge exit2 "$HEAD4" 'd["exit"] = 2'; run_script "$HEAD4"
if [ "$rc" = 1 ] && [ -z "$out" ]; then ok "G2: exit 2 receipt at the head -> exit 1"; else fail "G2: rc=$rc out=$out"; fi
rm -f "$COMMON"/postfix-gate/tree_receipts/forged-*.json
forge exitfalse "$HEAD4" 'd["exit"] = False'; run_script "$HEAD4"
if [ "$rc" = 1 ] && [ -z "$out" ]; then ok "G3: exit=false (== 0 in python) receipt -> exit 1"; else fail "G3: rc=$rc out=$out"; fi
rm -f "$COMMON"/postfix-gate/tree_receipts/forged-*.json
forge carried "$HEAD4" 'd["carried_from"] = "/elsewhere"'; run_script "$HEAD4"
if [ "$rc" = 1 ] && [ -z "$out" ]; then ok "G4: carried_from copy -> exit 1"; else fail "G4: rc=$rc out=$out"; fi
rm -f "$COMMON"/postfix-gate/tree_receipts/forged-*.json
forge control "$HEAD4" 'pass'; run_script "$HEAD4"
if [ "$rc" = 0 ] && [ -n "$out" ]; then ok "G5: control, the same copy untouched is accepted (so G2-G4 are discriminating)"; else fail "G5: rc=$rc out=$out"; fi
rm -f "$COMMON"/postfix-gate/tree_receipts/forged-*.json

(cd "$TMP/wt" && bash "$SCRIPT" "not-a-sha" >/dev/null 2>&1); rc=$?
if [ "$rc" = 64 ]; then ok "C: bad sha -> exit 64"; else fail "C: rc=$rc"; fi

[ "$FAILS" = 0 ] && echo "PASS" || { echo "FAIL ($FAILS)"; exit 1; }
