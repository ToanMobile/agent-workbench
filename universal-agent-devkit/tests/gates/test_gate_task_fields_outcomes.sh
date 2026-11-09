#!/usr/bin/env bash
# Test hồi quy (gate speed v14, mục 1 phần PFG): hợp đồng dữ liệu cho Stop hook đọc biên nhận thay vì chạy gate.
#   a  biên nhận task (task_pass.json + task_receipts/<fp>.json) có đủ exit, result_format, gate_sha, matrix_sha, local_sha, local_regen
#   b  exit 3 "không có gì để kiểm" ghi <git dir>/postfix-gate/outcomes/<fp>.json {exit, reason, lines, base}
#   c  suite không chạy được ở máy này (untested_exit) ⇒ outcome reason device_untested
#   d  ma trận chưa commit ⇒ outcome reason matrix
#   e  test có sẵn bị sửa ⇒ outcome reason edited_test
#   f  suite đỏ vì môi trường (exit 127) ⇒ outcome reason env; đỏ thật ⇒ không có outcome
#   g  lượt exit 0 bỏ outcome cũ của cùng cây
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u
unset DEVKIT_GATE_CACHE DEVKIT_SUITE_CACHE CI DEVKIT_SCOPED_TESTS DEVKIT_IMPACTED_SINCE GATE_TOTAL_BUDGET_S DEVKIT_GATE_MERGE_CHECK \
      DEVKIT_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WORKTREE_TRUNK_MODE DEVKIT_SLOT_PRIORITY
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$DEVKIT_DIR/bin/post-fix-gate.py"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
export SB_HEAVY_SLOT_DIR="$TMP/slots"; mkdir -p "$SB_HEAVY_SLOT_DIR"
FAILS=0
ok()   { echo "✔ $1"; }
fail() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

new_repo() {   # new_repo <dir> <lệnh suite>: origin + clone, nhánh feature
  local d="$1" cmd="$2"
  git init -q --bare -b main "$d.git" && git clone -q "$d.git" "$d" 2>/dev/null || exit 1
  ( cd "$d" && git config user.email t@t && git config user.name t && mkdir -p src .agents tests/gates
    echo "def ok(): return 1" > src/core.py
    echo '{"profile":"backend"}' > .agents/active-profile.json
    printf '.claude/\n.agents/CHECKLIST.md\n.agents/regression_status.json\n' > .gitignore
    printf '#!/usr/bin/env bash\necho ok\n' > tests/gates/test_x.sh
    python3 - "$cmd" <<'PY'
import json, sys
json.dump({"project": "t", "rules": [{"component": "Core", "watch_files": ["src/*", "tests/*"],
    "mandatory_regression_tests": [dict({"id": "REG-1", "name": "core", "command": sys.argv[1]}, **({"untested_exit": 44} if "44" in sys.argv[1] else {}))]}]},
    open(".agents/regression_matrix.active.json", "w"))
PY
    git add -A && git commit -qm init && git push -q -u origin main 2>/dev/null
    git checkout -q -b feature ) || exit 1
}
outcome() {   # outcome <repo> <biểu thức python trên d>: in giá trị, rỗng khi không có file
  python3 - "$DEVKIT_DIR/bin" "$1" "$2" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[1]); import tree_fp
repo = sys.argv[2]
fp = tree_fp.tree_fingerprint(repo)
p = os.path.join(os.path.dirname(tree_fp.receipt_path(repo)), "outcomes", fp + ".json")
if os.path.exists(p):
    d = json.load(open(p))
    print(eval(sys.argv[3]))
PY
}
gate() { ( cd "$1" && shift && python3 "$GATE" --run-tests --scoped --brief "$@" ) >"$TMP/out" 2>&1; }

# a. biên nhận task
R="$TMP/a"; new_repo "$R" true
( cd "$R" && echo "def ok(): return 2" > src/core.py && git commit -qam edit )
gate "$R"; RC=$?
[ "$RC" -eq 0 ] && ok "a. lượt task exit 0" || { fail "a. lượt task exit $RC"; tail -30 "$TMP/out"; }
A="$(python3 - "$R" <<'PY'
import glob, json, os, subprocess, sys
repo = sys.argv[1]
g = subprocess.run(["git", "-C", repo, "rev-parse", "--absolute-git-dir"], capture_output=True, text=True).stdout.strip()
paths = [os.path.join(g, "postfix-gate", "task_pass.json")] + glob.glob(os.path.join(g, "postfix-gate", "task_receipts", "*.json"))
for p in paths:
    d = json.load(open(p))
    miss = [k for k in ("exit", "result_format", "gate_sha", "matrix_sha", "local_sha", "local_regen") if k not in d]
    print("miss=" + ",".join(miss), "exit=%s" % d.get("exit"))
print(len(paths))
PY
)"
case "$A" in *"miss="[a-z]*) fail "a. biên nhận task thiếu trường: $A" ;;
  *"exit=0"*"2") ok "a. task_pass.json và mục store có đủ trường, exit 0" ;; *) fail "a. biên nhận task: $A" ;; esac

# b. exit 3
R="$TMP/b"; new_repo "$R" true
( cd "$R" && git checkout -q main )
gate "$R"; RC=$?
[ "$RC" -eq 3 ] && ok "b. cây sạch trên main exit 3" || fail "b. mong exit 3, được $RC"
[ "$(outcome "$R" 'd["exit"], d["reason"]')" = "(3, 'nothing')" ] && ok "b. outcome exit 3 reason nothing" || fail "b. outcome: $(outcome "$R" 'd')"
[ "$(outcome "$R" 'd["base"]')" = "$(git -C "$R" rev-parse HEAD)" ] && ok "b. outcome ghi base là sha commit" || fail "b. base: $(outcome "$R" 'd.get("base")')"
[ -n "$(outcome "$R" '"".join(d["lines"])')" ] && ok "b. outcome có dòng để in" || fail "b. lines rỗng"

# c. untested_exit
R="$TMP/c"; new_repo "$R" "exit 44"
( cd "$R" && echo "def ok(): return 2" > src/core.py && git commit -qam edit )
gate "$R"; RC=$?
[ "$RC" -eq 4 ] && [ "$(outcome "$R" 'd["reason"]')" = device_untested ] && ok "c. untested_exit ⇒ outcome device_untested" || { fail "c. rc=$RC outcome=$(outcome "$R" 'd')"; tail -20 "$TMP/out"; }

# d. ma trận chưa commit
R="$TMP/d"; new_repo "$R" true
( cd "$R" && echo "def ok(): return 2" > src/core.py && git commit -qam edit
  python3 - <<'PY'
import json
p = ".agents/regression_matrix.active.json"; d = json.load(open(p)); d["rules"][0]["watch_files"] = ["other/*"]; json.dump(d, open(p, "w"))
PY
)
gate "$R"; RC=$?
[ "$RC" -eq 2 ] && [ "$(outcome "$R" 'd["reason"]')" = matrix ] && ok "d. ma trận chưa commit ⇒ outcome matrix" || { fail "d. rc=$RC outcome=$(outcome "$R" 'd')"; tail -20 "$TMP/out"; }

# e. test có sẵn bị sửa
R="$TMP/e"; new_repo "$R" true
( cd "$R" && printf '#!/usr/bin/env bash\necho changed\n' > tests/gates/test_x.sh && git commit -qam edit )
gate "$R"; RC=$?
[ "$RC" -eq 2 ] && [ "$(outcome "$R" 'd["reason"]')" = edited_test ] && ok "e. test sửa ⇒ outcome edited_test" || { fail "e. rc=$RC outcome=$(outcome "$R" 'd')"; tail -20 "$TMP/out"; }

# f. môi trường, rồi đỏ thật
R="$TMP/f"; new_repo "$R" "exit 127"
( cd "$R" && echo "def ok(): return 2" > src/core.py && git commit -qam edit )
gate "$R"; RC=$?
[ "$RC" -eq 1 ] && [ "$(outcome "$R" 'd["reason"]')" = env ] && ok "f. exit 127 ⇒ outcome env" || { fail "f. rc=$RC outcome=$(outcome "$R" 'd')"; tail -20 "$TMP/out"; }
R="$TMP/f2"; new_repo "$R" "exit 7"
( cd "$R" && echo "def ok(): return 2" > src/core.py && git commit -qam edit )
gate "$R"; RC=$?
[ "$RC" -eq 1 ] && [ -z "$(outcome "$R" 'd')" ] && ok "f. đỏ thật không để outcome" || fail "f. đỏ thật rc=$RC outcome=$(outcome "$R" 'd')"

# g. exit 0 bỏ outcome cũ của cùng cây
R="$TMP/g"; new_repo "$R" true
( cd "$R" && echo "def ok(): return 2" > src/core.py && git commit -qam edit )
python3 - "$DEVKIT_DIR/bin" "$R" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[1]); import tree_fp
p = os.path.join(os.path.dirname(tree_fp.receipt_path(sys.argv[2])), "outcomes", tree_fp.tree_fingerprint(sys.argv[2]) + ".json")
os.makedirs(os.path.dirname(p), exist_ok=True); json.dump({"exit": 3, "reason": "nothing", "lines": ["x"], "base": ""}, open(p, "w"))
PY
gate "$R"; RC=$?
[ "$RC" -eq 0 ] && [ -z "$(outcome "$R" 'd')" ] && ok "g. exit 0 bỏ outcome cũ của cây" || fail "g. rc=$RC outcome=$(outcome "$R" 'd')"

[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; }
echo "failures: $FAILS"; exit 1
